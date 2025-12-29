import 'dart:io';

import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/core/services/storage_service_impl.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.pickEpubPath,
    this.storageService,
    this.stubImport = false,
  });

  final Future<String?> Function()? pickEpubPath;
  final StorageService? storageService;
  final bool stubImport;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final List<_BookItem> _books = <_BookItem>[];
  late final StorageService _storageService;
  late final LibraryStore _store;
  late final Future<void> _storeReady;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageService ?? AppStorageService();
    _store = LibraryStore();
    _storeReady = _store.init();
    _loadLibrary();
  }

  Future<void> _importEpub() async {
    Log.d('Import EPUB pressed.');
    if (widget.stubImport) {
      _addStubBook();
      return;
    }
    final path = widget.pickEpubPath == null
        ? await _pickEpubFromFilePicker()
        : await widget.pickEpubPath!();
    if (path == null) {
      _showError('Импорт отменён');
      return;
    }

    final validationError = await _validateEpubPath(path);
    if (validationError != null) {
      _showError(validationError);
      return;
    }

    try {
      await _storeReady;
      final stored = await _storageService.copyToAppStorageWithHash(path);
      final fallbackTitle = p.basenameWithoutExtension(path);
      final exists = await _store.existsByFingerprint(stored.hash);
      if (!mounted) {
        return;
      }
      if (exists) {
        _showError('Эта книга уже в библиотеке');
        return;
      }
      final metadata = await _readMetadata(stored.path, fallbackTitle);
      if (!mounted) {
        return;
      }
      final entry = LibraryEntry(
        id: stored.hash,
        title: metadata.title,
        author: metadata.author,
        localPath: stored.path,
        addedAt: DateTime.now(),
        fingerprint: stored.hash,
        sourcePath: File(path).absolute.path,
      );
      await _store.upsert(entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _books.add(
          _BookItem(
            id: entry.id,
            title: entry.title,
            author: entry.author,
            sourcePath: entry.sourcePath,
            storedPath: entry.localPath,
            hash: entry.fingerprint,
            addedAt: entry.addedAt,
          ),
        );
      });
      Log.d('EPUB copied to: ${stored.path}');
    } catch (e) {
      Log.d('EPUB import failed: $e');
      _showError('Не удалось сохранить файл');
    }
  }

  Future<void> _loadLibrary() async {
    if (widget.stubImport) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      return;
    }
    try {
      await _storeReady;
      final entries = await _store.loadAll();
      final items = entries.map(_BookItem.fromEntry).toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _books
          ..clear()
          ..addAll(items);
        _books.sort((a, b) => a.title.compareTo(b.title));
      });
    } catch (e) {
      Log.d('Failed to load library: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
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

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _addStubBook() {
    if (!mounted) {
      return;
    }
    setState(() {
      _books.add(
        _BookItem(
          id: 'stub-${DateTime.now().millisecondsSinceEpoch}',
          title: 'Imported book (stub) — ${DateTime.now()}',
          author: null,
          sourcePath: 'stub',
          storedPath: 'stub',
          hash: 'stub',
          addedAt: DateTime.now(),
        ),
      );
    });
  }

  void _open(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(title: _books[index].title),
      ),
    );
  }

  Future<void> _deleteBook(int index) async {
    final book = _books[index];
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить книгу?'),
        content: Text(book.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) {
      return;
    }
    try {
      await _storeReady;
      await _store.remove(book.id);
      final file = File(book.storedPath);
      if (await file.exists()) {
        await file.delete();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _books.removeAt(index);
      });
      _showError('Книга удалена');
    } catch (e) {
      Log.d('Failed to delete book: $e');
      _showError('Не удалось удалить книгу');
    }
  }

  Future<void> _clearLibrary() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить библиотеку?'),
        content: const Text(
          'Все сохраненные EPUB будут удалены из хранилища приложения.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (shouldClear != true) {
      return;
    }

    if (mounted) {
      setState(() {
        _books.clear();
      });
    }

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
      if (!mounted) {
        return;
      }
      await _loadLibrary();
      _showError('Библиотека очищена');
    } catch (e) {
      Log.d('Failed to clear library: $e');
      _showError('Не удалось очистить библиотеку');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Очистить библиотеку',
            onPressed: _books.isEmpty ? null : _clearLibrary,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Пока нет импортированных книг.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _importEpub,
                      child: const Text('Импортировать EPUB (заглушка)'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: _books.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                return ListTile(
                  title: Text(_books[i].title),
                  subtitle: _books[i].author == null
                      ? null
                      : Text(_books[i].author!),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteBook(i),
                    tooltip: 'Удалить книгу',
                  ),
                  onTap: () => _open(i),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importEpub,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _BookItem {
  const _BookItem({
    required this.id,
    required this.title,
    required this.author,
    required this.sourcePath,
    required this.storedPath,
    required this.hash,
    required this.addedAt,
  });

  factory _BookItem.fromEntry(LibraryEntry entry) {
    return _BookItem(
      id: entry.id,
      title: entry.title,
      author: entry.author,
      sourcePath: entry.sourcePath,
      storedPath: entry.localPath,
      hash: entry.fingerprint,
      addedAt: entry.addedAt,
    );
  }

  final String id;
  final String title;
  final String? author;
  final String sourcePath;
  final String storedPath;
  final String hash;
  final DateTime addedAt;
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
