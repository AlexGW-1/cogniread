import 'dart:io';

import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/core/services/storage_service_impl.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
  final List<String> _books = <String>[];
  late final StorageService _storageService;

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageService ?? AppStorageService();
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

    if (!mounted) {
      return;
    }

    try {
      final storedPath = await _storageService.copyToAppStorage(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _books.add('Imported book (stub) — ${DateTime.now()}');
      });
      Log.d('EPUB copied to: $storedPath');
    } catch (e) {
      _showError('Не удалось сохранить файл: $e');
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
      _books.add('Imported book (stub) — ${DateTime.now()}');
    });
  }

  void _open(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(title: _books[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
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
                  title: Text(_books[i]),
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
