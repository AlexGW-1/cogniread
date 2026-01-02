import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/features/library/presentation/library_controller.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
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
  late final LibraryController _controller;
  late final VoidCallback _controllerListener;
  String _query = '';
  String? _selectedBookId;

  @override
  void initState() {
    super.initState();
    _controller = LibraryController(
      storageService: widget.storageService,
      pickEpubPath: widget.pickEpubPath,
      stubImport: widget.stubImport,
    );
    _controllerListener = () {
      if (!mounted) {
        return;
      }
      setState(_syncSelection);
    };
    _controller.addListener(_controllerListener);
    _controller.init();
  }

  @override
  void dispose() {
    _controller.removeListener(_controllerListener);
    _controller.dispose();
    super.dispose();
  }

  void _syncSelection() {
    if (_controller.books.isEmpty) {
      _selectedBookId = null;
      return;
    }
    if (_selectedBookId == null ||
        !_controller.books.any((book) => book.id == _selectedBookId)) {
      _selectedBookId = _controller.books.first.id;
    }
  }

  Future<void> _importEpub() async {
    final error = await _controller.importEpub();
    if (error != null) {
      _showError(error);
    }
  }

  void _open(int index) {
    final book = _controller.books[index];
    _controller.markOpened(book.id);
    final isDesktop = MediaQuery.of(context).size.width >= 1000;
    if (isDesktop) {
      setState(() {
        _selectedBookId = book.id;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(bookId: book.id),
      ),
    );
  }

  Future<void> _deleteBook(int index) async {
    final book = _controller.books[index];
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
    final error = await _controller.deleteBook(book.id);
    if (error != null) {
      _showError(error);
      return;
    }
    _showError('Книга удалена');
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
    final error = await _controller.clearLibrary();
    if (error != null) {
      _showError(error);
      return;
    }
    _showError('Библиотека очищена');
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
            onPressed: _controller.books.isEmpty ? null : _clearLibrary,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _controller.loading
          ? const Center(child: CircularProgressIndicator())
          : _controller.books.isEmpty
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
                          key: const ValueKey('import-epub-button'),
                          onPressed: _importEpub,
                          child: const Text('Импортировать EPUB'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _controller.books.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, i) {
                    return ListTile(
                      title: Text(_controller.books[i].title),
                      subtitle: _controller.books[i].author == null
                          ? null
                          : Text(_controller.books[i].author!),
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
        key: const ValueKey('import-epub-fab'),
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
                          loading: _controller.loading,
                          books: filtered,
                          query: _query,
                          onQueryChanged: (value) {
                            setState(() {
                              _query = value;
                            });
                          },
                          onClearLibrary:
                              _controller.books.isEmpty ? null : _clearLibrary,
                          onImport: _importEpub,
                          onOpen: (index) => _open(
                            _controller.books.indexOf(filtered[index]),
                          ),
                          onDelete: (index) => _deleteBook(
                            _controller.books.indexOf(filtered[index]),
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

  List<LibraryBookItem> _filteredBooks() {
    if (_query.trim().isEmpty) {
      return _controller.books;
    }
    final needle = _query.toLowerCase().trim();
    return _controller.books
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
  final List<LibraryBookItem> books;
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

  final LibraryBookItem book;
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
