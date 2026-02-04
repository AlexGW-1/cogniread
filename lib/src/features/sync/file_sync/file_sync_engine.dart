import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/library/data/free_notes_store.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/features/sync/data/event_log_store.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_file_models.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:path/path.dart' as p;

class FileSyncEngine {
  FileSyncEngine({
    required SyncAdapter adapter,
    required LibraryStore libraryStore,
    FreeNotesStore? freeNotesStore,
    required EventLogStore eventLogStore,
    required String deviceId,
    required StorageService storageService,
    this.basePath = '',
    this.maxConcurrentBookUploads = 2,
  })  : _adapter = adapter,
        _libraryStore = libraryStore,
        _freeNotesStore = freeNotesStore,
        _eventLogStore = eventLogStore,
        _deviceId = deviceId,
        _storageService = storageService;

  final SyncAdapter _adapter;
  final LibraryStore _libraryStore;
  final FreeNotesStore? _freeNotesStore;
  final EventLogStore _eventLogStore;
  final String _deviceId;
  final StorageService _storageService;
  final String basePath;
  final int maxConcurrentBookUploads;
  _SyncMetricsTracker? _metrics;

  Future<FileSyncResult> sync() async {
    final stopwatch = Stopwatch()..start();
    Log.d('FileSyncEngine: sync started');
    final now = DateTime.now().toUtc();
    _metrics = _SyncMetricsTracker();
    try {
      final remoteEvents = await _readEventLog();
      final remoteState = await _readState();
      final booksSync = await _syncBooks();
      Log.d(
        'FileSyncEngine: remote events=${remoteEvents.events.length}, '
        'state=${remoteState.readingPositions.length}, '
        'books uploaded=${booksSync.uploaded}, downloaded=${booksSync.downloaded}',
      );

      final localEvents = _eventLogStore.listEvents();
      final localEventIds = localEvents.map((event) => event.id).toSet();

      var appliedEvents = 0;
      for (final event in remoteEvents.events) {
        if (localEventIds.contains(event.id)) {
          continue;
        }
        final applied = await _applyEvent(event);
        if (applied) {
          appliedEvents += 1;
        }
        await _eventLogStore.addEvent(event);
        localEventIds.add(event.id);
      }

      final appliedState = await _applyState(remoteState);
      Log.d(
        'FileSyncEngine: applied events=$appliedEvents, '
        'applied state=$appliedState',
      );

      final mergedEvents = _eventLogStore.listEvents()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final cursor = mergedEvents.isEmpty ? null : mergedEvents.last.id;
      final eventLogFile = SyncEventLogFile(
        schemaVersion: 1,
        deviceId: _deviceId,
        generatedAt: now,
        cursor: cursor,
        events: mergedEvents,
      );
      final stateFile = await _buildStateFile(cursor: cursor, now: now);
      final metaFile = SyncMetaFile(
        schemaVersion: 1,
        deviceId: _deviceId,
        lastUploadAt: now,
        lastDownloadAt: now,
        eventCount: mergedEvents.length,
      );

      await _safePutFile(
        _path('event_log.json'),
        eventLogFile.toJsonBytes(),
        contentType: 'application/json',
      );
      await _safePutFile(
        _path('state.json'),
        stateFile.toJsonBytes(),
        contentType: 'application/json',
      );
      await _safePutFile(
        _path('meta.json'),
        metaFile.toJsonBytes(),
        contentType: 'application/json',
      );

      final result = FileSyncResult(
        appliedEvents: appliedEvents,
        appliedState: appliedState,
        uploadedEvents: mergedEvents.length,
        uploadedAt: now,
        booksUploaded: booksSync.uploaded,
        booksDownloaded: booksSync.downloaded,
        durationMs: stopwatch.elapsedMilliseconds,
        bytesUploaded: _metrics?.bytesUploaded ?? 0,
        bytesDownloaded: _metrics?.bytesDownloaded ?? 0,
        filesUploaded: _metrics?.filesUploaded ?? 0,
        filesDownloaded: _metrics?.filesDownloaded ?? 0,
      );
      Log.d(
        'FileSyncEngine: sync finished in ${stopwatch.elapsedMilliseconds} ms',
      );
      return result;
    } on SyncAdapterException catch (error) {
      Log.d('FileSyncEngine: sync failed: $error');
      return FileSyncResult.error(
        error: error,
        uploadedAt: now,
        durationMs: stopwatch.elapsedMilliseconds,
        bytesUploaded: _metrics?.bytesUploaded ?? 0,
        bytesDownloaded: _metrics?.bytesDownloaded ?? 0,
        filesUploaded: _metrics?.filesUploaded ?? 0,
        filesDownloaded: _metrics?.filesDownloaded ?? 0,
      );
    } catch (error) {
      Log.d('FileSyncEngine: sync failed: $error');
      return FileSyncResult.error(
        error: SyncAdapterException(error.toString(), code: 'sync_error'),
        uploadedAt: now,
        durationMs: stopwatch.elapsedMilliseconds,
        bytesUploaded: _metrics?.bytesUploaded ?? 0,
        bytesDownloaded: _metrics?.bytesDownloaded ?? 0,
        filesUploaded: _metrics?.filesUploaded ?? 0,
        filesDownloaded: _metrics?.filesDownloaded ?? 0,
      );
    } finally {
      _metrics = null;
    }
  }

  Future<_BookSyncResult> _syncBooks() async {
    try {
      final remoteIndex = await _readBooksIndex();
      final localEntries = await _libraryStore.loadAll();
      final now = DateTime.now().toUtc();
      final deletedByFingerprint = _collectLocalBookDeletions();
      final result = await _mergeBooks(
        remoteIndex,
        localEntries,
        now,
        deletedByFingerprint,
      );
      final nextIndex = SyncBooksIndexFile(
        schemaVersion: 1,
        generatedAt: now,
        books: result.nextIndex.values.toList(),
      );
      await _putFile(
        _booksIndexPath(),
        nextIndex.toJsonBytes(),
        contentType: 'application/json',
      );
      return _BookSyncResult(
        uploaded: result.uploaded,
        downloaded: result.downloaded,
      );
    } on SyncAdapterException catch (error) {
      Log.d('Book sync skipped due to adapter error: $error');
      if (_isClientError(error)) {
        rethrow;
      }
      return const _BookSyncResult(uploaded: 0, downloaded: 0);
    } catch (error) {
      Log.d('Book sync failed: $error');
      return const _BookSyncResult(uploaded: 0, downloaded: 0);
    }
  }

  Future<_MergeBooksResult> _mergeBooks(
    SyncBooksIndexFile remoteIndex,
    List<LibraryEntry> localEntries,
    DateTime now,
    Map<String, DateTime> deletedByFingerprint,
  ) async {
    final remoteByFp = <String, SyncBookDescriptor>{
      for (final book in remoteIndex.books) book.fingerprint: book,
    };
    final localByFp = <String, LibraryEntry>{
      for (final entry in localEntries) entry.fingerprint: entry,
    };

    final nextIndex = <String, SyncBookDescriptor>{};
    var uploaded = 0;
    var downloaded = 0;

    // Upload or keep local books. Uploads may be parallel, but are capped.
    final uploadJobs = <Future<void> Function()>[];
    for (final entry in localEntries) {
      final file = File(entry.localPath);
      if (!await file.exists()) {
        continue;
      }
      final stat = await file.stat();
      final localDesc = _descriptorFromEntry(entry, stat);
      final remote = remoteByFp[entry.fingerprint];
      final shouldUpload =
          remote == null ||
          _isNewer(localDesc.updatedAt, remote.updatedAt) ||
          remote.size != localDesc.size;

      if (remote != null && remote.deleted) {
        if (_isNewer(localDesc.updatedAt, remote.updatedAt)) {
          // Resurrect locally modified file after a remote tombstone.
        } else {
          // Remote tombstone wins: remove local copy and keep deletion in index.
          await _removeLocalBook(entry);
          nextIndex[remote.fingerprint] = remote;
          continue;
        }
      }
      if (!shouldUpload) {
        nextIndex[localDesc.fingerprint] = remote;
        continue;
      }
      uploadJobs.add(() async {
        final bytes = await file.readAsBytes();
        await _putFile(
          _bookPath(localDesc),
          bytes,
          contentType: _contentTypeForExt(localDesc.extension),
        );
        uploaded += 1;
        nextIndex[localDesc.fingerprint] = localDesc;
      });
    }
    await _runJobs(uploadJobs, maxConcurrentBookUploads);

    // Handle remote-only or deleted books.
    for (final remote in remoteIndex.books) {
      if (nextIndex.containsKey(remote.fingerprint)) {
        continue;
      }
      final deletedAt = deletedByFingerprint[remote.fingerprint];
      final local = localByFp[remote.fingerprint];
      if (deletedAt != null &&
          !remote.deleted &&
          _isNewer(deletedAt, remote.updatedAt)) {
        final tombstone = _tombstoneFromRemote(remote, deletedAt);
        await _deleteRemoteBookFile(remote);
        if (local != null) {
          await _removeLocalBook(local);
        }
        nextIndex[remote.fingerprint] = tombstone;
        continue;
      }
      if (remote.deleted) {
        if (local != null) {
          await _removeLocalBook(local);
        }
        await _deleteRemoteBookFile(remote);
        nextIndex[remote.fingerprint] = remote;
        continue;
      }
      // Download missing book.
      final remotePath = remote.path ?? _defaultBookPath(remote);
      final file = await _getFile(remotePath);
      if (file == null) {
        nextIndex[remote.fingerprint] = remote;
        continue;
      }
      final savedPath = await _saveBookFile(
        remote.fingerprint,
        remote.extension,
        file.bytes,
      );
      final entry = _entryFromDescriptor(remote, savedPath, now);
      await _libraryStore.upsert(entry);
      nextIndex[remote.fingerprint] = remote;
      downloaded += 1;
    }

    return _MergeBooksResult(
      nextIndex: nextIndex,
      uploaded: uploaded,
      downloaded: downloaded,
    );
  }

  Map<String, DateTime> _collectLocalBookDeletions() {
    final deletedByFingerprint = <String, DateTime>{};
    final events = _eventLogStore.listEvents();
    for (final event in events) {
      if (event.entityType != 'book' || event.op != 'delete') {
        continue;
      }
      final payload = _coerceMap(event.payload);
      final fingerprint =
          (payload['fingerprint'] as String?) ??
          (payload['hash'] as String?) ??
          event.entityId;
      if (fingerprint.isEmpty) {
        continue;
      }
      final deletedAt = _extractUpdatedAt(payload) ?? event.createdAt.toUtc();
      final existing = deletedByFingerprint[fingerprint];
      if (existing == null || deletedAt.isAfter(existing)) {
        deletedByFingerprint[fingerprint] = deletedAt;
      }
    }
    return deletedByFingerprint;
  }

  SyncBookDescriptor _tombstoneFromRemote(
    SyncBookDescriptor remote,
    DateTime deletedAt,
  ) {
    return SyncBookDescriptor(
      id: remote.id,
      title: remote.title,
      author: remote.author,
      fingerprint: remote.fingerprint,
      size: remote.size,
      updatedAt: deletedAt.toUtc(),
      extension: remote.extension,
      path: remote.path,
      deleted: true,
    );
  }

  Future<void> _deleteRemoteBookFile(SyncBookDescriptor remote) async {
    final remotePath = remote.path ?? _defaultBookPath(remote);
    try {
      await _adapter.deleteFile(remotePath);
    } on SyncAdapterException catch (error) {
      if (_isNotFound(error)) {
        return;
      }
      Log.d('FileSyncEngine: failed to delete remote book $remotePath: $error');
      if (_isClientError(error)) {
        rethrow;
      }
    } catch (error) {
      Log.d('FileSyncEngine: failed to delete remote book $remotePath: $error');
    }
  }

  Future<void> _runJobs(
    List<Future<void> Function()> jobs,
    int maxConcurrent,
  ) async {
    if (jobs.isEmpty) {
      return;
    }
    final concurrency = maxConcurrent <= 0 ? 1 : maxConcurrent;
    var index = 0;
    Future<void> worker() async {
      while (true) {
        if (index >= jobs.length) {
          return;
        }
        final job = jobs[index];
        index += 1;
        await job();
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        concurrency > jobs.length ? jobs.length : concurrency,
        (_) => worker(),
      ),
    );
  }

  Future<SyncBooksIndexFile> _readBooksIndex() async {
    Log.d('FileSyncEngine: reading ${_booksIndexPath()}');
    try {
      final file = await _getFile(_booksIndexPath());
      if (file == null) {
        Log.d('FileSyncEngine: books_index.json not found, using empty');
        return SyncBooksIndexFile(
          schemaVersion: 1,
          generatedAt: DateTime.now().toUtc(),
          books: const <SyncBookDescriptor>[],
        );
      }
      final decoded = _decodeJsonMap(file.bytes);
      return SyncBooksIndexFile.fromMap(decoded);
    } on SyncAdapterException catch (error) {
      if (_isNotFound(error)) {
        Log.d('FileSyncEngine: books_index.json not found, using empty');
        return SyncBooksIndexFile(
          schemaVersion: 1,
          generatedAt: DateTime.now().toUtc(),
          books: const <SyncBookDescriptor>[],
        );
      }
      Log.d('FileSyncEngine: failed to read books_index.json: $error');
      if (_isClientError(error)) {
        rethrow;
      }
      return SyncBooksIndexFile(
        schemaVersion: 1,
        generatedAt: DateTime.now().toUtc(),
        books: const <SyncBookDescriptor>[],
      );
    }
  }

  SyncBookDescriptor _descriptorFromEntry(
    LibraryEntry entry,
    FileStat stat,
  ) {
    final ext = p.extension(entry.localPath);
    final path = _bookPathForFingerprint(entry.fingerprint, ext);
    final updatedAt = stat.modified.toUtc();
    return SyncBookDescriptor(
      id: entry.id,
      title: entry.title,
      author: entry.author,
      fingerprint: entry.fingerprint,
      size: stat.size,
      updatedAt: updatedAt,
      extension: ext,
      path: path,
      deleted: false,
    );
  }

  Future<String> _saveBookFile(
    String fingerprint,
    String extension,
    List<int> bytes,
  ) async {
    final dir = await _storageService.appStoragePath();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final path = p.join(dir, '$fingerprint$ext');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<void> _removeLocalBook(LibraryEntry entry) async {
    try {
      final file = File(entry.localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    await _libraryStore.remove(entry.id);
  }

  LibraryEntry _entryFromDescriptor(
    SyncBookDescriptor desc,
    String localPath,
    DateTime now,
  ) {
    final title = desc.title.isEmpty ? 'Book ${desc.fingerprint}' : desc.title;
    return LibraryEntry(
      id: desc.id.isEmpty ? desc.fingerprint : desc.id,
      title: title,
      author: desc.author,
      localPath: localPath,
      coverPath: null,
      addedAt: desc.updatedAt,
      fingerprint: desc.fingerprint,
      sourcePath: localPath,
      readingPosition: const ReadingPosition(
        chapterHref: null,
        anchor: null,
        offset: null,
        updatedAt: null,
      ),
      progress: const ReadingProgress(
        percent: null,
        chapterIndex: null,
        totalChapters: null,
        updatedAt: null,
      ),
      lastOpenedAt: null,
      notes: const <Note>[],
      highlights: const <Highlight>[],
      bookmarks: const <Bookmark>[],
      tocOfficial: const <TocNode>[],
      tocGenerated: const <TocNode>[],
      tocMode: TocMode.official,
    );
  }

  String _bookPath(SyncBookDescriptor desc) {
    return desc.path ?? _defaultBookPath(desc);
  }

  String _defaultBookPath(SyncBookDescriptor desc) {
    final ext = desc.extension.startsWith('.') ? desc.extension : '.${desc.extension}';
    return 'books/${desc.fingerprint}$ext';
  }

  String _bookPathForFingerprint(String fingerprint, String ext) {
    final normalized = ext.startsWith('.') ? ext : '.$ext';
    return 'books/$fingerprint$normalized';
  }

  String _booksIndexPath() => _path('books_index.json');

  String _contentTypeForExt(String ext) {
    final lower = ext.toLowerCase();
    switch (lower) {
      case '.epub':
        return 'application/epub+zip';
      case '.fb2':
      case '.fb2.zip':
      case '.zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  Future<SyncEventLogFile> _readEventLog() async {
    Log.d('FileSyncEngine: reading ${_path('event_log.json')}');
    try {
      final file = await _getFile(_path('event_log.json'));
      if (file == null) {
        Log.d('FileSyncEngine: event_log.json not found, using empty');
        return SyncEventLogFile(
          schemaVersion: 1,
          deviceId: _deviceId,
          generatedAt: DateTime.now().toUtc(),
          events: const <EventLogEntry>[],
        );
      }
      final decoded = _decodeJsonMap(file.bytes);
      return SyncEventLogFile.fromMap(decoded);
    } on SyncAdapterException catch (error) {
      if (_isNotFound(error)) {
        Log.d('FileSyncEngine: event_log.json not found, using empty');
        return SyncEventLogFile(
          schemaVersion: 1,
          deviceId: _deviceId,
          generatedAt: DateTime.now().toUtc(),
          events: const <EventLogEntry>[],
        );
      }
      Log.d('FileSyncEngine: failed to read event_log.json: ${error.toString()}');
      if (_isClientError(error)) {
        rethrow;
      }
      return SyncEventLogFile(
        schemaVersion: 1,
        deviceId: _deviceId,
        generatedAt: DateTime.now().toUtc(),
        events: const <EventLogEntry>[],
      );
    }
  }

  Future<SyncStateFile> _readState() async {
    Log.d('FileSyncEngine: reading ${_path('state.json')}');
    try {
      final file = await _getFile(_path('state.json'));
      if (file == null) {
        Log.d('FileSyncEngine: state.json not found, using empty');
        return SyncStateFile(
          schemaVersion: 1,
          generatedAt: DateTime.now().toUtc(),
          readingPositions: const <SyncReadingPosition>[],
        );
      }
      final decoded = _decodeJsonMap(file.bytes);
      return SyncStateFile.fromMap(decoded);
    } on SyncAdapterException catch (error) {
      if (_isNotFound(error)) {
        Log.d('FileSyncEngine: state.json not found, using empty');
        return SyncStateFile(
          schemaVersion: 1,
          generatedAt: DateTime.now().toUtc(),
          readingPositions: const <SyncReadingPosition>[],
        );
      }
      Log.d('FileSyncEngine: failed to read state.json: ${error.toString()}');
      if (_isClientError(error)) {
        rethrow;
      }
      return SyncStateFile(
        schemaVersion: 1,
        generatedAt: DateTime.now().toUtc(),
        readingPositions: const <SyncReadingPosition>[],
      );
    }
  }

  Future<SyncStateFile> _buildStateFile({
    required String? cursor,
    required DateTime now,
  }) async {
    final entries = await _libraryStore.loadAll();
    final positions = entries.map((entry) {
      final position = entry.readingPosition;
      return SyncReadingPosition(
        bookId: entry.id,
        chapterHref: position.chapterHref,
        anchor: position.anchor,
        offset: position.offset,
        updatedAt: position.updatedAt,
      );
    }).toList();
    return SyncStateFile(
      schemaVersion: 1,
      generatedAt: now,
      cursor: cursor,
      readingPositions: positions,
    );
  }

  Future<int> _applyState(SyncStateFile stateFile) async {
    var applied = 0;
    for (final remote in stateFile.readingPositions) {
      if (remote.bookId.isEmpty) {
        continue;
      }
      final entry = await _libraryStore.getById(remote.bookId);
      if (entry == null) {
        continue;
      }
      final incomingAt = remote.updatedAt;
      final currentAt = entry.readingPosition.updatedAt;
      if (!_isNewer(incomingAt, currentAt)) {
        continue;
      }
      final updatedEntry = _copyEntry(
        entry,
        readingPosition: ReadingPosition(
          chapterHref: remote.chapterHref,
          anchor: remote.anchor,
          offset: remote.offset,
          updatedAt: incomingAt,
        ),
      );
      await _libraryStore.upsert(updatedEntry);
      applied += 1;
    }
    return applied;
  }

  Future<void> _safePutFile(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    try {
      await _putFile(path, bytes, contentType: contentType);
    } on SyncAdapterException catch (error) {
      Log.d('FileSyncEngine: failed to upload $path: $error');
      if (_isClientError(error)) {
        rethrow;
      }
    }
  }

  Future<void> _putFile(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    await _adapter.putFile(
      path,
      bytes,
      contentType: contentType,
    );
    _metrics?.addUpload(bytes.length);
  }

  Future<SyncFile?> _getFile(String path) async {
    final file = await _adapter.getFile(path);
    if (file != null) {
      _metrics?.addDownload(file.bytes.length);
    }
    return file;
  }

  bool _isClientError(SyncAdapterException error) {
    final code = error.code;
    if (code == null) {
      return false;
    }
    final parts = code.split('_');
    if (parts.isEmpty) {
      return false;
    }
    final status = int.tryParse(parts.last);
    if (status == null) {
      return false;
    }
    return status >= 400 && status < 500;
  }

  bool _isNotFound(SyncAdapterException error) {
    final code = error.code;
    if (code == null) {
      return false;
    }
    if (code.contains('404')) {
      return true;
    }
    final parts = code.split('_');
    if (parts.isEmpty) {
      return false;
    }
    final status = int.tryParse(parts.last);
    return status == 404;
  }

  Future<bool> _applyEvent(EventLogEntry event) async {
    final payload = _coerceMap(event.payload);
    switch (event.entityType) {
      case 'note':
        return _applyNoteEvent(event, payload);
      case 'highlight':
        return _applyHighlightEvent(event, payload);
      case 'bookmark':
        return _applyBookmarkEvent(event, payload);
      case 'reading_position':
        return _applyReadingPositionEvent(event, payload);
      case 'free_note':
        return _applyFreeNoteEvent(event, payload);
      default:
        return false;
    }
  }

  Future<bool> _applyFreeNoteEvent(
    EventLogEntry event,
    Map<String, Object?> payload,
  ) async {
    final store = _freeNotesStore;
    if (store == null) {
      return false;
    }
    final incomingAt = _extractUpdatedAt(payload) ?? event.createdAt;
    final noteId = payload['id'] as String? ?? event.entityId;
    if (noteId.trim().isEmpty) {
      return false;
    }
    final current = await store.getById(noteId);
    final currentAt = _effectiveUpdatedAt(current?.updatedAt, current?.createdAt);
    if (event.op == 'delete') {
      if (!_isNewer(incomingAt, currentAt)) {
        return false;
      }
      await store.removeRaw(noteId);
      return true;
    }
    if (!_isNewer(incomingAt, currentAt) && current != null) {
      return false;
    }
    final note = FreeNote.fromMap(payload);
    await store.upsert(note);
    return true;
  }

  Future<bool> _applyNoteEvent(
    EventLogEntry event,
    Map<String, Object?> payload,
  ) async {
    final bookId = payload['bookId'] as String?;
    if (bookId == null || bookId.isEmpty) {
      return false;
    }
    final entry = await _libraryStore.getById(bookId);
    if (entry == null) {
      return false;
    }
    final incomingAt = _extractUpdatedAt(payload) ?? event.createdAt;
    final noteId = payload['id'] as String? ?? event.entityId;
    final existing = entry.notes.where((note) => note.id == noteId).toList();
    final current = existing.isEmpty ? null : existing.first;
    final currentAt = _effectiveUpdatedAt(current?.updatedAt, current?.createdAt);
    if (event.op == 'delete') {
      if (!_isNewer(incomingAt, currentAt)) {
        return false;
      }
      final updatedNotes =
          entry.notes.where((note) => note.id != noteId).toList();
      if (updatedNotes.length == entry.notes.length) {
        return false;
      }
      await _libraryStore.upsert(_copyEntry(entry, notes: updatedNotes));
      return true;
    }
    if (!_isNewer(incomingAt, currentAt) && current != null) {
      return false;
    }
    final note = Note.fromMap(payload);
    final updatedNotes = entry.notes
        .where((item) => item.id != note.id)
        .toList(growable: true)
      ..add(note);
    await _libraryStore.upsert(_copyEntry(entry, notes: updatedNotes));
    return true;
  }

  Future<bool> _applyHighlightEvent(
    EventLogEntry event,
    Map<String, Object?> payload,
  ) async {
    final bookId = payload['bookId'] as String?;
    if (bookId == null || bookId.isEmpty) {
      return false;
    }
    final entry = await _libraryStore.getById(bookId);
    if (entry == null) {
      return false;
    }
    final incomingAt = _extractUpdatedAt(payload) ?? event.createdAt;
    final highlightId = payload['id'] as String? ?? event.entityId;
    final existing =
        entry.highlights.where((item) => item.id == highlightId).toList();
    final current = existing.isEmpty ? null : existing.first;
    final currentAt =
        _effectiveUpdatedAt(current?.updatedAt, current?.createdAt);
    if (event.op == 'delete') {
      if (!_isNewer(incomingAt, currentAt)) {
        return false;
      }
      final updatedHighlights =
          entry.highlights.where((item) => item.id != highlightId).toList();
      if (updatedHighlights.length == entry.highlights.length) {
        return false;
      }
      await _libraryStore.upsert(
        _copyEntry(entry, highlights: updatedHighlights),
      );
      return true;
    }
    if (!_isNewer(incomingAt, currentAt) && current != null) {
      return false;
    }
    final highlight = Highlight.fromMap(payload);
    final updatedHighlights = entry.highlights
        .where((item) => item.id != highlight.id)
        .toList(growable: true)
      ..add(highlight);
    await _libraryStore.upsert(
      _copyEntry(entry, highlights: updatedHighlights),
    );
    return true;
  }

  Future<bool> _applyBookmarkEvent(
    EventLogEntry event,
    Map<String, Object?> payload,
  ) async {
    final bookId = payload['bookId'] as String?;
    if (bookId == null || bookId.isEmpty) {
      return false;
    }
    final entry = await _libraryStore.getById(bookId);
    if (entry == null) {
      return false;
    }
    final incomingAt = _extractUpdatedAt(payload) ?? event.createdAt;
    final bookmarkId = payload['id'] as String? ?? event.entityId;
    final existing =
        entry.bookmarks.where((item) => item.id == bookmarkId).toList();
    final current = existing.isEmpty ? null : existing.first;
    final currentAt =
        _effectiveUpdatedAt(current?.updatedAt, current?.createdAt);
    if (event.op == 'delete') {
      if (!_isNewer(incomingAt, currentAt)) {
        return false;
      }
      final updated =
          entry.bookmarks.where((item) => item.id != bookmarkId).toList();
      if (updated.length == entry.bookmarks.length) {
        return false;
      }
      await _libraryStore.upsert(_copyEntry(entry, bookmarks: updated));
      return true;
    }
    if (!_isNewer(incomingAt, currentAt) && current != null) {
      return false;
    }
    final bookmark = Bookmark.fromMap(payload);
    final updatedBookmarks = entry.bookmarks
        .where((item) => item.id != bookmark.id)
        .toList(growable: true)
      ..add(bookmark);
    await _libraryStore.upsert(
      _copyEntry(entry, bookmarks: updatedBookmarks),
    );
    return true;
  }

  Future<bool> _applyReadingPositionEvent(
    EventLogEntry event,
    Map<String, Object?> payload,
  ) async {
    final bookId = payload['bookId'] as String?;
    if (bookId == null || bookId.isEmpty) {
      return false;
    }
    final entry = await _libraryStore.getById(bookId);
    if (entry == null) {
      return false;
    }
    final incomingAt = _extractUpdatedAt(payload) ?? event.createdAt;
    final currentAt = entry.readingPosition.updatedAt;
    if (!_isNewer(incomingAt, currentAt)) {
      return false;
    }
    final updatedEntry = _copyEntry(
      entry,
      readingPosition: ReadingPosition(
        chapterHref: payload['chapterHref'] as String?,
        anchor: payload['anchor'] as String?,
        offset: (payload['offset'] as num?)?.toInt(),
        updatedAt: incomingAt,
      ),
    );
    await _libraryStore.upsert(updatedEntry);
    return true;
  }

  Map<String, Object?> _decodeJsonMap(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, Object?>{};
  }

  String _path(String fileName) {
    if (basePath.isEmpty) {
      return fileName;
    }
    return '$basePath/$fileName';
  }
}

class FileSyncResult {
  const FileSyncResult({
    required this.appliedEvents,
    required this.appliedState,
    required this.uploadedEvents,
    required this.uploadedAt,
    required this.booksUploaded,
    required this.booksDownloaded,
    required this.durationMs,
    required this.bytesUploaded,
    required this.bytesDownloaded,
    required this.filesUploaded,
    required this.filesDownloaded,
    this.error,
  });

  const FileSyncResult.error({
    required this.error,
    required this.uploadedAt,
    required this.durationMs,
    required this.bytesUploaded,
    required this.bytesDownloaded,
    required this.filesUploaded,
    required this.filesDownloaded,
  })  : appliedEvents = 0,
        appliedState = 0,
        uploadedEvents = 0,
        booksUploaded = 0,
        booksDownloaded = 0;

  final int appliedEvents;
  final int appliedState;
  final int uploadedEvents;
  final DateTime uploadedAt;
  final int booksUploaded;
  final int booksDownloaded;
  final int durationMs;
  final int bytesUploaded;
  final int bytesDownloaded;
  final int filesUploaded;
  final int filesDownloaded;
  final SyncAdapterException? error;
}

class _SyncMetricsTracker {
  int bytesUploaded = 0;
  int bytesDownloaded = 0;
  int filesUploaded = 0;
  int filesDownloaded = 0;

  void addUpload(int bytes) {
    filesUploaded += 1;
    bytesUploaded += bytes;
  }

  void addDownload(int bytes) {
    filesDownloaded += 1;
    bytesDownloaded += bytes;
  }
}

class _MergeBooksResult {
  const _MergeBooksResult({
    required this.nextIndex,
    required this.uploaded,
    required this.downloaded,
  });

  final Map<String, SyncBookDescriptor> nextIndex;
  final int uploaded;
  final int downloaded;
}

class _BookSyncResult {
  const _BookSyncResult({
    required this.uploaded,
    required this.downloaded,
  });

  final int uploaded;
  final int downloaded;
}

LibraryEntry _copyEntry(
  LibraryEntry entry, {
  ReadingPosition? readingPosition,
  List<Note>? notes,
  List<Highlight>? highlights,
  List<Bookmark>? bookmarks,
}) {
  return LibraryEntry(
    id: entry.id,
    title: entry.title,
    author: entry.author,
    localPath: entry.localPath,
    coverPath: entry.coverPath,
    addedAt: entry.addedAt,
    fingerprint: entry.fingerprint,
    sourcePath: entry.sourcePath,
    readingPosition: readingPosition ?? entry.readingPosition,
    progress: entry.progress,
    lastOpenedAt: entry.lastOpenedAt,
    notes: notes ?? entry.notes,
    highlights: highlights ?? entry.highlights,
    bookmarks: bookmarks ?? entry.bookmarks,
    tocOfficial: entry.tocOfficial,
    tocGenerated: entry.tocGenerated,
    tocMode: entry.tocMode,
  );
}

bool _isNewer(DateTime? incoming, DateTime? current) {
  if (incoming == null) {
    return false;
  }
  if (current == null) {
    return true;
  }
  return incoming.isAfter(current);
}

DateTime? _extractUpdatedAt(Map<String, Object?> payload) {
  final raw = payload['updatedAt'];
  if (raw is DateTime) {
    return raw;
  }
  if (raw is String) {
    return DateTime.tryParse(raw);
  }
  return null;
}

DateTime? _effectiveUpdatedAt(DateTime? updatedAt, DateTime? createdAt) {
  return updatedAt ?? createdAt;
}

Map<String, Object?> _coerceMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, Object?>{};
}
