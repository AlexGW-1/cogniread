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
  String _query = '';
  String? _selectedBookId;

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageService ?? AppStorageService();
    _store = LibraryStore();
    _storeReady = widget.stubImport ? Future<void>.value() : _store.init();
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
      if (widget.stubImport) {
        _addStubBook();
        return;
      }
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
            lastOpenedAt: entry.lastOpenedAt,
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
        _books.sort(_sortByLastOpenedAt);
        if (_selectedBookId == null && _books.isNotEmpty) {
          _selectedBookId = _books.first.id;
        }
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
          lastOpenedAt: null,
        ),
      );
    });
  }

  void _open(int index) {
    if (!widget.stubImport) {
      _storeReady.then((_) {
        return _store.updateLastOpenedAt(_books[index].id, DateTime.now());
      });
    }
    final isDesktop = MediaQuery.of(context).size.width >= 1000;
    if (isDesktop) {
      setState(() {
        _selectedBookId = _books[index].id;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(bookId: _books[index].id),
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
        if (_selectedBookId == book.id) {
          _selectedBookId = _books.isEmpty ? null : _books.first.id;
        }
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
    final isDesktop = MediaQuery.of(context).size.width >= 1000;
    if (!isDesktop) {
      return _buildMobileScaffold();
    }
    return _buildDesktopScaffold();
  }

  Widget _buildMobileScaffold() {
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
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
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

  Widget _buildDesktopScaffold() {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _filteredBooks();
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.surfaceContainerHighest.withAlpha(153),
              scheme.surface.withAlpha(51),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: 0,
                onDestinationSelected: (_) {
                  _showError('Этот раздел появится позже');
                },
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton.icon(
                    onPressed: _importEpub,
                    icon: const Icon(Icons.add),
                    label: const Text('Импорт'),
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.library_books_outlined),
                    selectedIcon: Icon(Icons.library_books),
                    label: Text('Библиотека'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.search_outlined),
                    selectedIcon: Icon(Icons.search),
                    label: Text('Поиск'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    selectedIcon: Icon(Icons.menu_book),
                    label: Text('Читалка'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.edit_note_outlined),
                    selectedIcon: Icon(Icons.edit_note),
                    label: Text('Заметки'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: Text('Настройки'),
                  ),
                ],
              ),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Flexible(
                        flex: 4,
                        child: _LibraryPanel(
                          loading: _loading,
                          books: filtered,
                          query: _query,
                          onQueryChanged: (value) {
                            setState(() {
                              _query = value;
                            });
                          },
                          onClearLibrary: _books.isEmpty ? null : _clearLibrary,
                          onImport: _importEpub,
                          onOpen: (index) => _open(
                            _books.indexOf(filtered[index]),
                          ),
                          onDelete: (index) => _deleteBook(
                            _books.indexOf(filtered[index]),
                          ),
                          selectedId: _selectedBookId,
                          onSelect: (id) {
                            setState(() {
                              _selectedBookId = id;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 20),
                      Flexible(
                        flex: 7,
                        child: _ReaderPanel(
                          bookId: _selectedBookId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_BookItem> _filteredBooks() {
    if (_query.trim().isEmpty) {
      return _books;
    }
    final needle = _query.toLowerCase().trim();
    return _books
        .where(
          (book) =>
              book.title.toLowerCase().contains(needle) ||
              (book.author?.toLowerCase().contains(needle) ?? false),
        )
        .toList();
  }
}

class _LibraryPanel extends StatelessWidget {
  const _LibraryPanel({
    required this.loading,
    required this.books,
    required this.query,
    required this.onQueryChanged,
    required this.onClearLibrary,
    required this.onImport,
    required this.onOpen,
    required this.onDelete,
    required this.selectedId,
    required this.onSelect,
  });

  final bool loading;
  final List<_BookItem> books;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback? onClearLibrary;
  final VoidCallback onImport;
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onDelete;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface.withAlpha(230),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Library',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              TextButton.icon(
                onPressed: onClearLibrary,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Очистить'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: 'Поиск по библиотеке',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withAlpha(128),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : books.isEmpty
                    ? _LibraryEmpty(onImport: onImport)
                    : ListView.separated(
                        itemCount: books.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final book = books[index];
                          return _BookCard(
                            book: book,
                            selected: book.id == selectedId,
                            onTap: () {
                              onSelect(book.id);
                              onOpen(index);
                            },
                            onDelete: () => onDelete(index),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final _BookItem book;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selected ? scheme.primaryContainer : scheme.surface;
    final accentAlpha = selected ? 217 : 255;
    return Material(
      color: accent.withAlpha(accentAlpha),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BookCover(title: book.title),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (book.author != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        book.author!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Добавлена ${_formatDate(book.addedAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Удалить книгу',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = title.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    return Container(
      width: 56,
      height: 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withAlpha(230),
            scheme.tertiaryContainer.withAlpha(204),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          initial.toUpperCase(),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
        ),
      ),
    );
  }
}

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Пока нет импортированных книг.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('Импортировать EPUB'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderPanel extends StatelessWidget {
  const _ReaderPanel({required this.bookId});

  final String? bookId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (bookId == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: scheme.surface.withAlpha(230),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Center(
          child: Text(
            'Выберите книгу, чтобы начать чтение',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }
    return ReaderScreen(bookId: bookId!, embedded: true);
  }
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.'
      '${date.year}';
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
    required this.lastOpenedAt,
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
      lastOpenedAt: entry.lastOpenedAt,
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
}

int _sortByLastOpenedAt(_BookItem a, _BookItem b) {
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
