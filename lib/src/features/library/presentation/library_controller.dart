import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/core/services/storage_service_impl.dart';
import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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
    Future<String?> Function()? pickEpubPath,
    bool stubImport = false,
  })  : _storageService = storageService ?? AppStorageService(),
        _store = store ?? LibraryStore(),
        _pickEpubPath = pickEpubPath,
        _stubImport = stubImport;

  final StorageService _storageService;
  final LibraryStore _store;
  final Future<String?> Function()? _pickEpubPath;
  final bool _stubImport;
  Future<void>? _storeReady;
  bool _coverSyncInProgress = false;

  bool _loading = true;
  String? _errorMessage;
  String? _infoMessage;
  String _query = '';
  final List<LibraryBookItem> _books = <LibraryBookItem>[];
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
    _storeReady = _stubImport ? Future<void>.value() : _store.init();
    await _loadLibrary();
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
    Log.d('Import EPUB pressed.');
    if (_stubImport) {
      _addStubBook();
      _setInfo('Книга добавлена');
      return;
    }
    final path = _pickEpubPath == null
        ? await _pickEpubFromFilePicker()
        : await _pickEpubPath();
    if (path == null) {
      _setInfo('Импорт отменён');
      return;
    }

    final validationError = await _validateEpubPath(path);
    if (validationError != null) {
      _setError(validationError);
      return;
    }

    try {
      await _storeReady;
      final stored = await _storageService.copyToAppStorageWithHash(path);
      final fallbackTitle = p.basenameWithoutExtension(path);
      final exists = await _store.existsByFingerprint(stored.hash);
      Log.d('Import EPUB fingerprint=${stored.hash} exists=$exists');
      if (exists) {
        final existing = await _store.getById(stored.hash);
        final existingPath = existing?.localPath;
        final existingMissing = existingPath == null
            ? true
            : !(await File(existingPath).exists());
        Log.d(
          'Import EPUB existingPath=$existingPath missing=$existingMissing',
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
      Log.d('EPUB copied to: ${stored.path}');
      _setInfo('Книга добавлена');
      return;
    } catch (e) {
      Log.d('EPUB import failed: $e');
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
          if (entry is File && entry.path.toLowerCase().endsWith('.epub')) {
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

  Future<String?> _pickEpubFromFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    return result.files.single.path;
  }

  Future<String?> _validateEpubPath(String path) async {
    final lowerPath = path.toLowerCase();
    if (!lowerPath.endsWith('.epub')) {
      return 'Неверное расширение файла (нужен .epub)';
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
      final bytes = await File(path).readAsBytes();
      final bookRef = await EpubReader.openBook(bytes);
      final cover = await _readCoverBytes(bookRef);
      if (cover == null || cover.bytes.isEmpty) {
        return null;
      }
      final dirPath = await _storageService.appStoragePath();
      final coversDir = Directory(p.join(dirPath, 'covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }
      final extension = cover.extension ?? '.img';
      final coverPath = p.join(coversDir.path, '$bookId$extension');
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
    final bytes = await File(path).readAsBytes();
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
