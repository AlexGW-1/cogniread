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
import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
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
    bool stubImport = false,
  })  : _storageService = storageService ?? AppStorageService(),
        _store = store ?? LibraryStore(),
        _preferencesStore = preferencesStore ?? LibraryPreferencesStore(),
        _pickEpubPath = pickEpubPath,
        _stubImport = stubImport;

  final StorageService _storageService;
  final LibraryStore _store;
  final LibraryPreferencesStore _preferencesStore;
  final Future<String?> Function()? _pickEpubPath;
  final bool _stubImport;
  Future<void>? _storeReady;
  bool _coverSyncInProgress = false;

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
  String _globalSearchQuery = '';
  bool _globalSearching = false;
  List<LibrarySearchResult> _globalSearchResults =
      const <LibrarySearchResult>[];
  Timer? _globalSearchDebounce;
  int _globalSearchNonce = 0;

  bool get loading => _loading;
  List<LibraryBookItem> get books => List<LibraryBookItem>.unmodifiable(_books);
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;
  String get query => _query;
  LibraryViewMode get viewMode => _viewMode;
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
    await _loadViewMode();
    await _loadLibrary();
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

    return null;
  }

  Future<String?> _readCoverPath(String path, String bookId) async {
    try {
      final extension = p.extension(path).toLowerCase();
      _CoverPayload? cover;
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
    super.dispose();
  }
}

class _CoverPayload {
  const _CoverPayload({required this.bytes, required this.extension});

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

Future<_CoverPayload?> _readCoverBytes(EpubBookRef bookRef) async {
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
      _CoverPayload? bestPayload;
      for (final entry in images.entries) {
        try {
          final bytes = await entry.value.readContentAsBytes();
          if (bytes.isNotEmpty &&
              (bestPayload == null ||
                  bytes.length > bestPayload.bytes.length)) {
            bestPayload = _CoverPayload(
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

Future<_CoverPayload?> _readImageBytesFromHref(
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
      return _CoverPayload(
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
        return _CoverPayload(
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

int _sortByLastOpenedAt(LibraryBookItem a, LibraryBookItem b) {
  final aTime = a.lastOpenedAt ?? a.addedAt;
  final bTime = b.lastOpenedAt ?? b.addedAt;
  final cmp = bTime.compareTo(aTime);
  if (cmp != 0) {
    return cmp;
  }
  return a.title.compareTo(b.title);
}

class _BookMetadata {
  const _BookMetadata({required this.title, required this.author});

  final String title;
  final String? author;
}

Future<_BookMetadata> _readMetadata(String path, String fallbackTitle) async {
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
        return _BookMetadata(title: fallbackTitle, author: null);
      }
    }
    if (extension == '.fb2') {
      return _readFb2MetadataFromBytes(bytes, fallbackTitle);
    }
    if (extension == '.zip') {
      return _readFb2MetadataFromZip(bytes, fallbackTitle);
    }
    return _BookMetadata(title: fallbackTitle, author: null);
  } catch (e) {
    Log.d('Failed to read EPUB bytes: $e');
    return _BookMetadata(title: fallbackTitle, author: null);
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

_BookMetadata _extractMetadata({
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
  return _BookMetadata(title: resolvedTitle, author: resolvedAuthor);
}

_BookMetadata _readFb2MetadataFromBytes(
  List<int> bytes,
  String fallbackTitle,
) {
  try {
    final xml = _decodeFb2Xml(bytes);
    return _extractFb2Metadata(xml, fallbackTitle);
  } catch (e) {
    Log.d('Failed to parse FB2 metadata: $e');
    return _BookMetadata(title: fallbackTitle, author: null);
  }
}

_BookMetadata _readFb2MetadataFromZip(
  List<int> bytes,
  String fallbackTitle,
) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final xml = _extractFb2XmlFromArchive(archive);
    if (xml == null) {
      return _BookMetadata(title: fallbackTitle, author: null);
    }
    return _extractFb2Metadata(xml, fallbackTitle);
  } catch (e) {
    Log.d('Failed to parse FB2.zip metadata: $e');
    return _BookMetadata(title: fallbackTitle, author: null);
  }
}

_CoverPayload? _readFb2CoverFromBytes(List<int> bytes) {
  try {
    final xml = _decodeFb2Xml(bytes);
    return _extractFb2Cover(xml);
  } catch (e) {
    Log.d('Failed to parse FB2 cover: $e');
    return null;
  }
}

_CoverPayload? _readFb2CoverFromZipBytes(List<int> bytes) {
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

_BookMetadata _extractFb2Metadata(String xml, String fallbackTitle) {
  final doc = XmlDocument.parse(xml);
  final title = _firstNonEmpty(
        doc.findAllElements('book-title').map((element) => element.innerText),
      ) ??
      fallbackTitle;
  final author = _extractFb2Author(doc);
  return _BookMetadata(title: title, author: author);
}

String? _extractFb2Author(XmlDocument doc) {
  final author = doc.findAllElements('author').firstWhere(
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

_CoverPayload? _extractFb2Cover(String xml) {
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
  return _CoverPayload(bytes: bytes, extension: extension);
}
