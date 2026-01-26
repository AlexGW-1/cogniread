import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/core/services/storage_service_impl.dart';
import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/library/data/library_preferences_store.dart';
import 'package:cogniread/src/features/library/data/free_notes_store.dart';
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
import 'package:cogniread/src/features/sync/file_sync/fallback_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/resilient_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/smb_credentials.dart';
import 'package:cogniread/src/features/sync/file_sync/smb_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_credentials.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_oauth_config.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_auth_store.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_errors.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_provider.dart';
import 'package:cogniread/src/features/sync/file_sync/stored_oauth_token_provider.dart';
import 'package:cogniread/src/features/search/search_index_service.dart';
import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:path/path.dart' as p;
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart';

class _WebDavPortCandidate {
  const _WebDavPortCandidate(this.scheme, this.port);

  final String scheme;
  final int port;
}

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

enum LibraryViewMode { list, grid }

enum LibrarySearchResultType { book, note, highlight }

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

enum NotesItemType { note, highlight, freeNote }

class NotesItem {
  const NotesItem({
    required this.type,
    required this.id,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.bookId,
    this.bookTitle,
    this.bookAuthor,
    this.anchor,
    this.excerpt = '',
    this.text = '',
  });

  final NotesItemType type;
  final String id;
  final String? bookId;
  final String? bookTitle;
  final String? bookAuthor;
  final String? anchor;
  final String excerpt;
  final String text;
  final String color;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get key => '${type.name}:${bookId ?? ''}:$id';
}

class LibraryController extends ChangeNotifier {
  static const bool _showAllSyncProviders = bool.fromEnvironment(
    'COGNIREAD_SHOW_ALL_SYNC_PROVIDERS',
    defaultValue: false,
  );
  static bool get _developerMode => _showAllSyncProviders;
  LibraryController({
    StorageService? storageService,
    LibraryStore? store,
    FreeNotesStore? freeNotesStore,
    LibraryPreferencesStore? preferencesStore,
    Future<String?> Function()? pickEpubPath,
    SyncAdapter? syncAdapter,
    bool stubImport = false,
  }) : _storageService = storageService ?? AppStorageService(),
       _store = store ?? LibraryStore(),
       _freeNotesStore = freeNotesStore ?? FreeNotesStore(),
       _preferencesStore = preferencesStore ?? LibraryPreferencesStore(),
       _pickEpubPath = pickEpubPath,
       _fallbackSyncAdapter = syncAdapter,
       _syncAdapter = syncAdapter,
       _stubImport = stubImport {
    _searchIndex = SearchIndexService(
      store: _store,
      freeNotesStore: _freeNotesStore,
    );
  }

  final StorageService _storageService;
  final LibraryStore _store;
  final FreeNotesStore _freeNotesStore;
  final LibraryPreferencesStore _preferencesStore;
  final Future<String?> Function()? _pickEpubPath;
  final SyncAdapter? _fallbackSyncAdapter;
  SyncAdapter? _syncAdapter;
  final bool _stubImport;
  Future<void>? _storeReady;
  final EventLogStore _syncEventLogStore = EventLogStore();
  final SyncAuthStore _syncAuthStore = SyncAuthStore();
  late final SearchIndexService _searchIndex;
  Listenable? _notesDataListenable;
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
  SmbCredentials? _smbCredentials;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri?>? _authLinkSub;
  final Map<SyncProvider, bool> _providerConnected = <SyncProvider, bool>{};
  String? _yandexPkceVerifier;
  String? _dropboxPkceVerifier;
  Timer? _autoSyncTimer;
  Timer? _scheduledSyncTimer;
  bool _pendingSync = false;
  bool _autoSyncDisabled = false;

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
  List<String> _searchHistory = <String>[];
  static const Duration _autoSyncInterval = Duration(minutes: 15);
  static const Duration _syncDebounce = Duration(seconds: 5);
  DateTime? _lastSyncAt;
  bool? _lastSyncOk;
  String? _lastSyncSummary;

  bool get loading => _loading;
  List<LibraryBookItem> get books => List<LibraryBookItem>.unmodifiable(_books);
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;
  String get query => _query;
  LibraryViewMode get viewMode => _viewMode;
  SyncProvider get syncProvider => _syncProvider;

  Listenable get notesDataListenable => _notesDataListenable ?? this;
  bool get syncInProgress => _syncInProgress;
  bool get authInProgress => _authInProgress;
  bool get connectionInProgress => _connectionInProgress;
  bool get deleteInProgress => _deleteInProgress;
  String? get authError => _authError;
  SyncOAuthConfig? get oauthConfig => _oauthConfig;
  bool get isSyncProviderConnected =>
      _providerConnected[_syncProvider] ?? false;
  bool get isNasProvider => _syncProvider == SyncProvider.webDav;
  bool get isBasicAuthProvider => isNasProvider;
  bool get isSyncProviderConfigured =>
      _oauthConfig?.isConfigured(_syncProvider) ?? false;
  WebDavCredentials? get webDavCredentials => _webDavCredentials;
  SmbCredentials? get smbCredentials => _smbCredentials;
  WebDavCredentials? get basicAuthCredentials =>
      isNasProvider ? _webDavCredentials : null;
  DateTime? get lastSyncAt => _lastSyncAt;
  bool? get lastSyncOk => _lastSyncOk;
  String? get lastSyncSummary => _lastSyncSummary;
  String? get logFilePath => Log.logFilePath;
  SearchIndexService get searchIndex => _searchIndex;
  String get syncAdapterLabel =>
      _syncAdapter == null ? 'none' : _providerLabel(_syncProvider);
  bool get requiresManualOAuthCode {
    if (_syncProvider != SyncProvider.yandexDisk) {
      return false;
    }
    final redirectUri = _oauthConfig?.yandexDisk?.redirectUri ?? '';
    return redirectUri.contains('oauth.yandex.ru/verification_code');
  }

  List<SyncProvider> get availableSyncProviders {
    final config = _oauthConfig;
    final candidates = <SyncProvider>[
      SyncProvider.googleDrive,
      SyncProvider.dropbox,
      SyncProvider.oneDrive,
      SyncProvider.yandexDisk,
      SyncProvider.webDav,
    ];
    if (_developerMode) {
      return candidates;
    }
    if (config == null) {
      return <SyncProvider>[SyncProvider.webDav];
    }
    return candidates
        .where(
          (provider) =>
              provider == SyncProvider.webDav || config.isConfigured(provider),
        )
        .toList();
  }

  String get globalSearchQuery => _globalSearchQuery;
  bool get globalSearching => _globalSearching;
  List<LibrarySearchResult> get globalSearchResults =>
      List<LibrarySearchResult>.unmodifiable(_globalSearchResults);
  List<String> get searchHistory => List<String>.unmodifiable(_searchHistory);

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

  Future<Uri?> beginOAuthConnection() async {
    if (_authInProgress) {
      return null;
    }
    await _loadOAuthConfig();
    if (!isSyncProviderConfigured) {
      Log.d('Sync provider not configured: $_syncProvider');
      _setAuthError(_oauthNotConfiguredMessage(_syncProvider));
      return null;
    }
    if (isNasProvider) {
      _setAuthError('Провайдер подключается через ручные настройки');
      return null;
    }
    final authUrl = _buildAuthorizationUrl(_syncProvider);
    if (authUrl == null) {
      Log.d('Auth URL not built for provider: $_syncProvider');
      _setAuthError('Подключение недоступно. Проверь настройки подключения.');
      return null;
    }
    _authInProgress = true;
    _authError = null;
    notifyListeners();
    return authUrl;
  }

  Future<void> submitOAuthCode(String code) async {
    final provider = _pendingAuthProvider;
    if (provider == null) {
      _setAuthError('Подключение не активно');
      return;
    }
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      _setAuthError('Введи код');
      return;
    }
    try {
      final token = await _exchangeAuthCode(provider, trimmed);
      await _syncAuthStore.saveToken(provider, token);
      await _loadProviderConnection(provider);
      await _refreshSyncAdapter();
      _setInfo('${_providerLabel(provider)} подключен');
      _authError = null;
    } catch (error) {
      if (_showAllSyncProviders) {
        _setAuthError('Подключение не удалось: $error');
      } else {
        _setAuthError(
          'Подключение не удалось. Проверь код и попробуй ещё раз.',
        );
      }
    } finally {
      _authInProgress = false;
      _pendingAuthProvider = null;
      _authState = null;
      _yandexPkceVerifier = null;
      _dropboxPkceVerifier = null;
      notifyListeners();
    }
  }

  void cancelOAuthConnection([String? message]) {
    _authInProgress = false;
    _pendingAuthProvider = null;
    _authState = null;
    _yandexPkceVerifier = null;
    _dropboxPkceVerifier = null;
    if (message != null && message.trim().isNotEmpty) {
      _setAuthError(message.trim());
    }
    notifyListeners();
  }

  Future<void> init() async {
    try {
      if (_stubImport) {
        _storeReady = Future<void>.value();
        _addStubBook();
        _setInfo('Книга добавлена');
        _loading = false;
        notifyListeners();
        return;
      }
      _storeReady = _store.init();
      await _storeReady;
      await _freeNotesStore.init();
      _notesDataListenable = Listenable.merge(<Listenable>[
        _store.listenable(),
        _freeNotesStore.listenable(),
      ]);
      await _preferencesStore.init();
      await _syncAuthStore.init();
      await _loadSearchHistory();
      await _loadOAuthConfig();
      await _initAuthLinks();
      await _ensureDeviceId();
      await _loadViewMode();
      await _loadSyncStatus();
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
    } catch (error) {
      Log.d('LibraryController init failed: $error');
      _handleSyncError(error);
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

  Future<void> _loadSyncStatus() async {
    final snapshot = await _preferencesStore.loadSyncStatus();
    if (snapshot == null) {
      return;
    }
    _lastSyncAt = snapshot.at;
    _lastSyncOk = snapshot.ok;
    _lastSyncSummary = snapshot.summary;
    notifyListeners();
  }

  Future<void> _loadSearchHistory() async {
    try {
      _searchHistory = await _preferencesStore.loadSearchHistory();
      notifyListeners();
    } catch (_) {
      _searchHistory = <String>[];
    }
  }

  Future<void> addSearchHistoryQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _searchHistory = <String>[
      trimmed,
      ..._searchHistory.where((item) => item != trimmed),
    ];
    if (_searchHistory.length > 50) {
      _searchHistory = _searchHistory.sublist(0, 50);
    }
    notifyListeners();
    try {
      await _preferencesStore.saveSearchHistory(_searchHistory);
    } catch (error) {
      Log.d('Failed to save search history: $error');
    }
  }

  Future<void> removeSearchHistoryQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final next = _searchHistory.where((item) => item != trimmed).toList();
    if (next.length == _searchHistory.length) {
      return;
    }
    _searchHistory = next;
    notifyListeners();
    try {
      await _preferencesStore.saveSearchHistory(_searchHistory);
    } catch (error) {
      Log.d('Failed to save search history: $error');
    }
  }

  Future<void> clearSearchHistory() async {
    if (_searchHistory.isEmpty) {
      return;
    }
    _searchHistory = <String>[];
    notifyListeners();
    try {
      await _preferencesStore.clearSearchHistory();
    } catch (error) {
      Log.d('Failed to clear search history: $error');
    }
  }

  Future<List<NotesItem>> loadAllNotesItems() async {
    if (_stubImport) {
      return const <NotesItem>[];
    }
    await _storeReady;
    await _freeNotesStore.init();
    try {
      final entries = await _store.loadAll();
      final items = <NotesItem>[];
      for (final entry in entries) {
        for (final note in entry.notes) {
          items.add(
            NotesItem(
              type: NotesItemType.note,
              id: note.id,
              bookId: entry.id,
              bookTitle: entry.title,
              bookAuthor: entry.author,
              anchor: note.anchor,
              excerpt: note.excerpt,
              text: note.noteText,
              color: note.color,
              createdAt: note.createdAt,
              updatedAt: note.updatedAt,
            ),
          );
        }
        for (final highlight in entry.highlights) {
          items.add(
            NotesItem(
              type: NotesItemType.highlight,
              id: highlight.id,
              bookId: entry.id,
              bookTitle: entry.title,
              bookAuthor: entry.author,
              anchor: highlight.anchor,
              excerpt: highlight.excerpt,
              color: highlight.color,
              createdAt: highlight.createdAt,
              updatedAt: highlight.updatedAt,
            ),
          );
        }
      }
      final freeNotes = await _freeNotesStore.loadAll();
      for (final note in freeNotes) {
        items.add(
          NotesItem(
            type: NotesItemType.freeNote,
            id: note.id,
            text: note.text,
            color: note.color,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
          ),
        );
      }
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return items;
    } catch (error) {
      Log.d('Failed to load notes items: $error');
      rethrow;
    }
  }

  Future<NotesItem?> loadFreeNoteItem(String id) async {
    await _freeNotesStore.init();
    final note = await _freeNotesStore.getById(id);
    if (note == null) {
      return null;
    }
    return NotesItem(
      type: NotesItemType.freeNote,
      id: note.id,
      text: note.text,
      color: note.color,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    );
  }

  Future<void> addFreeNote({
    required String text,
    required String color,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _freeNotesStore.init();
    final now = DateTime.now().toUtc();
    final note = FreeNote(
      id: 'fn-${now.microsecondsSinceEpoch}',
      text: trimmed,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await _freeNotesStore.add(note);
    _setInfo('Заметка сохранена');
    notifyListeners();
  }

  Future<void> updateFreeNote({
    required String id,
    required String text,
    required String color,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _freeNotesStore.init();
    final existing = await _freeNotesStore.getById(id);
    if (existing == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    final updated = FreeNote(
      id: existing.id,
      text: trimmed,
      color: color,
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    await _freeNotesStore.update(updated);
    _setInfo('Заметка обновлена');
    notifyListeners();
  }

  Future<void> deleteNotesItems(List<NotesItem> items) async {
    if (items.isEmpty) {
      return;
    }
    await _storeReady;
    await _freeNotesStore.init();
    for (final item in items) {
      switch (item.type) {
        case NotesItemType.note:
          final bookId = item.bookId;
          if (bookId == null) {
            continue;
          }
          await _store.removeNote(bookId, item.id);
          break;
        case NotesItemType.highlight:
          final bookId = item.bookId;
          if (bookId == null) {
            continue;
          }
          await _store.removeHighlight(bookId, item.id);
          break;
        case NotesItemType.freeNote:
          await _freeNotesStore.remove(item.id);
          break;
      }
    }
    _setInfo('Удалено: ${items.length}');
    notifyListeners();
  }

  Future<void> exportNotesItems(List<NotesItem> items) async {
    if (items.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc();
    final timestamp = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final suggestedName = 'cogniread_notes_$timestamp.zip';
    final destPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Экспорт заметок',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    if (destPath == null || destPath.trim().isEmpty) {
      return;
    }
    try {
      final archive = Archive();
      final jsonText = _buildNotesExportJson(items, generatedAt: now);
      final mdText = _buildNotesExportMarkdown(items, generatedAt: now);
      final jsonBytes = utf8.encode(jsonText);
      final mdBytes = utf8.encode(mdText);
      archive.addFile(ArchiveFile('notes.json', jsonBytes.length, jsonBytes));
      archive.addFile(ArchiveFile('notes.md', mdBytes.length, mdBytes));
      final bytes = ZipEncoder().encode(archive);
      if (bytes == null) {
        _setError('Не удалось подготовить экспорт');
        notifyListeners();
        return;
      }
      await File(destPath).writeAsBytes(bytes, flush: true);
      _setInfo('Экспорт сохранён: $destPath');
      notifyListeners();
    } catch (error) {
      _setError('Не удалось сохранить экспорт: $error');
      notifyListeners();
    }
  }

  String _buildNotesExportJson(
    List<NotesItem> items, {
    required DateTime generatedAt,
  }) {
    final sorted = items.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final payload = <String, Object?>{
      'generatedAt': generatedAt.toIso8601String(),
      'items':
          sorted.map((item) {
            return <String, Object?>{
              'type':
                  switch (item.type) {
                    NotesItemType.note => 'note',
                    NotesItemType.highlight => 'highlight',
                    NotesItemType.freeNote => 'free_note',
                  },
              'id': item.id,
              'bookId': item.bookId,
              'bookTitle': item.bookTitle,
              'bookAuthor': item.bookAuthor,
              'anchor': item.anchor,
              'excerpt': item.excerpt,
              'text': item.text,
              'color': item.color,
              'createdAt': item.createdAt.toIso8601String(),
              'updatedAt': item.updatedAt.toIso8601String(),
            };
          }).toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  String _buildNotesExportMarkdown(
    List<NotesItem> items, {
    required DateTime generatedAt,
  }) {
    final sorted = items.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final buffer = StringBuffer()
      ..writeln('# CogniRead — Export (Notes)')
      ..writeln()
      ..writeln('GeneratedAt: ${generatedAt.toIso8601String()}')
      ..writeln();
    for (final item in sorted) {
      final date = item.updatedAt.toIso8601String();
      final color = item.color;
      final title =
          item.type == NotesItemType.freeNote
              ? 'Без книги'
              : (item.bookTitle ?? 'Без названия');
      final typeLabel =
          switch (item.type) {
            NotesItemType.note => 'Заметка',
            NotesItemType.highlight => 'Выделение',
            NotesItemType.freeNote => 'Заметка',
          };
      final text = item.text.trim();
      final excerpt = item.excerpt.trim();
      buffer.writeln('- [$date] ($color) $title · $typeLabel');
      if (text.isNotEmpty) {
        buffer.writeln('  $text');
      }
      if (excerpt.isNotEmpty) {
        buffer.writeln('  > $excerpt');
      }
    }
    return buffer.toString().trimRight();
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
    final normalized =
        provider == SyncProvider.synologyDrive || provider == SyncProvider.smb
        ? SyncProvider.webDav
        : provider;
    if (!_developerMode && !_isProviderUsable(normalized)) {
      _syncProvider = SyncProvider.webDav;
      notifyListeners();
      await _preferencesStore.saveSyncProvider(_syncProvider.name);
      await _loadProviderConnection(_syncProvider);
      await _refreshSyncAdapter();
      _setAuthError('Этот провайдер синхронизации пока недоступен.');
      return;
    }
    if (_syncProvider == normalized) {
      return;
    }
    _syncProvider = normalized;
    notifyListeners();
    await _preferencesStore.saveSyncProvider(_syncProvider.name);
    await _loadProviderConnection(_syncProvider);
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

  Future<void> resetSyncSettingsForTesting({bool resetDeviceId = true}) async {
    if (_syncInProgress || _authInProgress || _connectionInProgress) {
      _setAuthError('Дождись окончания операции и повтори');
      return;
    }
    _autoSyncDisabled = false;
    _pendingSync = false;
    _autoSyncTimer?.cancel();
    _scheduledSyncTimer?.cancel();

    await _syncAuthStore.clearAll();
    await _preferencesStore.clearSyncProvider();
    await _preferencesStore.clearSyncOAuthConfig();
    await _preferencesStore.clearSyncStatus();
    if (resetDeviceId) {
      await _preferencesStore.clearDeviceId();
    }

    // After clearing stored overrides, reload config from assets/files so the
    // provider dropdown doesn't collapse to WebDAV-only.
    await _loadOAuthConfig();
    _providerConnected.clear();
    _webDavCredentials = null;
    _smbCredentials = null;
    _syncProvider = SyncProvider.webDav;
    _lastSyncAt = null;
    _lastSyncOk = null;
    _lastSyncSummary = null;
    _authError = null;

    _syncAdapter = _fallbackSyncAdapter;
    await _initSyncEngine();
    _restartAutoSyncTimer();
    notifyListeners();
    _setInfo('Настройки синхронизации сброшены');
  }

  Future<void> copyLogPath() async {
    final path = logFilePath;
    if (path == null || path.trim().isEmpty) {
      _setAuthError('Лог пока недоступен');
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    _setInfo('Путь к логу скопирован');
  }

  Future<void> openLogFolder() async {
    final srcPath = logFilePath;
    if (srcPath == null || srcPath.trim().isEmpty) {
      _setAuthError('Лог пока недоступен');
      return;
    }
    try {
      // `launchUrl(Uri.file(log))` opens the file in the default handler
      // (Console.app on macOS), while the UI expects opening the *folder*.
      if (Platform.isMacOS) {
        final exists = await File(srcPath).exists();
        if (exists) {
          final reveal = await Process.run('open', <String>['-R', srcPath]);
          if (reveal.exitCode == 0) {
            return;
          }
        }
        final dirPath = p.dirname(srcPath);
        final openDir = await Process.run('open', <String>[dirPath]);
        if (openDir.exitCode == 0) {
          return;
        }
        _setAuthError('Не удалось открыть папку с логом');
        return;
      }

      if (Platform.isWindows || Platform.isLinux) {
        final dirPath = p.dirname(srcPath);
        final ok = await launchUrl(
          Uri.directory(dirPath),
          mode: LaunchMode.externalApplication,
        );
        if (!ok) {
          _setAuthError('Не удалось открыть папку с логом');
        }
        return;
      }

      _setAuthError('Открытие папки с логом недоступно на этой платформе');
    } catch (error) {
      _setAuthError('Не удалось открыть папку с логом: $error');
    }
  }

  Future<void> exportLog() async {
    final srcPath = logFilePath;
    if (srcPath == null || srcPath.trim().isEmpty) {
      _setAuthError('Лог пока недоступен');
      return;
    }
    final src = File(srcPath);
    if (!await src.exists()) {
      _setAuthError('Файл лога не найден');
      return;
    }
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final suggestedName = 'cogniread_$timestamp.log';
    final destPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Экспорт лога',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: const <String>['log', 'txt'],
    );
    if (destPath == null || destPath.trim().isEmpty) {
      return;
    }
    try {
      await src.copy(destPath);
      _setInfo('Лог сохранён: $destPath');
    } catch (error) {
      _setAuthError('Не удалось сохранить лог: $error');
    }
  }

  Future<void> uploadDiagnosticsToCloud({
    bool includeSearchIndex = true,
    int maxLogBytes = 512 * 1024,
  }) async {
    final adapter = _syncAdapter;
    if (adapter == null || !isSyncProviderConnected) {
      _setAuthError('Синхронизация не подключена');
      return;
    }
    final deviceId = await _ensureDeviceId();
    final now = DateTime.now().toUtc();
    final timestamp = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');

    final archive = Archive();

    final logPath = logFilePath;
    if (logPath != null && logPath.trim().isNotEmpty) {
      try {
        final bytes = await _readTailBytes(File(logPath), maxBytes: maxLogBytes);
        if (bytes != null && bytes.isNotEmpty) {
          archive.addFile(ArchiveFile('cogniread.log', bytes.length, bytes));
        }
      } catch (error) {
        Log.d('Diagnostics upload: failed to read log: $error');
      }
    }

    File? snapshot;
    if (includeSearchIndex) {
      try {
        snapshot = await _searchIndex.exportSnapshot(
          fileName: 'search_index_snapshot_$timestamp.sqlite',
        );
        if (snapshot != null && await snapshot.exists()) {
          final bytes = await snapshot.readAsBytes();
          if (bytes.isNotEmpty) {
            archive.addFile(
              ArchiveFile('search_index.sqlite', bytes.length, bytes),
            );
          }
        }
      } catch (error) {
        Log.d('Diagnostics upload: failed to export search index: $error');
      } finally {
        if (snapshot != null) {
          try {
            await snapshot.delete();
          } catch (_) {}
        }
      }
    }

    if (archive.files.isEmpty) {
      _setAuthError('Нечего выгружать');
      return;
    }
    final bytes = ZipEncoder().encode(archive);
    if (bytes == null || bytes.isEmpty) {
      _setAuthError('Не удалось подготовить архив');
      return;
    }
    final remotePath = 'diagnostics/$deviceId/cogniread_diagnostics_$timestamp.zip';
    try {
      await adapter.putFile(
        remotePath,
        bytes,
        contentType: 'application/zip',
      );
      _setInfo('Диагностика выгружена: $remotePath');
    } catch (error) {
      _setAuthError('Не удалось выгрузить диагностику: $error');
    }
  }

  Future<void> syncNow() async {
    _autoSyncDisabled = false;
    _restartAutoSyncTimer();
    await _runFileSync(force: true);
  }

  Future<List<int>?> _readTailBytes(File file, {required int maxBytes}) async {
    if (maxBytes <= 0) {
      return null;
    }
    if (!await file.exists()) {
      return null;
    }
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final length = await raf.length();
      if (length <= 0) {
        return null;
      }
      final start = length > maxBytes ? length - maxBytes : 0;
      await raf.setPosition(start);
      final toRead = length - start;
      return await raf.read(toRead);
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
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
        Log.d(
          'Import book existingPath=$existingPath missing=$existingMissing',
        );
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
          unawaited(_searchIndex.indexBook(repaired.id));
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
      unawaited(_searchIndex.indexBook(entry.id));
      _books.add(LibraryBookItem.fromEntry(entry, isMissing: false));
      _books.sort(_sortByLastOpenedAt);
      notifyListeners();
      Log.d('Book copied to: ${stored.path}');
      _setInfo('Книга добавлена');
      _scheduleSync();
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
      await _logBookDeleteForSync(book);
      await _store.remove(book.id);
      unawaited(_searchIndex.deleteBook(book.id));
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
      _scheduleSync();
      return;
    } catch (e) {
      Log.d('Failed to delete book: $e');
      _setError('Не удалось удалить книгу');
    }
  }

  Future<void> _logBookDeleteForSync(LibraryBookItem book) async {
    try {
      await _syncEventLogStore.init();
      final now = DateTime.now().toUtc();
      await _syncEventLogStore.addEvent(
        EventLogEntry(
          id: 'evt-${now.microsecondsSinceEpoch}',
          entityType: 'book',
          entityId: book.hash,
          op: 'delete',
          payload: <String, Object?>{
            'bookId': book.id,
            'fingerprint': book.hash,
            'updatedAt': now.toIso8601String(),
          },
          createdAt: now,
        ),
      );
    } catch (error) {
      Log.d('Book deletion sync event write failed: $error');
    }
  }

  Future<void> clearLibrary() async {
    _books.clear();
    notifyListeners();
    try {
      await _storeReady;
      await _store.clear();
      unawaited(_searchIndex.resetIndexForTesting());
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
      _scheduleSync();
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
      allowedExtensions: _supportedExtensions
          .map((ext) => ext.replaceFirst('.', ''))
          .toList(),
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
        cover = _readFb2CoverFromZipBytes(await File(path).readAsBytes());
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
    if (provider == SyncProvider.webDav ||
        provider == SyncProvider.synologyDrive ||
        provider == SyncProvider.smb) {
      _setAuthError('Провайдер не требует OAuth ключей');
      return;
    }
    final trimmedClientId = clientId.trim();
    final trimmedClientSecret = clientSecret.trim();
    final trimmedRedirect = redirectUri.trim();
    final requiresSecret = provider != SyncProvider.dropbox;
    if (trimmedClientId.isEmpty ||
        trimmedRedirect.isEmpty ||
        (requiresSecret && trimmedClientSecret.isEmpty)) {
      _setAuthError(
        requiresSecret
            ? 'Заполни clientId, clientSecret и redirectUri'
            : 'Заполни clientId и redirectUri (clientSecret опционален)',
      );
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
      case SyncProvider.synologyDrive:
      case SyncProvider.smb:
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
      case SyncProvider.synologyDrive:
      case SyncProvider.smb:
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
    if (provider == SyncProvider.webDav ||
        provider == SyncProvider.synologyDrive ||
        provider == SyncProvider.smb) {
      _webDavCredentials = await _syncAuthStore.loadWebDavCredentials();
      if (_webDavCredentials == null) {
        final legacy = await _syncAuthStore.loadSynologyCredentials();
        if (legacy != null) {
          _webDavCredentials = legacy;
          await _syncAuthStore.saveWebDavCredentials(legacy);
          await _syncAuthStore.clearSynologyCredentials();
        }
      }
      final storedWebDav = _webDavCredentials;
      if (storedWebDav != null) {
        final parsed = Uri.tryParse(storedWebDav.baseUrl);
        if (parsed != null) {
          final normalizedBase = _normalizeWebDavBaseUri(parsed).toString();
          if (normalizedBase != storedWebDav.baseUrl) {
            final updated = WebDavCredentials(
              baseUrl: normalizedBase,
              username: storedWebDav.username,
              password: storedWebDav.password,
              allowInsecure: storedWebDav.allowInsecure,
              syncPath: storedWebDav.syncPath,
            );
            await _syncAuthStore.saveWebDavCredentials(updated);
            _webDavCredentials = updated;
          }
        }
      }
      _smbCredentials = await _syncAuthStore.loadSmbCredentials();
      _updateNasConnection();
      notifyListeners();
      return;
    }
    final token = await _syncAuthStore.loadToken(provider);
    _providerConnected[provider] = token != null;
    notifyListeners();
  }

  void _updateNasConnection() {
    final connected = _webDavCredentials != null || _smbCredentials != null;
    _providerConnected[SyncProvider.webDav] = connected;
    _providerConnected[SyncProvider.smb] = _smbCredentials != null;
  }

  Future<void> _refreshSyncAdapter() async {
    if (_providerConnected[_syncProvider] != true) {
      _syncAdapter = _fallbackSyncAdapter;
      await _initSyncEngine();
      _autoSyncDisabled = false;
      _restartAutoSyncTimer();
      notifyListeners();
      return;
    }
    final adapter = await _buildAdapter(_syncProvider);
    _syncAdapter = adapter == null
        ? _fallbackSyncAdapter
        : ResilientSyncAdapter(inner: adapter);
    await _initSyncEngine();
    _autoSyncDisabled = false;
    _restartAutoSyncTimer();
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
        return DropboxSyncAdapter(apiClient: apiClient, basePath: basePath);
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
      case SyncProvider.synologyDrive:
      case SyncProvider.smb:
        return _buildNasAdapter();
    }
  }

  Future<SyncAdapter?> _buildNasAdapter() async {
    final webDav = await _buildWebDavAdapter();
    final smb = _buildSmbAdapter();
    if (webDav == null && smb == null) {
      return null;
    }
    if (webDav != null && smb != null) {
      return FallbackSyncAdapter(primary: webDav, secondary: smb, label: 'NAS');
    }
    return webDav ?? smb;
  }

  Future<SyncAdapter?> _buildWebDavAdapter() async {
    final credentials = _webDavCredentials;
    if (credentials == null) {
      return null;
    }
    final resolved = await _resolveWebDavCredentials(credentials: credentials);
    final baseUri = Uri.tryParse(resolved.baseUrl);
    if (baseUri == null) {
      return null;
    }
    final apiClient = HttpWebDavApiClient(
      baseUri: baseUri,
      auth: WebDavAuth.basic(resolved.username, resolved.password),
      allowInsecure: resolved.allowInsecure,
    );
    return WebDavSyncAdapter(
      apiClient: apiClient,
      basePath: _webDavBasePath(resolved.syncPath),
    );
  }

  SyncAdapter? _buildSmbAdapter() {
    final credentials = _smbCredentials;
    if (credentials == null) {
      return null;
    }
    final syncPath = _webDavCredentials?.syncPath ?? 'cogniread';
    final normalized = _normalizeWebDavSyncPath(syncPath);
    final basePath = normalized.isEmpty ? '' : normalized;
    return SmbSyncAdapter(mountPath: credentials.mountPath, basePath: basePath);
  }

  Future<void> connectSyncProvider() async {
    if (_authInProgress) {
      return;
    }
    if (requiresManualOAuthCode) {
      _setAuthError('Открой подключение и введи код со страницы Яндекса.');
      return;
    }
    final authUrl = await beginOAuthConnection();
    if (authUrl == null) {
      return;
    }
    final loopback = _loopbackRedirect(_syncProvider);
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

  String _oauthNotConfiguredMessage(SyncProvider provider) {
    if (!_developerMode) {
      return 'Этот способ синхронизации недоступен в этой версии приложения.\n'
          'Выбери NAS (WebDAV/SMB) или установи обновление приложения.';
    }
    final loadedPath = SyncOAuthConfig.lastLoadedPath;
    final base = 'Этот провайдер синхронизации в этой сборке не настроен.';
    final configHint = loadedPath == null
        ? 'Файл sync_oauth.json не найден.'
        : 'Файл: $loadedPath';
    switch (provider) {
      case SyncProvider.yandexDisk:
        return '$base\n$configHint\n'
            'Нужен блок "yandexDisk": { "clientId": "...", "clientSecret": "...", "redirectUri": "cogniread://oauth" }';
      case SyncProvider.googleDrive:
        return '$base\n$configHint\n'
            'Нужен блок "googleDrive": { "clientId": "...", "clientSecret": "...", "redirectUri": "cogniread://oauth" }';
      case SyncProvider.dropbox:
        return '$base\n$configHint\n'
            'Нужен блок "dropbox": { "clientId": "...", "redirectUri": "cogniread://oauth", "clientSecret": "..." } (clientSecret опционален при PKCE)';
      case SyncProvider.oneDrive:
        return '$base\n$configHint\n'
            'Нужен блок "oneDrive": { "clientId": "...", "clientSecret": "...", "redirectUri": "cogniread://oauth", "tenant": "common" }';
      case SyncProvider.webDav:
      case SyncProvider.synologyDrive:
      case SyncProvider.smb:
        return 'Этот провайдер не использует OAuth. Заполни настройки подключения.';
    }
  }

  Future<void> disconnectSyncProvider() async {
    if (_syncProvider == SyncProvider.webDav) {
      await _clearWebDavCredentials(refresh: false, clearAuthError: false);
      await _clearSmbCredentials(refresh: false, clearAuthError: false);
      await _refreshSyncAdapter();
      notifyListeners();
      return;
    }
    await _syncAuthStore.clearToken(_syncProvider);
    await _loadProviderConnection(_syncProvider);
    await _refreshSyncAdapter();
  }

  Future<bool> saveNasCredentials({
    required String baseUrl,
    required String username,
    required String password,
    required bool allowInsecure,
    required String syncPath,
    required String smbMountPath,
  }) async {
    final trimmedBase = baseUrl.trim();
    final trimmedUser = username.trim();
    final trimmedSmb = smbMountPath.trim();
    final hasWebDav = trimmedBase.isNotEmpty || trimmedUser.isNotEmpty;
    final hasSmb = trimmedSmb.isNotEmpty;
    if (!hasWebDav && !hasSmb) {
      _setAuthError('Укажи WebDAV или SMB путь');
      return false;
    }
    var webDavSaved = true;
    if (hasWebDav) {
      if (trimmedBase.isEmpty || trimmedUser.isEmpty) {
        _setAuthError('Заполни URL и логин');
        return false;
      }
      webDavSaved = await saveWebDavCredentials(
        baseUrl: baseUrl,
        username: username,
        password: password,
        allowInsecure: allowInsecure,
        syncPath: syncPath,
      );
    } else {
      await _clearWebDavCredentials(refresh: false, clearAuthError: false);
    }
    if (hasSmb) {
      await saveSmbCredentials(
        mountPath: smbMountPath,
        clearAuthError: webDavSaved,
        refresh: false,
      );
    } else {
      await _clearSmbCredentials(refresh: false, clearAuthError: webDavSaved);
    }
    _updateNasConnection();
    await _refreshSyncAdapter();
    notifyListeners();
    if (!webDavSaved && hasWebDav) {
      return false;
    }
    return true;
  }

  Future<bool> saveWebDavCredentials({
    required String baseUrl,
    required String username,
    required String password,
    required bool allowInsecure,
    required String syncPath,
  }) async {
    final trimmedBase = baseUrl.trim();
    final trimmedUser = username.trim();
    if (trimmedBase.isEmpty || trimmedUser.isEmpty) {
      _setAuthError('Заполни URL и логин');
      return false;
    }
    final parsed = Uri.tryParse(trimmedBase);
    final scheme = parsed?.scheme.toLowerCase();
    if (parsed == null ||
        parsed.host.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      _setAuthError('URL должен начинаться с http:// или https://');
      return false;
    }
    try {
      final normalizedInput = _normalizeWebDavBaseUri(parsed);
      final endpoint = await _discoverWebDavEndpoint(
        label: 'WebDAV',
        baseUri: parsed,
        username: trimmedUser,
        password: password,
        allowInsecure: allowInsecure,
        syncPath: syncPath,
      );
      final normalizedEndpoint = _normalizeWebDavBaseUri(endpoint);
      final normalizedSyncPath = _normalizeWebDavSyncPath(syncPath);
      final creds = WebDavCredentials(
        baseUrl: normalizedEndpoint.toString(),
        username: trimmedUser,
        password: password,
        allowInsecure: allowInsecure,
        syncPath: normalizedSyncPath,
      );
      await _syncAuthStore.saveWebDavCredentials(creds);
      _webDavCredentials = creds;
      _updateNasConnection();
      _authError = null;
      await _refreshSyncAdapter();
      notifyListeners();
      if (normalizedInput.toString() != normalizedEndpoint.toString()) {
        _setInfo('WebDAV endpoint найден: $normalizedEndpoint');
      }
      return true;
    } catch (error) {
      _setAuthError(_formatBasicAuthError('WebDAV', error));
      return false;
    }
  }

  Future<void> saveSmbCredentials({
    required String mountPath,
    bool clearAuthError = true,
    bool refresh = true,
  }) async {
    final trimmedPath = mountPath.trim();
    if (trimmedPath.isEmpty) {
      _setAuthError('Укажи путь к шару');
      return;
    }
    final normalizedPath = p.normalize(trimmedPath);
    final creds = SmbCredentials(mountPath: normalizedPath);
    await _syncAuthStore.saveSmbCredentials(creds);
    _smbCredentials = creds;
    _updateNasConnection();
    if (clearAuthError) {
      _authError = null;
    }
    if (refresh) {
      await _refreshSyncAdapter();
      notifyListeners();
    }
  }

  Future<void> _clearWebDavCredentials({
    bool refresh = true,
    bool clearAuthError = true,
  }) async {
    await _syncAuthStore.clearWebDavCredentials();
    _webDavCredentials = null;
    if (clearAuthError) {
      _authError = null;
    }
    _updateNasConnection();
    if (refresh) {
      await _refreshSyncAdapter();
      notifyListeners();
    }
  }

  Future<void> _clearSmbCredentials({
    bool refresh = true,
    bool clearAuthError = true,
  }) async {
    await _syncAuthStore.clearSmbCredentials();
    _smbCredentials = null;
    if (clearAuthError) {
      _authError = null;
    }
    _updateNasConnection();
    if (refresh) {
      await _refreshSyncAdapter();
      notifyListeners();
    }
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
      final label = _providerLabel(_syncProvider);
      if (error is SyncAdapterException) {
        _setAuthError(_formatSyncAdapterError(label, error));
      } else {
        _setAuthError('$label проверка не удалась: $error');
      }
    } finally {
      _connectionInProgress = false;
      notifyListeners();
    }
  }

  Future<void> testWebDavCredentials({
    required String baseUrl,
    required String username,
    required String password,
    required bool allowInsecure,
    required String syncPath,
  }) async {
    await _testBasicAuthCredentials(
      label: 'WebDAV',
      baseUrl: baseUrl,
      username: username,
      password: password,
      allowInsecure: allowInsecure,
      syncPath: syncPath,
    );
  }

  Future<void> testSmbCredentials({required String mountPath}) async {
    if (_connectionInProgress) {
      return;
    }
    final trimmedPath = mountPath.trim();
    if (trimmedPath.isEmpty) {
      _setAuthError('Укажи путь к шару');
      return;
    }
    _connectionInProgress = true;
    _authError = null;
    notifyListeners();
    try {
      final dir = Directory(p.normalize(trimmedPath));
      if (!await dir.exists()) {
        _setAuthError('Путь не найден');
        return;
      }
      var count = 0;
      await for (final _ in dir.list(followLinks: false)) {
        count += 1;
        if (count >= 50) {
          break;
        }
      }
      _setInfo('SMB путь доступен (файлов: $count)');
    } catch (error) {
      _setAuthError('SMB проверка не удалась: $error');
    } finally {
      _connectionInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _testBasicAuthCredentials({
    required String label,
    required String baseUrl,
    required String username,
    required String password,
    required bool allowInsecure,
    required String syncPath,
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
      final endpoint = await _discoverWebDavEndpoint(
        label: label,
        baseUri: parsed,
        username: trimmedUser,
        password: password,
        allowInsecure: allowInsecure,
        requestTimeout: const Duration(seconds: 5),
        syncPath: syncPath,
      );
      final normalizedInput = _normalizeWebDavBaseUri(parsed);
      final normalizedEndpoint = _normalizeWebDavBaseUri(endpoint);
      if (normalizedInput.toString() != normalizedEndpoint.toString()) {
        _setInfo('$label endpoint найден: $normalizedEndpoint');
      } else {
        _setInfo('$label подключение успешно');
      }
    } catch (error) {
      _setAuthError(_formatBasicAuthError(label, error));
    } finally {
      _connectionInProgress = false;
      notifyListeners();
    }
  }

  String _formatBasicAuthError(String label, Object error) {
    if (error is SyncAdapterException) {
      return _formatSyncAdapterError(label, error);
    }
    return '$label проверка не удалась: $error';
  }

  String _formatSyncAdapterError(String label, SyncAdapterException error) {
    if (error.code == 'webdav_401' || error.code == 'webdav_403') {
      return '$label: неверный логин/пароль или нет доступа.';
    }
    if (error.code == 'webdav_405') {
      return '$label: метод WebDAV недоступен. Проверь, что WebDAV включён и корректны порт/путь (часто /webdav/ или /dav/, иногда порты 5005/5006).';
    }
    if (error.code == 'webdav_404') {
      return '$label: путь не найден. Проверь URL (часто /webdav/ или /dav/).';
    }
    if (error.code == 'smb_not_found') {
      return '$label: SMB путь не найден. Смонтируй сетевую папку и укажи корректный путь.';
    }
    if (error.code == 'webdav_endpoint_not_found') {
      return '$label: не удалось определить WebDAV URL автоматически. Укажи точный URL или выбери папку.';
    }
    if (error.code == 'webdav_invalid_xml') {
      return '$label: получен HTML вместо WebDAV. Проверь URL и права.';
    }
    if (error.code == 'webdav_timeout') {
      return '$label: таймаут соединения. Проверь доступность сервера.';
    }
    if (error.code == 'webdav_ssl') {
      return '$label: SSL ошибка. Проверь сертификат или включи "Принимать все сертификаты".';
    }
    if (error.code == 'webdav_socket') {
      return '$label: нет доступа к серверу. Проверь адрес, порт и сеть.';
    }
    if (error.code == 'webdav_http') {
      return '$label: ошибка HTTP. Проверь URL и доступ к WebDAV.';
    }
    if (error.code == 'yandex_401' || error.code == 'yandex_403') {
      return '$label: нет доступа. Переподключи аккаунт Yandex и попробуй ещё раз.';
    }
    if (error.code == 'yandex_timeout' ||
        error.code == 'yandex_socket' ||
        error.code == 'yandex_http') {
      return '$label: ошибка сети. Проверь интернет и попробуй ещё раз.';
    }
    if (error.code == 'dropbox_401' || error.code == 'dropbox_403') {
      return '$label: нет доступа. Переподключи Dropbox и попробуй ещё раз.';
    }
    if (error.code == 'dropbox_timeout' ||
        error.code == 'dropbox_socket' ||
        error.code == 'dropbox_http') {
      return '$label: ошибка сети. Проверь интернет и попробуй ещё раз.';
    }
    return '$label ошибка: $error';
  }

  Uri _normalizeWebDavBaseUri(Uri uri) {
    var normalized = uri;
    if (normalized.userInfo.isNotEmpty) {
      normalized = normalized.replace(userInfo: '');
    }
    if (normalized.hasQuery) {
      normalized = normalized.replace(query: '');
    }
    if (normalized.fragment.isNotEmpty) {
      normalized = normalized.replace(fragment: '');
    }
    if (normalized.path.isEmpty || normalized.path.endsWith('/')) {
      return normalized;
    }
    return normalized.replace(path: '${normalized.path}/');
  }

  String _normalizeWebDavSyncPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '';
    }
    var normalized = trimmed;
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _webDavBasePath(String syncPath) {
    if (syncPath.isEmpty) {
      return '';
    }
    final normalized = syncPath.startsWith('/') ? syncPath : '/$syncPath';
    return normalized.endsWith('/') ? normalized : '$normalized/';
  }

  List<Uri> _buildWebDavCandidateUris(Uri baseUri, String username) {
    final normalizedBase = _normalizeWebDavBaseUri(baseUri);
    final root = normalizedBase.replace(path: '/');
    final encodedUser = Uri.encodeComponent(username);
    final candidatePaths = <String>[
      'webdav/',
      'dav/',
      'remote.php/webdav/',
      'remote.php/dav/files/$encodedUser/',
      'dav/files/$encodedUser/',
      'webdav/$encodedUser/',
      '/',
    ];
    final candidates = <Uri>[];
    final seen = <String>{};
    void add(Uri uri) {
      final key = uri.toString();
      if (seen.add(key)) {
        candidates.add(uri);
      }
    }

    if (normalizedBase.path.isNotEmpty && normalizedBase.path != '/') {
      add(normalizedBase);
    }
    for (final path in candidatePaths) {
      final normalizedPath = path.startsWith('/') ? path : '/$path';
      final withSlash = normalizedPath.endsWith('/')
          ? normalizedPath
          : '$normalizedPath/';
      add(root.replace(path: withSlash));
    }
    if (normalizedBase.path.isEmpty || normalizedBase.path == '/') {
      add(normalizedBase);
    }
    return candidates;
  }

  List<Uri> _fallbackWebDavBaseUris(Uri baseUri) {
    final normalizedBase = _normalizeWebDavBaseUri(baseUri);
    if (normalizedBase.host.isEmpty) {
      return const <Uri>[];
    }
    final candidates = <Uri>[];
    final seen = <String>{normalizedBase.toString()};
    final isHttps = normalizedBase.scheme.toLowerCase() == 'https';
    final ports = isHttps
        ? <_WebDavPortCandidate>[
            const _WebDavPortCandidate('https', 443),
            const _WebDavPortCandidate('https', 5006),
            const _WebDavPortCandidate('https', 8443),
            const _WebDavPortCandidate('http', 80),
            const _WebDavPortCandidate('http', 5005),
            const _WebDavPortCandidate('http', 8080),
          ]
        : <_WebDavPortCandidate>[
            const _WebDavPortCandidate('http', 80),
            const _WebDavPortCandidate('http', 5005),
            const _WebDavPortCandidate('http', 8080),
            const _WebDavPortCandidate('https', 443),
            const _WebDavPortCandidate('https', 5006),
            const _WebDavPortCandidate('https', 8443),
          ];
    for (final candidate in ports) {
      final next = normalizedBase.replace(
        scheme: candidate.scheme,
        port: candidate.port,
      );
      final key = next.toString();
      if (seen.add(key)) {
        candidates.add(next);
      }
    }
    return candidates;
  }

  Future<Uri> _discoverWebDavEndpoint({
    required String label,
    required Uri baseUri,
    required String username,
    required String password,
    required bool allowInsecure,
    Duration requestTimeout = const Duration(seconds: 5),
    String syncPath = '',
  }) async {
    var sawTimeout = false;
    var sawInvalidXml = false;
    final normalizedSyncPath = _normalizeWebDavSyncPath(syncPath);
    final baseUris = <Uri>[baseUri, ..._fallbackWebDavBaseUris(baseUri)];
    for (var i = 0; i < baseUris.length; i += 1) {
      final base = baseUris[i];
      final timeout = i == 0 ? requestTimeout : const Duration(seconds: 3);
      for (final candidate in _buildWebDavCandidateUris(base, username)) {
        Log.d('$label discover: trying $candidate');
        final apiClient = HttpWebDavApiClient(
          baseUri: candidate,
          auth: WebDavAuth.basic(username, password),
          allowInsecure: allowInsecure,
          requestTimeout: timeout,
        );
        if (normalizedSyncPath.isNotEmpty) {
          final ok = await _probeWebDavPath(
            apiClient,
            '/$normalizedSyncPath/',
            label,
            candidate,
            allowNotFound: true,
            onTimeout: () => sawTimeout = true,
            onInvalidXml: () => sawInvalidXml = true,
          );
          if (ok) {
            Log.d('$label discover: endpoint найден $candidate');
            return candidate;
          }
        }
        final ok = await _probeWebDavPath(
          apiClient,
          '/',
          label,
          candidate,
          allowNotFound: false,
          onTimeout: () => sawTimeout = true,
          onInvalidXml: () => sawInvalidXml = true,
        );
        if (ok) {
          Log.d('$label discover: endpoint найден $candidate');
          return candidate;
        }
      }
    }
    if (sawTimeout) {
      throw SyncAdapterException('WebDAV timeout', code: 'webdav_timeout');
    }
    if (sawInvalidXml) {
      throw SyncAdapterException(
        '$label response is HTML. Check base URL and credentials.',
        code: 'webdav_invalid_xml',
      );
    }
    throw SyncAdapterException(
      '$label endpoint not found',
      code: 'webdav_endpoint_not_found',
    );
  }

  Future<List<String>> listWebDavFolders({
    required String label,
    required String baseUrl,
    required String username,
    required String password,
    required bool allowInsecure,
  }) async {
    final trimmedBase = baseUrl.trim();
    final trimmedUser = username.trim();
    if (trimmedBase.isEmpty || trimmedUser.isEmpty) {
      _setAuthError('Заполни URL и логин');
      return const <String>[];
    }
    final parsed = Uri.tryParse(trimmedBase);
    final scheme = parsed?.scheme.toLowerCase();
    if (parsed == null ||
        parsed.host.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      _setAuthError('URL должен начинаться с http:// или https://');
      return const <String>[];
    }
    try {
      final endpoint = await _discoverWebDavEndpoint(
        label: label,
        baseUri: parsed,
        username: trimmedUser,
        password: password,
        allowInsecure: allowInsecure,
        requestTimeout: const Duration(seconds: 5),
      );
      final apiClient = HttpWebDavApiClient(
        baseUri: endpoint,
        auth: WebDavAuth.basic(trimmedUser, password),
        allowInsecure: allowInsecure,
      );
      final entries = await apiClient.listFolder('/');
      final folders =
          entries
              .where((item) => item.isDirectory)
              .map((item) => item.name)
              .where((name) => name.isNotEmpty && name != '.' && name != '..')
              .toList()
            ..sort();
      if (folders.isEmpty) {
        _setInfo('$label: папки не найдены');
      }
      return folders;
    } catch (error) {
      _setAuthError(_formatBasicAuthError(label, error));
      return const <String>[];
    }
  }

  Future<bool> _probeWebDavPath(
    HttpWebDavApiClient apiClient,
    String path,
    String label,
    Uri candidate, {
    required bool allowNotFound,
    required void Function() onTimeout,
    required void Function() onInvalidXml,
  }) async {
    final folderPath = path == '/'
        ? '/'
        : (path.endsWith('/') ? path.substring(0, path.length - 1) : path);
    try {
      final response = await apiClient.propfindRaw(path);
      final statusCode = response.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        throw SyncAdapterException(
          'WebDAV error $statusCode',
          code: 'webdav_$statusCode',
        );
      }
      final ok = statusCode == 207 || statusCode == 200;
      if (ok) {
        if (_looksLikeHtmlResponse(response.bytes)) {
          onInvalidXml();
          return false;
        }
        return true;
      }
      if (allowNotFound &&
          folderPath != '/' &&
          (statusCode == 404 || statusCode == 405)) {
        try {
          Log.d(
            '$label discover: attempting MKCOL for $folderPath on $candidate',
          );
          final mkcol = await apiClient.mkcolRaw(folderPath);
          final mkcolOk = mkcol.statusCode < 400;
          Log.d(
            '$label discover: MKCOL ${mkcol.statusCode} for $candidate ($folderPath)',
          );
          if (mkcolOk) {
            Log.d('$label discover: MKCOL OK for $candidate ($folderPath)');
          }
          final next = await apiClient.propfindRaw(path);
          final nextOk = next.statusCode == 207 || next.statusCode == 200;
          if (nextOk && !_looksLikeHtmlResponse(next.bytes)) {
            Log.d('$label discover: created $folderPath on $candidate');
            return true;
          }
        } catch (_) {}
        if (statusCode == 404) {
          final optionsOk = await _probeWebDavOptions(
            apiClient,
            path,
            label,
            candidate,
          );
          if (optionsOk) {
            Log.d('$label discover: OPTIONS OK for $candidate');
            return true;
          }
        }
      }
      if (statusCode == 405) {
        Log.d('$label discover: PROPFIND not allowed for $candidate ($path)');
        return false;
      }
      if (statusCode == 404 || statusCode >= 400) {
        Log.d('$label discover: skip $candidate (webdav_$statusCode)');
        return false;
      }
      return false;
    } on SyncAdapterException catch (error) {
      if (error.code == 'webdav_401' || error.code == 'webdav_403') {
        rethrow;
      }
      if (error.code == 'webdav_timeout') {
        onTimeout();
        Log.d('$label discover: timeout for $candidate');
        return false;
      }
      if (error.code == 'webdav_invalid_xml') {
        onInvalidXml();
      }
      if (error.code == 'webdav_404' || error.code == 'webdav_invalid_xml') {
        final optionsOk = await _probeWebDavOptions(
          apiClient,
          path,
          label,
          candidate,
        );
        if (optionsOk) {
          Log.d('$label discover: OPTIONS OK for $candidate');
          return true;
        }
        Log.d('$label discover: skip $candidate (${error.code})');
        return false;
      }
      if (error.code != null) {
        Log.d('$label discover: skip $candidate (${error.code})');
        return false;
      }
      rethrow;
    } on TimeoutException {
      onTimeout();
      Log.d('$label discover: timeout for $candidate');
      return false;
    }
  }

  bool _looksLikeHtmlResponse(List<int> bytes) {
    if (bytes.isEmpty) {
      return false;
    }
    String raw;
    try {
      raw = utf8.decode(bytes);
    } catch (_) {
      return false;
    }
    final lower = raw.toLowerCase();
    return lower.contains('<html') ||
        lower.contains('<head') ||
        lower.contains('<body') ||
        lower.contains('<!doctype html');
  }

  Future<bool> _probeWebDavOptions(
    HttpWebDavApiClient apiClient,
    String path,
    String label,
    Uri candidate,
  ) async {
    try {
      final options = await apiClient.options(path);
      return options.allowsPropfind || options.hasDav;
    } on SyncAdapterException catch (error) {
      Log.d('$label discover: OPTIONS failed for $candidate (${error.code})');
      return false;
    }
  }

  Future<WebDavCredentials> _resolveWebDavCredentials({
    required WebDavCredentials credentials,
  }) async {
    final baseUri = Uri.tryParse(credentials.baseUrl);
    if (baseUri == null) {
      return credentials;
    }
    final normalizedBase = _normalizeWebDavBaseUri(baseUri);
    try {
      final probeClient = HttpWebDavApiClient(
        baseUri: normalizedBase,
        auth: WebDavAuth.basic(credentials.username, credentials.password),
        allowInsecure: credentials.allowInsecure,
        requestTimeout: const Duration(seconds: 5),
      );
      final initialSyncPath = _normalizeWebDavSyncPath(credentials.syncPath);
      final probePath = initialSyncPath.isEmpty ? '/' : '/$initialSyncPath/';
      final probeOk = await _probeWebDavPath(
        probeClient,
        probePath,
        'WebDAV',
        normalizedBase,
        allowNotFound: initialSyncPath.isNotEmpty,
        onTimeout: () {},
        onInvalidXml: () {},
      );
      if (probeOk) {
        return credentials;
      }
      final endpoint = await _discoverWebDavEndpoint(
        label: 'WebDAV',
        baseUri: normalizedBase,
        username: credentials.username,
        password: credentials.password,
        allowInsecure: credentials.allowInsecure,
        requestTimeout: const Duration(seconds: 5),
        syncPath: credentials.syncPath,
      );
      final normalizedEndpoint = _normalizeWebDavBaseUri(endpoint);
      var updated = credentials;
      if (normalizedEndpoint.toString() != normalizedBase.toString()) {
        updated = WebDavCredentials(
          baseUrl: normalizedEndpoint.toString(),
          username: credentials.username,
          password: credentials.password,
          allowInsecure: credentials.allowInsecure,
          syncPath: credentials.syncPath,
        );
        await _syncAuthStore.saveWebDavCredentials(updated);
        _webDavCredentials = updated;
        _setInfo('WebDAV endpoint найден: $normalizedEndpoint');
      }

      final verifiedClient = HttpWebDavApiClient(
        baseUri: normalizedEndpoint,
        auth: WebDavAuth.basic(updated.username, updated.password),
        allowInsecure: updated.allowInsecure,
        requestTimeout: const Duration(seconds: 5),
      );
      final verifiedSyncPath = _normalizeWebDavSyncPath(updated.syncPath);
      if (verifiedSyncPath.isEmpty) {
        return updated;
      }
      final verifiedOk = await _probeWebDavPath(
        verifiedClient,
        '/$verifiedSyncPath/',
        'WebDAV',
        normalizedEndpoint,
        allowNotFound: true,
        onTimeout: () {},
        onInvalidXml: () {},
      );
      if (verifiedOk) {
        return updated;
      }

      final canAutoPrefix = !verifiedSyncPath.contains('/');
      if (!canAutoPrefix) {
        return updated;
      }

      List<WebDavItem> rootEntries;
      try {
        rootEntries = await verifiedClient.listFolder('/');
      } catch (_) {
        return updated;
      }
      final rootFolders = rootEntries
          .where((item) => item.isDirectory && item.name.isNotEmpty)
          .map((item) => item.name)
          .toSet();
      if (rootFolders.isNotEmpty) {
        final sorted = rootFolders.toList()..sort();
        Log.d('WebDAV root folders: ${sorted.join(', ')}');
      }
      final username = updated.username.trim();

      final byLower = <String, String>{
        for (final name in rootFolders) name.toLowerCase(): name,
      };
      final homeName = byLower['home'];
      final homesName = byLower['homes'];
      final publicName = byLower['public'];

      String? homesUserDir;
      if (homesName != null && username.isNotEmpty) {
        try {
          final entries = await verifiedClient.listFolder('/$homesName/');
          final dirNames = entries
              .where((item) => item.isDirectory && item.name.isNotEmpty)
              .map((item) => item.name)
              .toList();
          final target = username.toLowerCase();
          homesUserDir = dirNames.firstWhere(
            (name) => name.toLowerCase() == target,
            orElse: () => username,
          );
        } catch (_) {
          homesUserDir = username;
        }
      }

      final candidates = <String>[];
      void addCandidate(String? value) {
        if (value == null || value.trim().isEmpty) {
          return;
        }
        if (!candidates.contains(value)) {
          candidates.add(value);
        }
      }

      addCandidate(homeName);
      addCandidate(
        homesName != null && homesUserDir != null
            ? '$homesName/$homesUserDir'
            : null,
      );
      addCandidate(publicName);
      addCandidate(
        username.isNotEmpty && byLower.containsKey(username.toLowerCase())
            ? byLower[username.toLowerCase()]
            : null,
      );
      if (rootFolders.length == 1) {
        addCandidate(rootFolders.first);
      }
      if (rootFolders.isNotEmpty) {
        final sorted = rootFolders.toList()..sort();
        for (final folder in sorted) {
          addCandidate(folder);
        }
      }

      for (final prefix in candidates) {
        final candidateSyncPath = '$prefix/$verifiedSyncPath';
        Log.d('WebDAV auto-path: trying /$candidateSyncPath/');
        final ok = await _probeWebDavPath(
          verifiedClient,
          '/$candidateSyncPath/',
          'WebDAV',
          normalizedEndpoint,
          allowNotFound: true,
          onTimeout: () {},
          onInvalidXml: () {},
        );
        if (!ok) {
          continue;
        }
        updated = WebDavCredentials(
          baseUrl: updated.baseUrl,
          username: updated.username,
          password: updated.password,
          allowInsecure: updated.allowInsecure,
          syncPath: candidateSyncPath,
        );
        await _syncAuthStore.saveWebDavCredentials(updated);
        _webDavCredentials = updated;
        _setInfo('WebDAV путь синхронизации: /$candidateSyncPath/');
        return updated;
      }

      return updated;
    } catch (error) {
      Log.d('WebDAV auto-discovery failed: $error');
      return credentials;
    }
  }

  void _disableAutoSync(SyncAdapterException error) {
    if (_autoSyncDisabled) {
      return;
    }
    _autoSyncDisabled = true;
    _pendingSync = false;
    _scheduledSyncTimer?.cancel();
    _autoSyncTimer?.cancel();
    final label = _providerLabel(_syncProvider);
    _setAuthError(
      'Автосинхронизация отключена. ${_formatSyncAdapterError(label, error)}',
    );
  }

  bool _isClientErrorCode(String? code) {
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
      final failures = <String, Object>{};
      for (final name in _syncFileNames) {
        try {
          await adapter.deleteFile(_buildSyncPath(name));
        } catch (error) {
          if (_isNotFoundSyncError(error)) {
            continue;
          }
          failures[name] = error;
        }
      }
      for (final folder in _syncFolderNames) {
        try {
          await adapter.deleteFile(_buildSyncPath(folder));
        } catch (error) {
          if (_isNotFoundSyncError(error)) {
            continue;
          }
          failures[folder] = error;
        }
      }

      // Google Drive adapter stores everything flat; best-effort cleanup of
      // book files that use `books/...` names.
      if (_syncProvider == SyncProvider.googleDrive) {
        try {
          final refs = await adapter.listFiles();
          for (final ref in refs) {
            if (!ref.path.startsWith('books/')) {
              continue;
            }
            try {
              await adapter.deleteFile(ref.path);
            } catch (error) {
              if (_isNotFoundSyncError(error)) {
                continue;
              }
              failures[ref.path] = error;
            }
          }
        } catch (error) {
          failures['books/*'] = error;
        }
      }

      if (failures.isEmpty) {
        _setInfo('Данные синхронизации удалены в облаке');
        return;
      }
      final label = _providerLabel(_syncProvider);
      final first = failures.entries.first;
      final error = first.value;
      if (error is SyncAdapterException) {
        _setAuthError(
          'Удаление завершено с ошибками: ${first.key}. ${_formatSyncAdapterError(label, error)}',
        );
      } else {
        _setAuthError('Удаление завершено с ошибками: ${first.key}. $error');
      }
    } catch (error) {
      final label = _providerLabel(_syncProvider);
      if (error is SyncAdapterException) {
        _setAuthError(
          'Не удалось удалить файлы синка. ${_formatSyncAdapterError(label, error)}',
        );
      } else {
        _setAuthError('Не удалось удалить файлы синка: $error');
      }
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
    'books_index.json',
  ];

  static const List<String> _syncFolderNames = <String>['books'];

  bool _isNotFoundSyncError(Object error) {
    if (error is! SyncAdapterException) {
      return false;
    }
    final code = error.code ?? '';
    if (code.contains('404')) {
      return true;
    }
    if (code.contains('not_found')) {
      return true;
    }
    final message = error.message;
    return message.contains('not_found') || message.contains('NotFound');
  }

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
        final pkce = DropboxOAuthClient.createPkce();
        _dropboxPkceVerifier = pkce.verifier;
        url = DropboxOAuthClient(
          dropbox,
        ).authorizationUrl(state: state, codeChallenge: pkce.challenge);
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
        final redirect = yandex.redirectUri.trim();
        final usesVerificationCode = redirect.contains(
          'oauth.yandex.ru/verification_code',
        );
        Log.d(
          'Yandex OAuth: redirect=$redirect, verification_code=$usesVerificationCode',
        );
        final responseType = usesVerificationCode
            ? 'code'
            : ((yandex.clientSecret == null ||
                      yandex.clientSecret!.trim().isEmpty)
                  ? 'token'
                  : 'code');
        String? codeChallenge;
        if (responseType == 'code') {
          final pkce = YandexDiskOAuthClient.createPkce();
          _yandexPkceVerifier = pkce.verifier;
          codeChallenge = pkce.challenge;
        } else {
          _yandexPkceVerifier = null;
        }
        url = YandexDiskOAuthClient(yandex).authorizationUrl(
          state: state,
          responseType: responseType,
          codeChallenge: codeChallenge,
        );
        break;
      case SyncProvider.webDav:
      case SyncProvider.synologyDrive:
      case SyncProvider.smb:
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
    Log.d('Handle auth redirect: ${_safeAuthUriForLogs(uri)}');
    final provider = _pendingAuthProvider;
    final expectedState = _authState;
    if (provider == null || expectedState == null) {
      return;
    }
    final query = uri.queryParameters;
    final fragment = _parseFragment(uri.fragment);
    final state = (query['state']?.isNotEmpty ?? false)
        ? query['state']!
        : fragment['state'];
    if (state != expectedState) {
      return;
    }
    final error = (query['error']?.isNotEmpty ?? false)
        ? query['error']
        : fragment['error'];
    if (error != null && error.isNotEmpty) {
      _finishAuthWithError('Подключение не удалось');
      return;
    }
    final code = query['code'];
    try {
      final token = await _exchangeAuth(provider, code, fragment);
      await _syncAuthStore.saveToken(provider, token);
      await _loadProviderConnection(provider);
      await _refreshSyncAdapter();
      _setInfo('${_providerLabel(provider)} подключен');
      _authError = null;
    } catch (error) {
      if (_developerMode) {
        _finishAuthWithError('OAuth ошибка: $error');
      } else {
        _finishAuthWithError('Подключение не удалось. Попробуй ещё раз.');
      }
      return;
    } finally {
      _authInProgress = false;
      _pendingAuthProvider = null;
      _authState = null;
      _yandexPkceVerifier = null;
      _dropboxPkceVerifier = null;
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
        return DropboxOAuthClient(
          dropbox,
        ).exchangeCode(code, codeVerifier: _dropboxPkceVerifier);
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
        return YandexDiskOAuthClient(
          yandex,
        ).exchangeCode(code, codeVerifier: _yandexPkceVerifier);
      case SyncProvider.webDav:
      case SyncProvider.synologyDrive:
      case SyncProvider.smb:
        throw SyncAuthException('OAuth provider not supported');
    }
  }

  Future<OAuthToken> _exchangeAuth(
    SyncProvider provider,
    String? code,
    Map<String, String> fragment,
  ) async {
    if (provider != SyncProvider.yandexDisk) {
      if (code == null || code.isEmpty) {
        throw SyncAuthException('OAuth code отсутствует');
      }
      return _exchangeAuthCode(provider, code);
    }

    if (code != null && code.isNotEmpty) {
      return _exchangeAuthCode(provider, code);
    }

    final accessToken = fragment['access_token'];
    if (accessToken == null || accessToken.isEmpty) {
      throw SyncAuthException('OAuth token отсутствует');
    }
    final expiresInRaw = fragment['expires_in'];
    final expiresIn = expiresInRaw == null ? null : int.tryParse(expiresInRaw);
    final expiresAt = expiresIn == null
        ? null
        : DateTime.now().toUtc().add(Duration(seconds: expiresIn));
    final tokenTypeRaw = fragment['token_type'] ?? 'OAuth';
    final tokenType = tokenTypeRaw.trim().toUpperCase() == 'BEARER'
        ? 'OAuth'
        : tokenTypeRaw;
    return OAuthToken(
      accessToken: accessToken,
      refreshToken: null,
      expiresAt: expiresAt,
      tokenType: tokenType,
    );
  }

  Map<String, String> _parseFragment(String fragment) {
    if (fragment.isEmpty) {
      return const <String, String>{};
    }
    final map = <String, String>{};
    for (final part in fragment.split('&')) {
      if (part.isEmpty) {
        continue;
      }
      final index = part.indexOf('=');
      if (index == -1) {
        map[Uri.decodeComponent(part)] = '';
        continue;
      }
      final key = Uri.decodeComponent(part.substring(0, index));
      final value = Uri.decodeComponent(part.substring(index + 1));
      map[key] = value;
    }
    return map;
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
    if (provider != SyncProvider.dropbox &&
        provider != SyncProvider.yandexDisk) {
      return null;
    }
    final raw = provider == SyncProvider.dropbox
        ? _oauthConfig?.dropbox?.redirectUri
        : _oauthConfig?.yandexDisk?.redirectUri;
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
      _finishAuthWithError(
        'Подключение недоступно. Проверь настройки подключения.',
      );
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
      Log.d('Loopback auth request: ${_safeAuthUriForLogs(request.uri)}');
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

  static String _safeAuthUriForLogs(Uri uri) {
    final base = '${uri.scheme}://${uri.authority}${uri.path}';
    final hasQuery = uri.queryParameters.isNotEmpty;
    final hasFragment = uri.fragment.isNotEmpty;
    if (!hasQuery && !hasFragment) {
      return base;
    }
    final params = uri.queryParameters.keys.toList()..sort();
    final suffix = [
      if (hasQuery) 'query=${params.join(',')}',
      if (hasFragment) 'fragment=present',
    ].join(' ');
    return '$base ($suffix)';
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
        return 'NAS (WebDAV/SMB)';
      case SyncProvider.synologyDrive:
      case SyncProvider.smb:
        return 'NAS (WebDAV/SMB)';
    }
  }

  Future<void> _initSyncEngine() async {
    final adapter = _syncAdapter;
    if (adapter == null) {
      _syncEngine = null;
      return;
    }
    await _storeReady;
    await _freeNotesStore.init();
    await _syncEventLogStore.init();
    final deviceId = await _ensureDeviceId();
    _syncEngine = FileSyncEngine(
      adapter: adapter,
      libraryStore: _store,
      freeNotesStore: _freeNotesStore,
      eventLogStore: _syncEventLogStore,
      deviceId: deviceId,
      storageService: _storageService,
    );
  }

  Future<void> _runFileSync({bool force = false}) async {
    final engine = _syncEngine;
    if (engine == null || _syncInProgress) {
      return;
    }
    if (_autoSyncDisabled && !force) {
      return;
    }
    _syncInProgress = true;
    _pendingSync = false;
    notifyListeners();
    try {
      final result = await engine.sync();
      _lastSyncAt = result.uploadedAt;
      final error = result.error;
      if (error != null) {
        _lastSyncOk = false;
        _lastSyncSummary = _formatSyncAdapterError(
          _providerLabel(_syncProvider),
          error,
        );
        await _preferencesStore.saveSyncStatus(
          SyncStatusSnapshot(
            at: _lastSyncAt!,
            ok: false,
            summary: _lastSyncSummary!,
          ),
        );
        _handleSyncError(error);
        Log.d('File sync failed: $error');
        return;
      }
      _lastSyncOk = true;
      _lastSyncSummary =
          'Успех: events=${result.appliedEvents}, state=${result.appliedState}, '
          'books↑=${result.booksUploaded}, books↓=${result.booksDownloaded}';
      await _preferencesStore.saveSyncStatus(
        SyncStatusSnapshot(
          at: _lastSyncAt!,
          ok: true,
          summary: _lastSyncSummary!,
        ),
      );
      if (result.appliedEvents > 0 ||
          result.appliedState > 0 ||
          result.booksUploaded > 0 ||
          result.booksDownloaded > 0) {
        await _loadLibrary();
        unawaited(_searchIndex.reconcileWithLibrary());
      } else {
        notifyListeners();
      }
    } catch (e) {
      final now = DateTime.now().toUtc();
      _lastSyncAt = now;
      _lastSyncOk = false;
      _lastSyncSummary = 'Синхронизация не удалась: $e';
      await _preferencesStore.saveSyncStatus(
        SyncStatusSnapshot(at: now, ok: false, summary: _lastSyncSummary!),
      );
      _handleSyncError(e);
      Log.d('File sync failed: $e');
    } finally {
      _syncInProgress = false;
      notifyListeners();
      if (_pendingSync) {
        _pendingSync = false;
        _scheduleSync(delay: const Duration(seconds: 1));
      }
    }
  }

  void _handleSyncError(Object error) {
    if (error is SyncAdapterException) {
      if (_isClientErrorCode(error.code)) {
        _disableAutoSync(error);
      } else {
        _setAuthError(
          _formatSyncAdapterError(_providerLabel(_syncProvider), error),
        );
      }
      return;
    }
    if (error is HandshakeException) {
      _setAuthError(
        'SSL ошибка. Проверь сертификат или включи "Принимать все сертификаты".',
      );
      return;
    }
    if (error is SocketException) {
      _setAuthError('Нет доступа к серверу. Проверь адрес, порт и сеть.');
      return;
    }
    if (error is HttpException) {
      _setAuthError('Ошибка HTTP. Проверь URL и доступ к WebDAV.');
      return;
    }
    _setAuthError('Синхронизация не удалась: $error');
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
    final normalized =
        stored == SyncProvider.synologyDrive.name ||
            stored == SyncProvider.smb.name
        ? SyncProvider.webDav.name
        : stored;
    _syncProvider = SyncProvider.values.firstWhere(
      (value) => value.name == normalized,
      orElse: _defaultSyncProvider,
    );
    if (normalized != stored) {
      await _preferencesStore.saveSyncProvider(_syncProvider.name);
    }
    if (!_developerMode && !_isProviderUsable(_syncProvider)) {
      _syncProvider = SyncProvider.webDav;
      await _preferencesStore.saveSyncProvider(_syncProvider.name);
    }
    notifyListeners();
  }

  SyncProvider _defaultSyncProvider() {
    if (_developerMode) {
      return SyncProvider.googleDrive;
    }
    final config = _oauthConfig;
    if (config == null) {
      return SyncProvider.webDav;
    }
    if (config.googleDrive != null) {
      return SyncProvider.googleDrive;
    }
    if (config.dropbox != null) {
      return SyncProvider.dropbox;
    }
    if (config.oneDrive != null) {
      return SyncProvider.oneDrive;
    }
    if (config.yandexDisk != null) {
      return SyncProvider.yandexDisk;
    }
    return SyncProvider.webDav;
  }

  bool _isProviderUsable(SyncProvider provider) {
    if (provider == SyncProvider.webDav ||
        provider == SyncProvider.synologyDrive ||
        provider == SyncProvider.smb) {
      return true;
    }
    final config = _oauthConfig;
    return config?.isConfigured(provider) ?? false;
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
    _autoSyncTimer?.cancel();
    _scheduledSyncTimer?.cancel();
    _searchIndex.close();
    super.dispose();
  }

  void _restartAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    if (_syncAdapter == null || _autoSyncDisabled) {
      return;
    }
    _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) => _scheduleSync());
  }

  void _scheduleSync({Duration delay = _syncDebounce}) {
    if (_syncAdapter == null || _autoSyncDisabled) {
      return;
    }
    _pendingSync = true;
    if (_syncInProgress) {
      return;
    }
    _scheduledSyncTimer?.cancel();
    _scheduledSyncTimer = Timer(delay, () async {
      _scheduledSyncTimer = null;
      try {
        await _runFileSync();
      } catch (error) {
        Log.d('Scheduled sync failed: $error');
        _handleSyncError(error);
      }
    });
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
BookMetadata readFb2MetadataForTest(List<int> bytes, String fallbackTitle) =>
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
}) async {
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
        extension:
            _extensionFromMediaType(mediaType) ??
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
  final rawTitle = _firstNonEmpty([
    title,
    ...?schema?.Package?.Metadata?.Titles,
    ...?schema?.Navigation?.DocTitle?.Titles,
  ]);
  final rawAuthor = _firstNonEmpty([
    author,
    ...?authorList,
    ...?schema?.Package?.Metadata?.Creators?.map((creator) => creator.Creator),
    ...?schema?.Navigation?.DocAuthors?.expand(
      (author) => author.Authors ?? const <String>[],
    ),
  ]);
  final resolvedTitle = (rawTitle == null || rawTitle.isEmpty)
      ? fallbackTitle
      : rawTitle;
  final resolvedAuthor = (rawAuthor == null || rawAuthor.isEmpty)
      ? null
      : rawAuthor;
  return BookMetadata(title: resolvedTitle, author: resolvedAuthor);
}

BookMetadata _readFb2MetadataFromBytes(List<int> bytes, String fallbackTitle) {
  try {
    final xml = _decodeFb2Xml(bytes);
    return _extractFb2Metadata(xml, fallbackTitle);
  } catch (e) {
    Log.d('Failed to parse FB2 metadata: $e');
    return BookMetadata(title: fallbackTitle, author: null);
  }
}

BookMetadata _readFb2MetadataFromZip(List<int> bytes, String fallbackTitle) {
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
  final match = RegExp('encoding=["\\\']([^"\\\']+)["\\\']').firstMatch(header);
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
  final titleInfo = doc
      .findAllElements('title-info')
      .firstWhere((_) => true, orElse: () => XmlElement(XmlName('title-info')));
  final scope = titleInfo.name.local == 'title-info' ? titleInfo : doc;
  final title =
      _firstNonEmpty(
        scope.findAllElements('book-title').map((element) => element.innerText),
      ) ??
      fallbackTitle;
  final author = _extractFb2Author(scope);
  return BookMetadata(title: title, author: author);
}

String? _extractFb2Author(XmlNode node) {
  final author = node
      .findAllElements('author')
      .firstWhere((_) => true, orElse: () => XmlElement(XmlName('author')));
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
  final image = doc
      .findAllElements('coverpage')
      .expand((node) {
        return node.findAllElements('image');
      })
      .firstWhere((_) => true, orElse: () => XmlElement(XmlName('image')));
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
  final binary = doc
      .findAllElements('binary')
      .firstWhere(
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
