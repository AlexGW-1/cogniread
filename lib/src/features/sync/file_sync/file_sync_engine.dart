import 'dart:convert';

import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/sync/data/event_log_store.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_file_models.dart';

class FileSyncEngine {
  FileSyncEngine({
    required SyncAdapter adapter,
    required LibraryStore libraryStore,
    required EventLogStore eventLogStore,
    required String deviceId,
    this.basePath = '',
  })  : _adapter = adapter,
        _libraryStore = libraryStore,
        _eventLogStore = eventLogStore,
        _deviceId = deviceId;

  final SyncAdapter _adapter;
  final LibraryStore _libraryStore;
  final EventLogStore _eventLogStore;
  final String _deviceId;
  final String basePath;

  Future<FileSyncResult> sync() async {
    final now = DateTime.now().toUtc();
    final remoteEvents = await _readEventLog();
    final remoteState = await _readState();

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

    await _adapter.putFile(
      _path('event_log.json'),
      eventLogFile.toJsonBytes(),
      contentType: 'application/json',
    );
    await _adapter.putFile(
      _path('state.json'),
      stateFile.toJsonBytes(),
      contentType: 'application/json',
    );
    await _adapter.putFile(
      _path('meta.json'),
      metaFile.toJsonBytes(),
      contentType: 'application/json',
    );

    return FileSyncResult(
      appliedEvents: appliedEvents,
      appliedState: appliedState,
      uploadedEvents: mergedEvents.length,
      uploadedAt: now,
    );
  }

  Future<SyncEventLogFile> _readEventLog() async {
    final file = await _adapter.getFile(_path('event_log.json'));
    if (file == null) {
      return SyncEventLogFile(
        schemaVersion: 1,
        deviceId: _deviceId,
        generatedAt: DateTime.now().toUtc(),
        events: const <EventLogEntry>[],
      );
    }
    final decoded = _decodeJsonMap(file.bytes);
    return SyncEventLogFile.fromMap(decoded);
  }

  Future<SyncStateFile> _readState() async {
    final file = await _adapter.getFile(_path('state.json'));
    if (file == null) {
      return SyncStateFile(
        schemaVersion: 1,
        generatedAt: DateTime.now().toUtc(),
        readingPositions: const <SyncReadingPosition>[],
      );
    }
    final decoded = _decodeJsonMap(file.bytes);
    return SyncStateFile.fromMap(decoded);
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
      default:
        return false;
    }
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
  });

  final int appliedEvents;
  final int appliedState;
  final int uploadedEvents;
  final DateTime uploadedAt;
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
