import 'dart:io';

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
  late final TextEditingController _searchController;
  String? _selectedBookId;
  String? _lastNotice;
  bool _showSearch = false;

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
      _handleNotices();
      setState(_syncSelection);
    };
    _controller.addListener(_controllerListener);
    _controller.init();
    _searchController = TextEditingController(text: _controller.query);
  }

  @override
  void dispose() {
    _controller.removeListener(_controllerListener);
    _controller.dispose();
    _searchController.dispose();
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
    await _controller.importEpub();
  }

  Future<void> _open(String id) async {
    final book = await _controller.prepareOpen(id);
    if (book == null) {
      return;
    }
    if (!mounted) {
      return;
    }
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
    final book = _controller.filteredBooks[index];
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
    await _controller.deleteBook(book.id);
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
    await _controller.clearLibrary();
  }

  void _handleNotices() {
    final error = _controller.errorMessage;
    final info = _controller.infoMessage;
    final message = error ?? info;
    if (message == null || message == _lastNotice) {
      return;
    }
    _lastNotice = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      _controller.clearNotices();
    });
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (_showSearch) {
        _searchController.text = _controller.query;
      } else {
        _searchController.clear();
        _controller.setQuery('');
      }
    });
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
    final scheme = Theme.of(context).colorScheme;
    final filtered = _controller.filteredBooks;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Очистить библиотеку',
            onPressed: _controller.books.isEmpty ? null : _clearLibrary,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: _showSearch ? 'Скрыть поиск' : 'Поиск',
            onPressed: _controller.books.isEmpty ? null : _toggleSearch,
            key: const ValueKey('library-search-toggle'),
            icon: Icon(_showSearch ? Icons.close : Icons.search),
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
              : Column(
                  children: [
                    if (_showSearch)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          key: const ValueKey('library-search-field'),
                          controller: _searchController,
                          onChanged: _controller.setQuery,
                          decoration: InputDecoration(
                            hintText: 'Поиск по библиотеке',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor:
                                scheme.surfaceContainerHighest.withAlpha(128),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: scheme.outlineVariant),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('Ничего не найдено.'),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final book = filtered[i];
                                return ListTile(
                                  key: ValueKey('library-book-tile-$i'),
                                  leading: _BookCover(
                                    title: book.title,
                                    coverPath: book.coverPath,
                                  ),
                                  title: Text(book.title),
                                  subtitle: _buildBookSubtitle(book, scheme),
                                  trailing: IconButton(
                                    key: ValueKey('library-delete-$i'),
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _deleteBook(i),
                                    tooltip: 'Удалить книгу',
                                  ),
                                  onTap: () => _open(book.id),
                                );
                              },
                            ),
                    ),
                  ],
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
    final filtered = _controller.filteredBooks;
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
                          query: _controller.query,
                          showSearch: _showSearch,
                          searchController: _searchController,
                          onQueryChanged: (value) {
                            _controller.setQuery(value);
                          },
                          onToggleSearch: _toggleSearch,
                          onClearLibrary:
                              _controller.books.isEmpty ? null : _clearLibrary,
                          onImport: _importEpub,
                          onOpen: (index) => _open(filtered[index].id),
                          onDelete: (index) => _deleteBook(index),
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

  Widget? _buildBookSubtitle(LibraryBookItem book, ColorScheme scheme) {
    if (book.isMissing) {
      final text = book.author == null
          ? 'Файл отсутствует'
          : '${book.author} · файл отсутствует';
      return Text(
        text,
        style: TextStyle(color: scheme.error),
      );
    }
    if (book.author == null) {
      return null;
    }
    return Text(book.author!);
  }
}

class _LibraryPanel extends StatelessWidget {
  const _LibraryPanel({
    required this.loading,
    required this.books,
    required this.query,
    required this.showSearch,
    required this.searchController,
    required this.onQueryChanged,
    required this.onToggleSearch,
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
  final bool showSearch;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleSearch;
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
              const SizedBox(width: 8),
              IconButton(
                tooltip: showSearch ? 'Скрыть поиск' : 'Поиск',
                onPressed: onToggleSearch,
                key: const ValueKey('library-search-toggle'),
                icon: Icon(showSearch ? Icons.close : Icons.search),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (showSearch) ...[
            TextField(
              key: const ValueKey('library-search-field'),
              controller: searchController,
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
          ],
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
                            key: ValueKey('library-book-card-$index'),
                            book: book,
                            index: index,
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
    super.key,
    required this.book,
    required this.index,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final LibraryBookItem book;
  final int index;
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
              _BookCover(title: book.title, coverPath: book.coverPath),
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
                    if (book.isMissing) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Файл отсутствует',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.error,
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
                key: ValueKey('library-delete-$index'),
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
  const _BookCover({required this.title, required this.coverPath});

  final String title;
  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = title.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    File? coverFile;
    if (coverPath != null) {
      final candidate = File(coverPath!);
      if (candidate.existsSync()) {
        coverFile = candidate;
      }
    }
    if (coverFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          coverFile,
          width: 56,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _BookCoverPlaceholder(
            initial: initial,
            scheme: scheme,
          ),
        ),
      );
    }
    return _BookCoverPlaceholder(initial: initial, scheme: scheme);
  }
}

class _BookCoverPlaceholder extends StatelessWidget {
  const _BookCoverPlaceholder({
    required this.initial,
    required this.scheme,
  });

  final String initial;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
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
