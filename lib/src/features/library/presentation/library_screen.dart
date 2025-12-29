import 'dart:io';

import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/core/services/storage_service_impl.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
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
  bool _libraryLoaded = false;

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageService ?? AppStorageService();
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
      final stored = await _storageService.copyToAppStorageWithHash(path);
      final title = p.basenameWithoutExtension(path);
      if (!mounted) {
        return;
      }
      final hasSame = _books.any(
        (book) => book.hash == stored.hash || book.storedPath == stored.path,
      );
      if (stored.alreadyExists && !hasSame) {
        setState(() {
          _books.add(
            _BookItem(
              title: title,
              sourcePath: File(path).absolute.path,
              storedPath: stored.path,
              hash: stored.hash,
            ),
          );
        });
        return;
      }
      if (hasSame) {
        _showError('Эта книга уже в библиотеке');
        return;
      }
      setState(() {
        _books.add(
          _BookItem(
            title: title,
            sourcePath: File(path).absolute.path,
            storedPath: stored.path,
            hash: stored.hash,
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
    try {
      final dirPath = await _storageService.appStoragePath();
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        return;
      }
      final entries = await dir.list().toList();
      final items = <_BookItem>[];
      for (final entry in entries) {
        if (entry is! File) {
          continue;
        }
        final path = entry.path;
        if (!path.toLowerCase().endsWith('.epub')) {
          continue;
        }
        items.add(
          _BookItem(
            title: p.basenameWithoutExtension(path),
            sourcePath: path,
            storedPath: path,
            hash: '',
          ),
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _libraryLoaded = true;
        _books
          ..clear()
          ..addAll(_dedupeByStoredPath(items));
        _books.sort((a, b) => a.title.compareTo(b.title));
      });
    } catch (e) {
      Log.d('Failed to load library: $e');
    }
  }

  List<_BookItem> _dedupeByStoredPath(List<_BookItem> items) {
    final seen = <String>{};
    final unique = <_BookItem>[];
    for (final item in items) {
      if (seen.add(item.storedPath)) {
        unique.add(item);
      }
    }
    return unique;
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
          title: 'Imported book (stub) — ${DateTime.now()}',
          sourcePath: 'stub',
          storedPath: 'stub',
          hash: 'stub',
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
      body: _books.isEmpty
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
    required this.title,
    required this.sourcePath,
    required this.storedPath,
    required this.hash,
  });

  final String title;
  final String sourcePath;
  final String storedPath;
  final String hash;
}
