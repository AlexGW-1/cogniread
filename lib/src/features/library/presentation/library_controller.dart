import 'dart:io';

import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/core/services/storage_service_impl.dart';
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
    required this.hash,
    required this.addedAt,
    required this.lastOpenedAt,
    required this.isMissing,
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
      hash: entry.fingerprint,
      addedAt: entry.addedAt,
      lastOpenedAt: entry.lastOpenedAt,
      isMissing: isMissing,
    );
  }

  final String id;
  final String title;
  final String? author;
  final String sourcePath;
  final String storedPath;
  final String hash;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
  final bool isMissing;
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

  bool _loading = true;
  final List<LibraryBookItem> _books = <LibraryBookItem>[];

  bool get loading => _loading;
  List<LibraryBookItem> get books => List<LibraryBookItem>.unmodifiable(_books);

  Future<void> init() async {
    _storeReady = _stubImport ? Future<void>.value() : _store.init();
    await _loadLibrary();
  }

  Future<String?> importEpub() async {
    Log.d('Import EPUB pressed.');
    if (_stubImport) {
      _addStubBook();
      return null;
    }
    final path = _pickEpubPath == null
        ? await _pickEpubFromFilePicker()
        : await _pickEpubPath();
    if (path == null) {
      return 'Импорт отменён';
    }

    final validationError = await _validateEpubPath(path);
    if (validationError != null) {
      return validationError;
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
            addedAt: existing.addedAt,
            fingerprint: existing.fingerprint,
            sourcePath: File(path).absolute.path,
            readingPosition: existing.readingPosition,
            progress: existing.progress,
            lastOpenedAt: existing.lastOpenedAt,
            notes: existing.notes,
            highlights: existing.highlights,
            bookmarks: existing.bookmarks,
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
          return null;
        }
        return 'Эта книга уже в библиотеке';
      }
      final metadata = await _readMetadata(stored.path, fallbackTitle);
      final entry = LibraryEntry(
        id: stored.hash,
        title: metadata.title,
        author: metadata.author,
        localPath: stored.path,
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
      );
      await _store.upsert(entry);
      _books.add(LibraryBookItem.fromEntry(entry, isMissing: false));
      _books.sort(_sortByLastOpenedAt);
      notifyListeners();
      Log.d('EPUB copied to: ${stored.path}');
      return null;
    } catch (e) {
      Log.d('EPUB import failed: $e');
      return 'Не удалось сохранить файл';
    }
  }

  Future<String?> deleteBook(String id) async {
    final index = _books.indexWhere((book) => book.id == id);
    if (index == -1) {
      return 'Книга не найдена';
    }
    final book = _books[index];
    try {
      await _storeReady;
      await _store.remove(book.id);
      final file = File(book.storedPath);
      if (await file.exists()) {
        await file.delete();
      }
      _books.removeAt(index);
      notifyListeners();
      return null;
    } catch (e) {
      Log.d('Failed to delete book: $e');
      return 'Не удалось удалить книгу';
    }
  }

  Future<String?> clearLibrary() async {
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
      }
      await _loadLibrary();
      return null;
    } catch (e) {
      Log.d('Failed to clear library: $e');
      return 'Не удалось очистить библиотеку';
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
        hash: book.hash,
        addedAt: book.addedAt,
        lastOpenedAt: DateTime.now(),
        isMissing: book.isMissing,
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
      hash: book.hash,
      addedAt: book.addedAt,
      lastOpenedAt: book.lastOpenedAt,
      isMissing: true,
    );
    notifyListeners();
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
    } catch (e) {
      Log.d('Failed to load library: $e');
      _loading = false;
      notifyListeners();
    }
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

  void _addStubBook() {
    _books.add(
      LibraryBookItem(
        id: 'stub-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Imported book (stub) — ${DateTime.now()}',
        author: null,
        sourcePath: 'stub',
        storedPath: 'stub',
        hash: 'stub',
        addedAt: DateTime.now(),
        lastOpenedAt: null,
        isMissing: false,
      ),
    );
    notifyListeners();
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

class _BookMetadata {
  const _BookMetadata({required this.title, required this.author});

  final String title;
  final String? author;
}

Future<_BookMetadata> _readMetadata(String path, String fallbackTitle) async {
  try {
    final bytes = await File(path).readAsBytes();
    try {
      final book = await EpubReader.readBook(bytes);
      return _extractMetadata(
        fallbackTitle: fallbackTitle,
        title: book.Title,
        author: book.Author,
        authorList: book.AuthorList,
        schema: book.Schema,
      );
    } catch (e) {
      Log.d('Failed to read EPUB metadata: $e');
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
