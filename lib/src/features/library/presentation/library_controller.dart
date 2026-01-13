import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/core/services/storage_service_impl.dart';
import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/library/data/library_preferences_store.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/sync/data/event_log_store.dart';
import 'package:cogniread/src/features/sync/file_sync/file_sync_engine.dart';
import 'package:cogniread/src/features/sync/file_sync/dropbox_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/dropbox_oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/dropbox_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/google_drive_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/google_drive_oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/google_drive_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/onedrive_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/onedrive_oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/onedrive_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_credentials.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_auth_store.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_errors.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_oauth_config.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_provider.dart';
import 'package:cogniread/src/features/sync/file_sync/stored_oauth_token_provider.dart';
import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart';

class LibraryBookItem {
  const LibraryBookItem({
    required this.id,
    required this.title,
    required this.author,
    required this.sourcePath,
    required this.storedPath,
    required this.coverPath,
    required this.hash,
    required this.addedAt,
    required this.lastOpenedAt,
    required this.isMissing,
    required this.notes,
    required this.highlights,
  });

  factory LibraryBookItem.fromEntry(
    LibraryEntry entry, {
    required bool isMissing,
  }) {
    return LibraryBookItem(
      id: entry.id,
      title: entry.title,
      author: entry.author,
      sourcePath: entry.sourcePath,
      storedPath: entry.localPath,
      coverPath: entry.coverPath,
      hash: entry.fingerprint,
      addedAt: entry.addedAt,
      lastOpenedAt: entry.lastOpenedAt,
      isMissing: isMissing,
      notes: entry.notes,
      highlights: entry.highlights,
    );
  }

  final String id;
  final String title;
  final String? author;
  final String sourcePath;
  final String storedPath;
  final String? coverPath;
  final String hash;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
  final bool isMissing;
  final List<Note> notes;
  final List<Highlight> highlights;
}

enum LibraryViewMode {
  list,
  grid,
}

enum LibrarySearchResultType {
  book,
  note,
  highlight,
}

class LibrarySearchResult {
  const LibrarySearchResult({
    required this.type,
    required this.bookId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.snippet,
    required this.sourceLabel,
    this.markId,
  });

  final LibrarySearchResultType type;
  final String bookId;
  final String bookTitle;
  final String? bookAuthor;
  final String snippet;
  final String sourceLabel;
  final String? markId;
}

class LibraryController extends ChangeNotifier {
  LibraryController({
    StorageService? storageService,
    LibraryStore? store,
    LibraryPreferencesStore? preferencesStore,
    Future<String?> Function()? pickEpubPath,
    SyncAdapter? syncAdapter,
    bool stubImport = false,
  })  : _storageService = storageService ?? AppStorageService(),
        _store = store ?? LibraryStore(),
        _preferencesStore = preferencesStore ?? LibraryPreferencesStore(),
        _pickEpubPath = pickEpubPath,
        _fallbackSyncAdapter = syncAdapter,
        _syncAdapter = syncAdapter,
        _stubImport = stubImport;

  final StorageService _storageService;
  final LibraryStore _store;
  final LibraryPreferencesStore _preferencesStore;
  final Future<String?> Function()? _pickEpubPath;
  final SyncAdapter? _fallbackSyncAdapter;
  SyncAdapter? _syncAdapter;
  final bool _stubImport;
  Future<void>? _storeReady;
  final EventLogStore _syncEventLogStore = EventLogStore();
  final SyncAuthStore _syncAuthStore = SyncAuthStore();
  SyncOAuthConfig? _oauthConfig;
  FileSyncEngine? _syncEngine;
  bool _syncInProgress = false;
  bool _coverSyncInProgress = false;
  bool _authInProgress = false;
  bool _connectionInProgress = false;
  bool _deleteInProgress = false;
  String? _authError;
  String? _authState;
  SyncProvider? _pendingAuthProvider;
  WebDavCredentials? _webDavCredentials;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri?>? _authLinkSub;
  final Map<SyncProvider, bool> _providerConnected =
      <SyncProvider, bool>{};

  bool _loading = true;
  String? _errorMessage;
  String? _infoMessage;

  static const List<String> _supportedExtensions = <String>[
    '.epub',
    '.fb2',
    '.zip',
  ];
  String _query = '';
  final List<LibraryBookItem> _books = <LibraryBookItem>[];
  LibraryViewMode _viewMode = LibraryViewMode.list;
  SyncProvider _syncProvider = SyncProvider.googleDrive;
  String _globalSearchQuery = '';
  bool _globalSearching = false;
  List<LibrarySearchResult> _globalSearchResults =
      const <LibrarySearchResult>[];
  Timer? _globalSearchDebounce;
  int _globalSearchNonce = 0;
  DateTime? _lastSyncAt;
  String? _lastSyncSummary;

  bool get loading => _loading;
  List<LibraryBookItem> get books => List<LibraryBookItem>.unmodifiable(_books);
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;
  String get query => _query;
  LibraryViewMode get viewMode => _viewMode;
  SyncProvider get syncProvider => _syncProvider;
  bool get syncInProgress => _syncInProgress;
  bool get authInProgress => _authInProgress;
  bool get connectionInProgress => _connectionInProgress;
  bool get deleteInProgress => _deleteInProgress;
  String? get authError => _authError;
  SyncOAuthConfig? get oauthConfig => _oauthConfig;
  bool get isSyncProviderConnected =>
      _providerConnected[_syncProvider] ?? false;
  bool get isWebDavProvider => _syncProvider == SyncProvider.webDav;
  bool get isSyncProviderConfigured =>
      _oauthConfig?.isConfigured(_syncProvider) ?? false;
  WebDavCredentials? get webDavCredentials => _webDavCredentials;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastSyncSummary => _lastSyncSummary;
  String get syncAdapterLabel =>
      _syncAdapter == null ? 'none' : _syncAdapter.runtimeType.toString();
  String get globalSearchQuery => _globalSearchQuery;
  bool get globalSearching => _globalSearching;
  List<LibrarySearchResult> get globalSearchResults =>
      List<LibrarySearchResult>.unmodifiable(_globalSearchResults);

  List<LibraryBookItem> get filteredBooks {
    final needle = _query.toLowerCase().trim();
    if (needle.isEmpty) {
      return books;
    }
    return books
        .where(
          (book) =>
              book.title.toLowerCase().contains(needle) ||
              (book.author?.toLowerCase().contains(needle) ?? false),
        )
        .toList();
  }

  Future<void> init() async {
    if (_stubImport) {
      _storeReady = Future<void>.value();
      _addStubBook();
      _setInfo('Книга добавлена');
      _loading = false;
      notifyListeners();
      return;
    }
    _storeReady = _store.init();
    await _preferencesStore.init();
    await _syncAuthStore.init();
    await _loadOAuthConfig();
    await _initAuthLinks();
    await _ensureDeviceId();
    await _loadViewMode();
    await _loadSyncProvider();
    await _loadProviderConnection(_syncProvider);
    await _refreshSyncAdapter();
    await _loadLibrary();
    try {
      await _runFileSync();
    } catch (error) {
      _setAuthError('Автосинхронизация отключена. Проверь подключение.');
      Log.d('Auto sync failed: $error');
    }
  }

  Future<void> _loadViewMode() async {
    final stored = await _preferencesStore.loadViewMode();
    if (stored == 'grid') {
      _viewMode = LibraryViewMode.grid;
    } else {
      _viewMode = LibraryViewMode.list;
    }
    notifyListeners();
  }

  Future<void> setViewMode(LibraryViewMode mode) async {
    if (_viewMode == mode) {
      return;
    }
    _viewMode = mode;
    notifyListeners();
    await _preferencesStore.saveViewMode(
      mode == LibraryViewMode.grid ? 'grid' : 'list',
    );
  }

  Future<void> setSyncProvider(SyncProvider provider) async {
    if (_syncProvider == provider) {
      return;
    }
    _syncProvider = provider;
    notifyListeners();
    await _preferencesStore.saveSyncProvider(provider.name);
    await _loadProviderConnection(provider);
    await _refreshSyncAdapter();
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setGlobalSearchQuery(String value, {int limit = 50}) {
    _globalSearchQuery = value;
    _globalSearchDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _globalSearching = false;
      _globalSearchResults = const <LibrarySearchResult>[];
      notifyListeners();
      return;
    }
    _globalSearching = true;
    notifyListeners();
    final nonce = ++_globalSearchNonce;
    _globalSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      final results = _searchGlobalMatches(trimmed, limit: limit);
      if (nonce != _globalSearchNonce) {
        return;
      }
      _globalSearchResults = results;
      _globalSearching = false;
      notifyListeners();
    });
  }

  List<LibrarySearchResult> _searchGlobalMatches(
    String query, {
    int limit = 50,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <LibrarySearchResult>[];
    }
    final needle = trimmed.toLowerCase();
    final results = <LibrarySearchResult>[];
    for (final book in _books) {
      if (results.length >= limit) {
        break;
      }
      _appendBookMatch(
        results,
        book: book,
        text: book.title,
        needle: needle,
        sourceLabel: 'Название',
        type: LibrarySearchResultType.book,
        limit: limit,
      );
      if (results.length >= limit) {
        break;
      }
      if (book.author != null && book.author!.trim().isNotEmpty) {
        _appendBookMatch(
          results,
          book: book,
          text: book.author!,
          needle: needle,
          sourceLabel: 'Автор',
          type: LibrarySearchResultType.book,
          limit: limit,
        );
      }
      if (results.length >= limit) {
        break;
      }
      for (final note in book.notes) {
        if (results.length >= limit) {
          break;
        }
        _appendBookMatch(
          results,
          book: book,
          text: note.noteText,
          needle: needle,
          sourceLabel: 'Заметка',
          type: LibrarySearchResultType.note,
          markId: note.id,
          limit: limit,
        );
      }
      if (results.length >= limit) {
        break;
      }
      for (final highlight in book.highlights) {
        if (results.length >= limit) {
          break;
        }
        _appendBookMatch(
          results,
          book: book,
          text: highlight.excerpt,
          needle: needle,
          sourceLabel: 'Выделение',
          type: LibrarySearchResultType.highlight,
          markId: highlight.id,
          limit: limit,
        );
      }
    }
    return results;
  }

  void _appendBookMatch(
    List<LibrarySearchResult> results, {
    required LibraryBookItem book,
    required String text,
    required String needle,
    required String sourceLabel,
    required LibrarySearchResultType type,
    required int limit,
    String? markId,
  }) {
    if (text.trim().isEmpty || results.length >= limit) {
      return;
    }
    final lower = text.toLowerCase();
    final index = lower.indexOf(needle);
    if (index == -1) {
      return;
    }
    final snippet = _buildSnippet(text, index, needle.length);
    results.add(
      LibrarySearchResult(
        type: type,
        bookId: book.id,
        bookTitle: book.title,
        bookAuthor: book.author,
        snippet: snippet,
        sourceLabel: sourceLabel,
        markId: markId,
      ),
    );
  }

  void clearNotices() {
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();
  }

  Future<void> syncNow() async {
    await _runFileSync();
  }

  Future<void> importEpub() async {
    Log.d('Import book pressed.');
    if (_stubImport) {
      _addStubBook();
      _setInfo('Книга добавлена');
      return;
    }
    final path = _pickEpubPath == null
        ? await _pickBookFromFilePicker()
        : await _pickEpubPath();
    if (path == null) {
      _setInfo('Импорт отменён');
      return;
    }

    final validationError = await _validateBookPath(path);
    if (validationError != null) {
      _setError(validationError);
      return;
    }

    try {
      await _storeReady;
      final stored = await _storageService.copyToAppStorageWithHash(path);
      final fallbackTitle = p.basenameWithoutExtension(path);
      final exists = await _store.existsByFingerprint(stored.hash);
      Log.d('Import book fingerprint=${stored.hash} exists=$exists');
      if (exists) {
        final existing = await _store.getById(stored.hash);
        final existingPath = existing?.localPath;
        final existingMissing = existingPath == null
            ? true
            : !(await File(existingPath).exists());
        Log.d('Import book existingPath=$existingPath missing=$existingMissing');
        final index = _books.indexWhere((book) => book.id == stored.hash);
        final listMissing = index != -1 && _books[index].isMissing;
        if (existing != null && (existingMissing || listMissing)) {
          final repaired = LibraryEntry(
            id: existing.id,
            title: existing.title,
            author: existing.author,
            localPath: stored.path,
            coverPath: existing.coverPath,
            addedAt: existing.addedAt,
            fingerprint: existing.fingerprint,
            sourcePath: File(path).absolute.path,
            readingPosition: existing.readingPosition,
            progress: existing.progress,
            lastOpenedAt: existing.lastOpenedAt,
            notes: existing.notes,
            highlights: existing.highlights,
            bookmarks: existing.bookmarks,
            tocOfficial: existing.tocOfficial,
            tocGenerated: existing.tocGenerated,
            tocMode: existing.tocMode,
          );
          if (existingMissing) {
            await _store.upsert(repaired);
          }
          if (index != -1) {
            _books[index] = LibraryBookItem.fromEntry(
              existingMissing ? repaired : existing,
              isMissing: false,
            );
            _books.sort(_sortByLastOpenedAt);
            notifyListeners();
          } else {
            await _loadLibrary();
          }
          _setInfo('Книга восстановлена');
          return;
        }
        _setError('Эта книга уже в библиотеке');
        return;
      }
      final metadata = await _readMetadata(stored.path, fallbackTitle);
      String? coverPath;
      try {
        coverPath = await _readCoverPath(stored.path, stored.hash);
      } catch (e) {
        Log.d('Cover extraction failed: $e');
        coverPath = null;
      }
      final entry = LibraryEntry(
        id: stored.hash,
        title: metadata.title,
        author: metadata.author,
        localPath: stored.path,
        coverPath: coverPath,
        addedAt: DateTime.now(),
        fingerprint: stored.hash,
        sourcePath: File(path).absolute.path,
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
      await _store.upsert(entry);
      _books.add(LibraryBookItem.fromEntry(entry, isMissing: false));
      _books.sort(_sortByLastOpenedAt);
      notifyListeners();
      Log.d('Book copied to: ${stored.path}');
      _setInfo('Книга добавлена');
      return;
    } catch (e) {
      Log.d('Book import failed: $e');
      _setError('Не удалось сохранить файл');
    }
  }

  Future<void> deleteBook(String id) async {
    final index = _books.indexWhere((book) => book.id == id);
    if (index == -1) {
      _setError('Книга не найдена');
      return;
    }
    final book = _books[index];
    try {
      await _storeReady;
      await _store.remove(book.id);
      final file = File(book.storedPath);
      if (await file.exists()) {
        await file.delete();
      }
      final coverPath = book.coverPath;
      if (coverPath != null) {
        final coverFile = File(coverPath);
        if (await coverFile.exists()) {
          await coverFile.delete();
        }
      }
      _books.removeAt(index);
      notifyListeners();
      _setInfo('Книга удалена');
      return;
    } catch (e) {
      Log.d('Failed to delete book: $e');
      _setError('Не удалось удалить книгу');
    }
  }

  Future<void> clearLibrary() async {
    _books.clear();
    notifyListeners();
    try {
      await _storeReady;
      await _store.clear();
      final dirPath = await _storageService.appStoragePath();
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await for (final entry in dir.list()) {
          if (entry is File && _isSupportedExtension(entry.path)) {
            await entry.delete();
          }
        }
        final coversDir = Directory(p.join(dirPath, 'covers'));
        if (await coversDir.exists()) {
          await coversDir.delete(recursive: true);
        }
      }
      await _loadLibrary();
      _setInfo('Библиотека очищена');
      return;
    } catch (e) {
      Log.d('Failed to clear library: $e');
      _setError('Не удалось очистить библиотеку');
    }
  }

  Future<void> markOpened(String id) async {
    if (_stubImport) {
      return;
    }
    await _storeReady;
    await _store.updateLastOpenedAt(id, DateTime.now());
    final index = _books.indexWhere((book) => book.id == id);
    if (index != -1) {
      final book = _books[index];
      _books[index] = LibraryBookItem(
        id: book.id,
        title: book.title,
        author: book.author,
        sourcePath: book.sourcePath,
        storedPath: book.storedPath,
        coverPath: book.coverPath,
        hash: book.hash,
        addedAt: book.addedAt,
        lastOpenedAt: DateTime.now(),
        isMissing: book.isMissing,
        notes: book.notes,
        highlights: book.highlights,
      );
      _books.sort(_sortByLastOpenedAt);
      notifyListeners();
    }
  }

  void markMissing(String id) {
    final index = _books.indexWhere((book) => book.id == id);
    if (index == -1) {
      return;
    }
    final book = _books[index];
    if (book.isMissing) {
      return;
    }
    _books[index] = LibraryBookItem(
      id: book.id,
      title: book.title,
      author: book.author,
      sourcePath: book.sourcePath,
      storedPath: book.storedPath,
      coverPath: book.coverPath,
      hash: book.hash,
      addedAt: book.addedAt,
      lastOpenedAt: book.lastOpenedAt,
      isMissing: true,
      notes: book.notes,
      highlights: book.highlights,
    );
    notifyListeners();
  }

  Future<LibraryBookItem?> prepareOpen(String id) async {
    final index = _books.indexWhere((book) => book.id == id);
    if (index == -1) {
      _setError('Книга не найдена');
      return null;
    }
    final book = _books[index];
    if (book.isMissing) {
      _setError('Файл книги недоступен');
      return null;
    }
    if (book.sourcePath != 'stub') {
      final exists = await File(book.storedPath).exists();
      if (!exists) {
        markMissing(book.id);
        _setError('Файл книги недоступен');
        return null;
      }
    }
    await markOpened(book.id);
    return book;
  }

  Future<void> _loadLibrary() async {
    if (_stubImport) {
      _loading = false;
      notifyListeners();
      return;
    }
    try {
      await _storeReady;
      final entries = await _store.loadAll();
      final items = <LibraryBookItem>[];
      for (final entry in entries) {
        final exists = await File(entry.localPath).exists();
        items.add(LibraryBookItem.fromEntry(entry, isMissing: !exists));
      }
      _books
        ..clear()
        ..addAll(items);
      _books.sort(_sortByLastOpenedAt);
      _loading = false;
      notifyListeners();
      _syncMissingCovers(entries);
    } catch (e) {
      Log.d('Failed to load library: $e');
      _setError('Не удалось загрузить библиотеку');
      _loading = false;
      notifyListeners();
    }
  }

  void _syncMissingCovers(List<LibraryEntry> entries) {
    if (_coverSyncInProgress) {
      return;
    }
    _coverSyncInProgress = true;
    Future<void>(() async {
      try {
        for (final entry in entries) {
          if (entry.coverPath != null &&
              await File(entry.coverPath!).exists()) {
            continue;
          }
          final exists = await File(entry.localPath).exists();
          if (!exists) {
            continue;
          }
          final coverPath = await _readCoverPath(entry.localPath, entry.id);
          if (coverPath == null) {
            continue;
          }
          final updated = LibraryEntry(
            id: entry.id,
            title: entry.title,
            author: entry.author,
            localPath: entry.localPath,
            coverPath: coverPath,
            addedAt: entry.addedAt,
            fingerprint: entry.fingerprint,
            sourcePath: entry.sourcePath,
            readingPosition: entry.readingPosition,
            progress: entry.progress,
            lastOpenedAt: entry.lastOpenedAt,
            notes: entry.notes,
            highlights: entry.highlights,
            bookmarks: entry.bookmarks,
            tocOfficial: entry.tocOfficial,
            tocGenerated: entry.tocGenerated,
            tocMode: entry.tocMode,
          );
          await _store.upsert(updated);
          final index = _books.indexWhere((book) => book.id == entry.id);
          if (index != -1) {
            _books[index] = LibraryBookItem.fromEntry(
              updated,
              isMissing: _books[index].isMissing,
            );
            notifyListeners();
          }
        }
      } catch (e) {
        Log.d('Failed to sync covers: $e');
      } finally {
        _coverSyncInProgress = false;
      }
    });
  }

  Future<String?> _pickBookFromFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions:
          _supportedExtensions.map((ext) => ext.replaceFirst('.', '')).toList(),
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    return result.files.single.path;
  }

  Future<String?> _validateBookPath(String path) async {
    if (!_isSupportedExtension(path)) {
      return 'Неверное расширение файла';
    }

    final file = File(path);
    if (!await file.exists()) {
      return 'Файл не существует';
    }

    try {
      final raf = await file.open();
      await raf.close();
    } on FileSystemException {
      return 'Нет доступа к файлу';
    }

    final ext = p.extension(path).toLowerCase();
    if (ext == '.zip') {
      final error = await _validateZipContainsBook(file);
      if (error != null) {
        return error;
      }
    }

    return null;
  }

  Future<String?> _readCoverPath(String path, String bookId) async {
    try {
      final extension = p.extension(path).toLowerCase();
      CoverPayload? cover;
      if (extension == '.epub') {
        final bytes = await File(path).readAsBytes();
        final bookRef = await EpubReader.openBook(bytes);
        cover = await _readCoverBytes(bookRef);
      } else if (extension == '.fb2') {
        cover = _readFb2CoverFromBytes(await File(path).readAsBytes());
      } else if (extension == '.zip') {
        cover =
            _readFb2CoverFromZipBytes(await File(path).readAsBytes());
      }
      if (cover == null || cover.bytes.isEmpty) {
        return null;
      }
      final dirPath = await _storageService.appStoragePath();
      final coversDir = Directory(p.join(dirPath, 'covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }
      final coverExt = cover.extension ?? '.img';
      final coverPath = p.join(coversDir.path, '$bookId$coverExt');
      await File(coverPath).writeAsBytes(cover.bytes, flush: true);
      return coverPath;
    } catch (e) {
      Log.d('Failed to read EPUB cover: $e');
      return null;
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _setInfo(String message) {
    _infoMessage = message;
    notifyListeners();
  }

  void _setAuthError(String message) {
    _authError = message;
    notifyListeners();
  }

  Future<void> _loadOAuthConfig() async {
    final stored = await _preferencesStore.loadSyncOAuthConfig();
    if (stored != null) {
      final fromStore = SyncOAuthConfig.fromMap(stored);
      if (fromStore != null &&
          (fromStore.googleDrive != null ||
              fromStore.dropbox != null ||
              fromStore.oneDrive != null ||
              fromStore.yandexDisk != null)) {
        _oauthConfig = fromStore;
        return;
      }
    }
    _oauthConfig = await SyncOAuthConfig.load();
  }

  Future<void> saveOAuthConfig({
    required SyncProvider provider,
    required String clientId,
    required String clientSecret,
    required String redirectUri,
    String? tenant,
  }) async {
    if (provider == SyncProvider.webDav) {
      _setAuthError('WebDAV не требует OAuth ключей');
      return;
    }
    final trimmedClientId = clientId.trim();
    final trimmedClientSecret = clientSecret.trim();
    final trimmedRedirect = redirectUri.trim();
    if (trimmedClientId.isEmpty ||
        trimmedClientSecret.isEmpty ||
        trimmedRedirect.isEmpty) {
      _setAuthError('Заполни clientId, clientSecret и redirectUri');
      return;
    }

    final current = _oauthConfig ?? const SyncOAuthConfig();
    SyncOAuthConfig updated;
    switch (provider) {
      case SyncProvider.googleDrive:
        updated = SyncOAuthConfig(
          googleDrive: GoogleDriveOAuthConfig(
            clientId: trimmedClientId,
            clientSecret: trimmedClientSecret,
            redirectUri: trimmedRedirect,
          ),
          dropbox: current.dropbox,
          oneDrive: current.oneDrive,
          yandexDisk: current.yandexDisk,
        );
        break;
      case SyncProvider.dropbox:
        updated = SyncOAuthConfig(
          googleDrive: current.googleDrive,
          dropbox: DropboxOAuthConfig(
            clientId: trimmedClientId,
            clientSecret: trimmedClientSecret,
            redirectUri: trimmedRedirect,
          ),
          oneDrive: current.oneDrive,
          yandexDisk: current.yandexDisk,
        );
        break;
      case SyncProvider.oneDrive:
        updated = SyncOAuthConfig(
          googleDrive: current.googleDrive,
          dropbox: current.dropbox,
          oneDrive: OneDriveOAuthConfig(
            clientId: trimmedClientId,
            clientSecret: trimmedClientSecret,
            redirectUri: trimmedRedirect,
            tenant: (tenant == null || tenant.trim().isEmpty)
                ? 'common'
                : tenant.trim(),
          ),
          yandexDisk: current.yandexDisk,
        );
        break;
      case SyncProvider.yandexDisk:
        updated = SyncOAuthConfig(
          googleDrive: current.googleDrive,
          dropbox: current.dropbox,
          oneDrive: current.oneDrive,
          yandexDisk: YandexDiskOAuthConfig(
            clientId: trimmedClientId,
            clientSecret: trimmedClientSecret,
            redirectUri: trimmedRedirect,
          ),
        );
        break;
      case SyncProvider.webDav:
        return;
    }

    _oauthConfig = updated;
    await _preferencesStore.saveSyncOAuthConfig(updated.toMap());
    _authError = null;
    await _refreshSyncAdapter();
    notifyListeners();
  }

  Future<void> clearOAuthConfig(SyncProvider provider) async {
    final current = _oauthConfig;
    if (current == null) {
      return;
    }
    SyncOAuthConfig updated;
    switch (provider) {
      case SyncProvider.googleDrive:
        updated = SyncOAuthConfig(
          dropbox: current.dropbox,
          oneDrive: current.oneDrive,
          yandexDisk: current.yandexDisk,
        );
        break;
      case SyncProvider.dropbox:
        updated = SyncOAuthConfig(
          googleDrive: current.googleDrive,
          oneDrive: current.oneDrive,
          yandexDisk: current.yandexDisk,
        );
        break;
      case SyncProvider.oneDrive:
        updated = SyncOAuthConfig(
          googleDrive: current.googleDrive,
          dropbox: current.dropbox,
          yandexDisk: current.yandexDisk,
        );
        break;
      case SyncProvider.yandexDisk:
        updated = SyncOAuthConfig(
          googleDrive: current.googleDrive,
          dropbox: current.dropbox,
          oneDrive: current.oneDrive,
        );
        break;
      case SyncProvider.webDav:
        return;
    }
    _oauthConfig = updated;
    await _preferencesStore.saveSyncOAuthConfig(updated.toMap());
    await _refreshSyncAdapter();
    notifyListeners();
  }

  Future<void> _initAuthLinks() async {
    _authLinkSub?.cancel();
    _authLinkSub = _appLinks.uriLinkStream.listen(
      _handleAuthRedirect,
      onError: (Object error, StackTrace stackTrace) {
        _setAuthError('OAuth link error: $error');
      },
    );
    try {
      _handleAuthRedirect(await _appLinks.getInitialLink());
    } catch (error) {
      _setAuthError('OAuth init failed: $error');
    }
  }

  Future<void> _loadProviderConnection(SyncProvider provider) async {
    if (provider == SyncProvider.webDav) {
      _webDavCredentials = await _syncAuthStore.loadWebDavCredentials();
      _providerConnected[provider] = _webDavCredentials != null;
      notifyListeners();
      return;
    }
    final token = await _syncAuthStore.loadToken(provider);
    _providerConnected[provider] = token != null;
    notifyListeners();
  }

  Future<void> _refreshSyncAdapter() async {
    if (_providerConnected[_syncProvider] != true) {
      _syncAdapter = _fallbackSyncAdapter;
      await _initSyncEngine();
      notifyListeners();
      return;
    }
    final adapter = await _buildAdapter(_syncProvider);
    _syncAdapter = adapter ?? _fallbackSyncAdapter;
    await _initSyncEngine();
    notifyListeners();
  }

  Future<SyncAdapter?> _buildAdapter(SyncProvider provider) async {
    final config = _oauthConfig;
    if (config == null) {
      return null;
    }
    switch (provider) {
      case SyncProvider.googleDrive:
        final googleConfig = config.googleDrive;
        if (googleConfig == null) {
          return null;
        }
        final oauthClient = GoogleDriveOAuthClient(googleConfig);
        final tokenProvider = StoredOAuthTokenProvider(
          provider: provider,
          store: _syncAuthStore,
          refreshToken: oauthClient.refreshToken,
        );
        final apiClient = HttpGoogleDriveApiClient(
          tokenProvider: tokenProvider,
        );
        return GoogleDriveSyncAdapter(apiClient: apiClient);
      case SyncProvider.dropbox:
        final dropboxConfig = config.dropbox;
        if (dropboxConfig == null) {
          return null;
        }
        final oauthClient = DropboxOAuthClient(dropboxConfig);
        final tokenProvider = StoredOAuthTokenProvider(
          provider: provider,
          store: _syncAuthStore,
          refreshToken: oauthClient.refreshToken,
        );
        final apiClient = HttpDropboxApiClient(tokenProvider: tokenProvider);
        // Пишем в корень App Folder Dropbox (без дополнительных вложенных папок),
        // чтобы избежать неожиданных конфликтов пути.
        const basePath = '';
        return DropboxSyncAdapter(
          apiClient: apiClient,
          basePath: basePath,
        );
      case SyncProvider.oneDrive:
        final oneDriveConfig = config.oneDrive;
        if (oneDriveConfig == null) {
          return null;
        }
        final oauthClient = OneDriveOAuthClient(oneDriveConfig);
        final tokenProvider = StoredOAuthTokenProvider(
          provider: provider,
          store: _syncAuthStore,
          refreshToken: oauthClient.refreshToken,
        );
        final apiClient = HttpOneDriveApiClient(tokenProvider: tokenProvider);
        return OneDriveSyncAdapter(apiClient: apiClient);
      case SyncProvider.yandexDisk:
        final yandexConfig = config.yandexDisk;
        if (yandexConfig == null) {
          return null;
        }
        final oauthClient = YandexDiskOAuthClient(yandexConfig);
        final tokenProvider = StoredOAuthTokenProvider(
          provider: provider,
          store: _syncAuthStore,
          refreshToken: oauthClient.refreshToken,
        );
        final apiClient = HttpYandexDiskApiClient(tokenProvider: tokenProvider);
        return YandexDiskSyncAdapter(apiClient: apiClient);
      case SyncProvider.webDav:
        final credentials = _webDavCredentials;
        if (credentials == null) {
          return null;
        }
        final baseUri = Uri.tryParse(credentials.baseUrl);
        if (baseUri == null) {
          return null;
        }
        final apiClient = HttpWebDavApiClient(
          baseUri: baseUri,
          auth: WebDavAuth.basic(
            credentials.username,
            credentials.password,
          ),
        );
        return WebDavSyncAdapter(apiClient: apiClient);
    }
  }

  Future<void> connectSyncProvider() async {
    if (_authInProgress) {
      return;
    }
    await _loadOAuthConfig();
    if (!isSyncProviderConfigured) {
      Log.d('Sync provider not configured: $_syncProvider');
      _setAuthError('Подключение недоступно. Проверь настройки подключения.');
      return;
    }
    if (_syncProvider == SyncProvider.webDav) {
      _setAuthError('WebDAV подключается через логин/пароль');
      return;
    }
    final authUrl = _buildAuthorizationUrl(_syncProvider);
    if (authUrl == null) {
      Log.d('Auth URL not built for provider: $_syncProvider');
      _setAuthError('Подключение недоступно. Проверь настройки подключения.');
      return;
    }
    final loopback = _loopbackRedirect(_syncProvider);
    _authInProgress = true;
    _authError = null;
    notifyListeners();
    if (loopback != null) {
      await _connectWithLoopback(authUrl, loopback);
      return;
    }
    final launched = await launchUrl(
      authUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      _authInProgress = false;
      _authState = null;
      _pendingAuthProvider = null;
      _setAuthError('Не удалось открыть браузер');
      notifyListeners();
    }
  }

  Future<void> disconnectSyncProvider() async {
    if (_syncProvider == SyncProvider.webDav) {
      await _syncAuthStore.clearWebDavCredentials();
      _webDavCredentials = null;
      await _loadProviderConnection(_syncProvider);
      await _refreshSyncAdapter();
      return;
    }
    await _syncAuthStore.clearToken(_syncProvider);
    await _loadProviderConnection(_syncProvider);
    await _refreshSyncAdapter();
  }

  Future<void> saveWebDavCredentials({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final trimmedBase = baseUrl.trim();
    final trimmedUser = username.trim();
    if (trimmedBase.isEmpty || trimmedUser.isEmpty) {
      _setAuthError('Заполни URL и логин');
      return;
    }
    final parsed = Uri.tryParse(trimmedBase);
    final scheme = parsed?.scheme.toLowerCase();
    if (parsed == null ||
        parsed.host.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      _setAuthError('URL должен начинаться с http:// или https://');
      return;
    }
    final normalizedBase =
        trimmedBase.endsWith('/') ? trimmedBase : '$trimmedBase/';
    final creds = WebDavCredentials(
      baseUrl: normalizedBase,
      username: trimmedUser,
      password: password,
    );
    await _syncAuthStore.saveWebDavCredentials(creds);
    _webDavCredentials = creds;
    _providerConnected[SyncProvider.webDav] = true;
    _authError = null;
    await _refreshSyncAdapter();
    notifyListeners();
  }

  Future<void> testSyncConnection() async {
    if (_connectionInProgress) {
      return;
    }
    final adapter = _syncAdapter;
    if (adapter == null) {
      _setAuthError('Адаптер не подключен');
      return;
    }
    _connectionInProgress = true;
    _authError = null;
    notifyListeners();
    try {
      final files = await adapter.listFiles();
      _setInfo('Подключение успешно (файлов: ${files.length})');
    } catch (error) {
      _setAuthError('Проверка не удалась: $error');
    } finally {
      _connectionInProgress = false;
      notifyListeners();
    }
  }

  Future<void> testWebDavCredentials({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    if (_connectionInProgress) {
      return;
    }
    final trimmedBase = baseUrl.trim();
    final trimmedUser = username.trim();
    if (trimmedBase.isEmpty || trimmedUser.isEmpty) {
      _setAuthError('Заполни URL и логин');
      return;
    }
    final parsed = Uri.tryParse(trimmedBase);
    final scheme = parsed?.scheme.toLowerCase();
    if (parsed == null ||
        parsed.host.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      _setAuthError('URL должен начинаться с http:// или https://');
      return;
    }
    _connectionInProgress = true;
    _authError = null;
    notifyListeners();
    try {
      final apiClient = HttpWebDavApiClient(
        baseUri: parsed,
        auth: WebDavAuth.basic(trimmedUser, password),
      );
      await apiClient.listFolder('/');
      _setInfo('WebDAV подключение успешно');
    } catch (error) {
      _setAuthError('WebDAV проверка не удалась: $error');
    } finally {
      _connectionInProgress = false;
      notifyListeners();
    }
  }

  Future<void> deleteRemoteSyncFiles() async {
    if (_deleteInProgress) {
      return;
    }
    final adapter = _syncAdapter;
    if (adapter == null) {
      _setAuthError('Адаптер не подключен');
      return;
    }
    _deleteInProgress = true;
    _authError = null;
    notifyListeners();
    try {
      for (final name in _syncFileNames) {
        await adapter.deleteFile(_buildSyncPath(name));
      }
      _setInfo('Файлы синка удалены в облаке');
    } catch (error) {
      _setAuthError('Не удалось удалить файлы: $error');
    } finally {
      _deleteInProgress = false;
      notifyListeners();
    }
  }

  String _buildSyncPath(String name) {
    final base = _syncEngine?.basePath ?? '';
    if (base.isEmpty) {
      return name;
    }
    if (base.endsWith('/')) {
      return '$base$name';
    }
    return '$base/$name';
  }

  static const List<String> _syncFileNames = <String>[
    'event_log.json',
    'state.json',
    'meta.json',
  ];

  Uri? _buildAuthorizationUrl(SyncProvider provider) {
    final config = _oauthConfig;
    if (config == null) {
      return null;
    }
    final state = _generateAuthState();
    Uri? url;
    switch (provider) {
      case SyncProvider.googleDrive:
        final google = config.googleDrive;
        if (google == null) {
          return null;
        }
        url = GoogleDriveOAuthClient(google).authorizationUrl(state: state);
        break;
      case SyncProvider.dropbox:
        final dropbox = config.dropbox;
        if (dropbox == null) {
          return null;
        }
        url = DropboxOAuthClient(dropbox).authorizationUrl(state: state);
        break;
      case SyncProvider.oneDrive:
        final oneDrive = config.oneDrive;
        if (oneDrive == null) {
          return null;
        }
        url = OneDriveOAuthClient(oneDrive).authorizationUrl(state: state);
        break;
      case SyncProvider.yandexDisk:
        final yandex = config.yandexDisk;
        if (yandex == null) {
          return null;
        }
        url = YandexDiskOAuthClient(yandex).authorizationUrl(state: state);
        break;
      case SyncProvider.webDav:
        return null;
    }
    _authState = state;
    _pendingAuthProvider = provider;
    return url;
  }

  void _handleAuthRedirect(Uri? uri) {
    if (uri == null) {
      return;
    }
    unawaited(_handleAuthRedirectAsync(uri));
  }

  Future<void> _handleAuthRedirectAsync(Uri uri) async {
    Log.d('Handle auth redirect: $uri');
    final provider = _pendingAuthProvider;
    final expectedState = _authState;
    if (provider == null || expectedState == null) {
      return;
    }
    final query = uri.queryParameters;
    if (query.isEmpty) {
      return;
    }
    if (query['state'] != expectedState) {
      return;
    }
    final error = query['error'];
    if (error != null && error.isNotEmpty) {
      _finishAuthWithError('OAuth error: $error');
      return;
    }
    final code = query['code'];
    if (code == null || code.isEmpty) {
      _finishAuthWithError('OAuth code отсутствует');
      return;
    }
    try {
      final token = await _exchangeAuthCode(provider, code);
      await _syncAuthStore.saveToken(provider, token);
      await _loadProviderConnection(provider);
      await _refreshSyncAdapter();
      _setInfo('${_providerLabel(provider)} подключен');
      _authError = null;
    } catch (error) {
      _finishAuthWithError('OAuth ошибка: $error');
      return;
    } finally {
      _authInProgress = false;
      _pendingAuthProvider = null;
      _authState = null;
      notifyListeners();
    }
  }

  Future<OAuthToken> _exchangeAuthCode(
    SyncProvider provider,
    String code,
  ) async {
    final config = _oauthConfig;
    if (config == null) {
      throw SyncAuthException('OAuth config missing');
    }
    switch (provider) {
      case SyncProvider.googleDrive:
        final google = config.googleDrive;
        if (google == null) {
          throw SyncAuthException('Google OAuth not configured');
        }
        return GoogleDriveOAuthClient(google).exchangeCode(code);
      case SyncProvider.dropbox:
        final dropbox = config.dropbox;
        if (dropbox == null) {
          throw SyncAuthException('Dropbox OAuth not configured');
        }
        return DropboxOAuthClient(dropbox).exchangeCode(code);
      case SyncProvider.oneDrive:
        final oneDrive = config.oneDrive;
        if (oneDrive == null) {
          throw SyncAuthException('OneDrive OAuth not configured');
        }
        return OneDriveOAuthClient(oneDrive).exchangeCode(code);
      case SyncProvider.yandexDisk:
        final yandex = config.yandexDisk;
        if (yandex == null) {
          throw SyncAuthException('Yandex OAuth not configured');
        }
        return YandexDiskOAuthClient(yandex).exchangeCode(code);
      case SyncProvider.webDav:
        throw SyncAuthException('OAuth provider not supported');
    }
  }

  void _finishAuthWithError(String message) {
    _authInProgress = false;
    _authState = null;
    _pendingAuthProvider = null;
    _setAuthError(message);
    notifyListeners();
  }

  String _generateAuthState() {
    final seed = Random().nextInt(1 << 32);
    return '${DateTime.now().microsecondsSinceEpoch}-${seed.toRadixString(16)}';
  }

  Uri? _loopbackRedirect(SyncProvider provider) {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return null;
    }
    if (provider != SyncProvider.dropbox) {
      return null;
    }
    final raw = _oauthConfig?.dropbox?.redirectUri;
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) {
      return null;
    }
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }
    if (host != 'localhost' && host != '127.0.0.1') {
      return null;
    }
    if (uri.port == 0) {
      return null;
    }
    return uri;
  }

  Future<void> _connectWithLoopback(Uri authUrl, Uri redirectUri) async {
    HttpServer? server;
    try {
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        redirectUri.port,
      );
    } catch (error) {
      Log.d('Loopback bind failed: $error');
      _finishAuthWithError('Подключение недоступно. Проверь настройки подключения.');
      return;
    }

    final launched = await launchUrl(
      authUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      await server.close(force: true);
      _authInProgress = false;
      _authState = null;
      _pendingAuthProvider = null;
      _setAuthError('Не удалось открыть браузер');
      notifyListeners();
      return;
    }

    final completer = Completer<void>();
    StreamSubscription<HttpRequest>? subscription;
    subscription = server.listen((request) async {
      Log.d('Loopback auth request: ${request.uri}');
      if (request.uri.path != redirectUri.path) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final fullUri = Uri(
        scheme: redirectUri.scheme,
        host: redirectUri.host,
        port: redirectUri.port,
        path: request.uri.path,
        query: request.uri.query,
      );
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<html><body>Можно вернуться в приложение.</body></html>',
      );
      await request.response.close();
      try {
        await _handleAuthRedirectAsync(fullUri);
      } catch (error) {
        Log.d('Loopback auth handling error: $error');
        _finishAuthWithError('Подключение не удалось');
      }
      await subscription?.cancel();
      await server?.close(force: true);
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    Future<void>.delayed(const Duration(minutes: 2), () async {
      if (completer.isCompleted) {
        return;
      }
      await subscription?.cancel();
      await server?.close(force: true);
      _finishAuthWithError('Время ожидания истекло');
      completer.complete();
    });

    await completer.future;
  }

  String _providerLabel(SyncProvider provider) {
    switch (provider) {
      case SyncProvider.googleDrive:
        return 'Google Drive';
      case SyncProvider.dropbox:
        return 'Dropbox';
      case SyncProvider.oneDrive:
        return 'OneDrive';
      case SyncProvider.yandexDisk:
        return 'Yandex Disk';
      case SyncProvider.webDav:
        return 'WebDAV';
    }
  }

  Future<void> _initSyncEngine() async {
    final adapter = _syncAdapter;
    if (adapter == null) {
      _syncEngine = null;
      return;
    }
    await _storeReady;
    await _syncEventLogStore.init();
    final deviceId = await _ensureDeviceId();
    _syncEngine = FileSyncEngine(
      adapter: adapter,
      libraryStore: _store,
      eventLogStore: _syncEventLogStore,
      deviceId: deviceId,
      storageService: _storageService,
    );
  }

  Future<void> _runFileSync() async {
    final engine = _syncEngine;
    if (engine == null || _syncInProgress) {
      return;
    }
    _syncInProgress = true;
    notifyListeners();
    try {
      final result = await engine.sync();
      _lastSyncAt = result.uploadedAt;
      _lastSyncSummary =
          'Events: ${result.appliedEvents}, state: ${result.appliedState}';
      if (result.appliedEvents > 0 || result.appliedState > 0) {
        await _loadLibrary();
      } else {
        notifyListeners();
      }
    } catch (e) {
      Log.d('File sync failed: $e');
    } finally {
      _syncInProgress = false;
      notifyListeners();
    }
  }

  Future<String> _ensureDeviceId() async {
    final existing = await _preferencesStore.loadDeviceId();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final randomSeed = Random().nextInt(1 << 32);
    final generated =
        'dev-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
        '-${randomSeed.toRadixString(16)}';
    await _preferencesStore.saveDeviceId(generated);
    return generated;
  }

  Future<void> _loadSyncProvider() async {
    final stored = await _preferencesStore.loadSyncProvider();
    if (stored == null || stored.isEmpty) {
      return;
    }
    _syncProvider = SyncProvider.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => SyncProvider.googleDrive,
    );
    notifyListeners();
  }

  void _addStubBook() {
    _books.add(
      LibraryBookItem(
        id: 'stub-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Imported book (stub) — ${DateTime.now()}',
        author: null,
        sourcePath: 'stub',
        storedPath: 'stub',
        coverPath: null,
        hash: 'stub',
        addedAt: DateTime.now(),
        lastOpenedAt: null,
        isMissing: false,
        notes: const <Note>[],
        highlights: const <Highlight>[],
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _globalSearchDebounce?.cancel();
    _authLinkSub?.cancel();
    super.dispose();
  }
}

class CoverPayload {
  const CoverPayload({required this.bytes, required this.extension});

  final List<int> bytes;
  final String? extension;
}

const Map<String, String> _fb2CoverExtensions = <String, String>{
  'image/jpeg': '.jpg',
  'image/jpg': '.jpg',
  'image/png': '.png',
  'image/gif': '.gif',
  'image/webp': '.webp',
};

@visibleForTesting
BookMetadata readFb2MetadataForTest(
  List<int> bytes,
  String fallbackTitle,
) =>
    _readFb2MetadataFromBytes(bytes, fallbackTitle);

@visibleForTesting
CoverPayload? readFb2CoverForTest(List<int> bytes) =>
    _readFb2CoverFromBytes(bytes);

Future<CoverPayload?> _readCoverBytes(EpubBookRef bookRef) async {
  try {
    final manifestItems = bookRef.Schema?.Package?.Manifest?.Items;
    if (manifestItems != null) {
      for (final item in manifestItems) {
        if (_isCoverManifestItem(item)) {
          final payload = await _readImageBytesFromHref(
            bookRef,
            item.Href,
            mediaType: item.MediaType,
          );
          if (payload != null) {
            return payload;
          }
        }
      }
    }

    final guideItems = bookRef.Schema?.Package?.Guide?.Items;
    if (guideItems != null) {
      for (final item in guideItems) {
        final type = item.Type?.toLowerCase() ?? '';
        if (type.contains('cover')) {
          final payload = await _readImageBytesFromHref(bookRef, item.Href);
          if (payload != null) {
            return payload;
          }
        }
      }
    }

    final images = bookRef.Content?.Images;
    if (images != null && images.isNotEmpty) {
      CoverPayload? bestPayload;
      for (final entry in images.entries) {
        try {
          final bytes = await entry.value.readContentAsBytes();
          if (bytes.isNotEmpty &&
              (bestPayload == null ||
                  bytes.length > bestPayload.bytes.length)) {
            bestPayload = CoverPayload(
              bytes: bytes,
              extension: _extensionFromPath(entry.key),
            );
          }
        } catch (e) {
          Log.d('Cover image read failed for ${entry.key}: $e');
        }
      }
      if (bestPayload != null) {
        return bestPayload;
      }
    }
  } catch (e) {
    Log.d('Cover image lookup failed: $e');
  }

  return null;
}

String _buildSnippet(String text, int matchIndex, int matchLength) {
  const context = 36;
  final start = max(0, matchIndex - context);
  final end = min(text.length, matchIndex + matchLength + context);
  final raw = text.substring(start, end);
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final prefix = start > 0 ? '…' : '';
  final suffix = end < text.length ? '…' : '';
  return '$prefix$normalized$suffix';
}

bool _isCoverManifestItem(EpubManifestItem item) {
  final mediaType = item.MediaType?.toLowerCase() ?? '';
  if (!mediaType.startsWith('image/')) {
    return false;
  }
  final properties = item.Properties?.toLowerCase() ?? '';
  if (properties.contains('cover-image')) {
    return true;
  }
  return _looksLikeCover(item.Id) || _looksLikeCover(item.Href);
}

bool _looksLikeCover(String? value) {
  if (value == null) {
    return false;
  }
  return value.toLowerCase().contains('cover');
}

Future<CoverPayload?> _readImageBytesFromHref(
  EpubBookRef bookRef,
  String? href, {
  String? mediaType,
}
) async {
  if (href == null || href.isEmpty) {
    return null;
  }
  final images = bookRef.Content?.Images;
  if (images == null || images.isEmpty) {
    return null;
  }
  final normalized = href.startsWith('./') ? href.substring(2) : href;
  final direct = images[normalized] ?? images[href];
  if (direct != null) {
    try {
      final bytes = await direct.readContentAsBytes();
      return CoverPayload(
        bytes: bytes,
        extension: _extensionFromMediaType(mediaType) ??
            _extensionFromPath(normalized),
      );
    } catch (e) {
      Log.d('Cover image read failed for $normalized: $e');
      return null;
    }
  }
  final targetBase = p.basename(normalized).toLowerCase();
  for (final entry in images.entries) {
    if (p.basename(entry.key).toLowerCase() == targetBase) {
      try {
        final bytes = await entry.value.readContentAsBytes();
        return CoverPayload(
          bytes: bytes,
          extension: _extensionFromPath(entry.key),
        );
      } catch (e) {
        Log.d('Cover image read failed for ${entry.key}: $e');
        return null;
      }
    }
  }
  return null;
}

String? _extensionFromMediaType(String? mediaType) {
  final lower = mediaType?.toLowerCase().trim();
  if (lower == null || lower.isEmpty) {
    return null;
  }
  if (lower.contains('png')) {
    return '.png';
  }
  if (lower.contains('jpeg') || lower.contains('jpg')) {
    return '.jpg';
  }
  if (lower.contains('gif')) {
    return '.gif';
  }
  if (lower.contains('webp')) {
    return '.webp';
  }
  if (lower.contains('bmp')) {
    return '.bmp';
  }
  return null;
}

String? _extensionFromPath(String path) {
  final ext = p.extension(path).toLowerCase();
  if (ext.isEmpty) {
    return null;
  }
  if (ext.length > 5) {
    return null;
  }
  return ext;
}

bool _isSupportedExtension(String path) {
  final ext = _extensionFromPath(path);
  if (ext == null) {
    return false;
  }
  return LibraryController._supportedExtensions.contains(ext);
}

Future<String?> _validateZipContainsBook(File zipFile) async {
  try {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final name = file.name.toLowerCase();
      if (name.endsWith('.fb2') ||
          name.endsWith('.xml') ||
          name.endsWith('.epub')) {
        return null;
      }
    }
    return 'Архив не содержит книгу (.fb2/.xml/.epub)';
  } catch (e) {
    Log.d('Failed to validate zip: $e');
    return 'Не удалось прочитать архив';
  }
}

int _sortByLastOpenedAt(LibraryBookItem a, LibraryBookItem b) {
  final aTime = a.lastOpenedAt ?? a.addedAt;
  final bTime = b.lastOpenedAt ?? b.addedAt;
  final cmp = bTime.compareTo(aTime);
  if (cmp != 0) {
    return cmp;
  }
  return a.title.compareTo(b.title);
}

class BookMetadata {
  const BookMetadata({required this.title, required this.author});

  final String title;
  final String? author;
}

Future<BookMetadata> _readMetadata(String path, String fallbackTitle) async {
  try {
    final extension = p.extension(path).toLowerCase();
    final bytes = await File(path).readAsBytes();
    if (extension == '.epub') {
      try {
        final bookRef = await EpubReader.openBook(bytes);
        return _extractMetadata(
          fallbackTitle: fallbackTitle,
          title: bookRef.Title,
          author: bookRef.Author,
          authorList: bookRef.AuthorList,
          schema: bookRef.Schema,
        );
      } catch (e) {
        Log.d('Failed to open EPUB metadata: $e');
        return BookMetadata(title: fallbackTitle, author: null);
      }
    }
    if (extension == '.fb2') {
      return _readFb2MetadataFromBytes(bytes, fallbackTitle);
    }
    if (extension == '.zip') {
      return _readFb2MetadataFromZip(bytes, fallbackTitle);
    }
    return BookMetadata(title: fallbackTitle, author: null);
  } catch (e) {
    Log.d('Failed to read EPUB bytes: $e');
    return BookMetadata(title: fallbackTitle, author: null);
  }
}

String? _firstNonEmpty(Iterable<String?> candidates) {
  for (final candidate in candidates) {
    final value = candidate?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

BookMetadata _extractMetadata({
  required String fallbackTitle,
  required String? title,
  required String? author,
  required List<String?>? authorList,
  required EpubSchema? schema,
}) {
  final rawTitle = _firstNonEmpty(
    [
      title,
      ...?schema?.Package?.Metadata?.Titles,
      ...?schema?.Navigation?.DocTitle?.Titles,
    ],
  );
  final rawAuthor = _firstNonEmpty(
    [
      author,
      ...?authorList,
      ...?schema?.Package?.Metadata?.Creators
          ?.map((creator) => creator.Creator),
      ...?schema?.Navigation?.DocAuthors
          ?.expand((author) => author.Authors ?? const <String>[]),
    ],
  );
  final resolvedTitle =
      (rawTitle == null || rawTitle.isEmpty) ? fallbackTitle : rawTitle;
  final resolvedAuthor =
      (rawAuthor == null || rawAuthor.isEmpty) ? null : rawAuthor;
  return BookMetadata(title: resolvedTitle, author: resolvedAuthor);
}

BookMetadata _readFb2MetadataFromBytes(
  List<int> bytes,
  String fallbackTitle,
) {
  try {
    final xml = _decodeFb2Xml(bytes);
    return _extractFb2Metadata(xml, fallbackTitle);
  } catch (e) {
    Log.d('Failed to parse FB2 metadata: $e');
    return BookMetadata(title: fallbackTitle, author: null);
  }
}

BookMetadata _readFb2MetadataFromZip(
  List<int> bytes,
  String fallbackTitle,
) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final xml = _extractFb2XmlFromArchive(archive);
    if (xml == null) {
      return BookMetadata(title: fallbackTitle, author: null);
    }
    return _extractFb2Metadata(xml, fallbackTitle);
  } catch (e) {
    Log.d('Failed to parse FB2.zip metadata: $e');
    return BookMetadata(title: fallbackTitle, author: null);
  }
}

CoverPayload? _readFb2CoverFromBytes(List<int> bytes) {
  try {
    final xml = _decodeFb2Xml(bytes);
    return _extractFb2Cover(xml);
  } catch (e) {
    Log.d('Failed to parse FB2 cover: $e');
    return null;
  }
}

CoverPayload? _readFb2CoverFromZipBytes(List<int> bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final xml = _extractFb2XmlFromArchive(archive);
    if (xml == null) {
      return null;
    }
    return _extractFb2Cover(xml);
  } catch (e) {
    Log.d('Failed to parse FB2.zip cover: $e');
    return null;
  }
}

String _decodeFb2Xml(List<int> bytes) {
  final encoding = _detectXmlEncoding(bytes);
  final normalized = encoding?.toLowerCase();
  if (normalized == 'windows-1251' ||
      normalized == 'win-1251' ||
      normalized == 'cp1251') {
    return _decodeCp1251(bytes);
  }
  if (normalized == 'utf-8' || normalized == 'utf8') {
    return utf8.decode(bytes);
  }
  if (normalized == 'latin1' || normalized == 'iso-8859-1') {
    return latin1.decode(bytes);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    try {
      return _decodeCp1251(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }
}

String? _detectXmlEncoding(List<int> bytes) {
  final header = String.fromCharCodes(bytes.take(200));
  final match = RegExp('encoding=["\\\']([^"\\\']+)["\\\']')
      .firstMatch(header);
  return match?.group(1);
}

String _decodeCp1251(List<int> bytes) {
  const table = <int>[
    0x0402,
    0x0403,
    0x201A,
    0x0453,
    0x201E,
    0x2026,
    0x2020,
    0x2021,
    0x20AC,
    0x2030,
    0x0409,
    0x2039,
    0x040A,
    0x040C,
    0x040B,
    0x040F,
    0x0452,
    0x2018,
    0x2019,
    0x201C,
    0x201D,
    0x2022,
    0x2013,
    0x2014,
    0xFFFD,
    0x2122,
    0x0459,
    0x203A,
    0x045A,
    0x045C,
    0x045B,
    0x045F,
    0x00A0,
    0x040E,
    0x045E,
    0x0408,
    0x00A4,
    0x0490,
    0x00A6,
    0x00A7,
    0x0401,
    0x00A9,
    0x0404,
    0x00AB,
    0x00AC,
    0x00AD,
    0x00AE,
    0x0407,
    0x00B0,
    0x00B1,
    0x0406,
    0x0456,
    0x0491,
    0x00B5,
    0x00B6,
    0x00B7,
    0x0451,
    0x2116,
    0x0454,
    0x00BB,
    0x0458,
    0x0405,
    0x0455,
    0x0457,
    0x0410,
    0x0411,
    0x0412,
    0x0413,
    0x0414,
    0x0415,
    0x0416,
    0x0417,
    0x0418,
    0x0419,
    0x041A,
    0x041B,
    0x041C,
    0x041D,
    0x041E,
    0x041F,
    0x0420,
    0x0421,
    0x0422,
    0x0423,
    0x0424,
    0x0425,
    0x0426,
    0x0427,
    0x0428,
    0x0429,
    0x042A,
    0x042B,
    0x042C,
    0x042D,
    0x042E,
    0x042F,
    0x0430,
    0x0431,
    0x0432,
    0x0433,
    0x0434,
    0x0435,
    0x0436,
    0x0437,
    0x0438,
    0x0439,
    0x043A,
    0x043B,
    0x043C,
    0x043D,
    0x043E,
    0x043F,
    0x0440,
    0x0441,
    0x0442,
    0x0443,
    0x0444,
    0x0445,
    0x0446,
    0x0447,
    0x0448,
    0x0449,
    0x044A,
    0x044B,
    0x044C,
    0x044D,
    0x044E,
    0x044F,
  ];
  final runes = List<int>.generate(bytes.length, (index) {
    final value = bytes[index];
    if (value < 0x80) {
      return value;
    }
    return table[value - 0x80];
  });
  return String.fromCharCodes(runes);
}

String? _extractFb2XmlFromArchive(Archive archive) {
  for (final file in archive.files) {
    if (!file.isFile) {
      continue;
    }
    final name = file.name.toLowerCase();
    if (!name.endsWith('.fb2') && !name.endsWith('.xml')) {
      continue;
    }
    final content = file.content;
    if (content is List<int>) {
      return _decodeFb2Xml(content);
    }
  }
  return null;
}

BookMetadata _extractFb2Metadata(String xml, String fallbackTitle) {
  final doc = XmlDocument.parse(xml);
  final titleInfo = doc.findAllElements('title-info').firstWhere(
        (_) => true,
        orElse: () => XmlElement(XmlName('title-info')),
      );
  final scope = titleInfo.name.local == 'title-info' ? titleInfo : doc;
  final title = _firstNonEmpty(
        scope.findAllElements('book-title').map((element) => element.innerText),
      ) ??
      fallbackTitle;
  final author = _extractFb2Author(scope);
  return BookMetadata(title: title, author: author);
}

String? _extractFb2Author(XmlNode node) {
  final author = node.findAllElements('author').firstWhere(
        (_) => true,
        orElse: () => XmlElement(XmlName('author')),
      );
  if (author.name.local != 'author') {
    return null;
  }
  final parts = <String>[];
  final first = _firstNonEmpty(
    author.findElements('first-name').map((element) => element.innerText),
  );
  final middle = _firstNonEmpty(
    author.findElements('middle-name').map((element) => element.innerText),
  );
  final last = _firstNonEmpty(
    author.findElements('last-name').map((element) => element.innerText),
  );
  if (first != null) {
    parts.add(first);
  }
  if (middle != null) {
    parts.add(middle);
  }
  if (last != null) {
    parts.add(last);
  }
  if (parts.isEmpty) {
    return null;
  }
  return parts.join(' ');
}

CoverPayload? _extractFb2Cover(String xml) {
  final doc = XmlDocument.parse(xml);
  final image = doc.findAllElements('coverpage').expand((node) {
    return node.findAllElements('image');
  }).firstWhere(
        (_) => true,
        orElse: () => XmlElement(XmlName('image')),
      );
  if (image.name.local != 'image') {
    return null;
  }
  String? href;
  for (final attr in image.attributes) {
    if (attr.name.local == 'href') {
      href = attr.value;
      break;
    }
  }
  if (href == null || href.isEmpty) {
    return null;
  }
  final id = href.startsWith('#') ? href.substring(1) : href;
  final binary = doc.findAllElements('binary').firstWhere(
        (node) => node.getAttribute('id') == id,
        orElse: () => XmlElement(XmlName('binary')),
      );
  if (binary.name.local != 'binary') {
    return null;
  }
  final contentType = binary.getAttribute('content-type');
  final extension = _fb2CoverExtensions[contentType ?? ''];
  final raw = binary.innerText.replaceAll(RegExp(r'\s+'), '');
  if (raw.isEmpty) {
    return null;
  }
  final bytes = base64.decode(raw);
  return CoverPayload(bytes: bytes, extension: extension);
}
