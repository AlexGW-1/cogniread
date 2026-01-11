import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/features/library/presentation/library_controller.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
import 'package:cogniread/src/features/sync/data/event_log_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late final TextEditingController _globalSearchController;
  String? _selectedBookId;
  String? _lastNotice;
  bool _showSearch = false;
  String? _pendingNoteId;
  String? _pendingHighlightId;

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
    _globalSearchController = TextEditingController(
      text: _controller.globalSearchQuery,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_controllerListener);
    _controller.dispose();
    _searchController.dispose();
    _globalSearchController.dispose();
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

  Future<void> _open(
    String id, {
    String? initialNoteId,
    String? initialHighlightId,
  }) async {
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
        _pendingNoteId = initialNoteId;
        _pendingHighlightId = initialHighlightId;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          bookId: book.id,
          initialNoteId: initialNoteId,
          initialHighlightId: initialHighlightId,
        ),
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

  void _showGlobalSearch() {
    _globalSearchController.text = _controller.globalSearchQuery;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final query = _controller.globalSearchQuery.trim();
            final searching = _controller.globalSearching;
            final results = _controller.globalSearchResults;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Глобальный поиск',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Закрыть',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    TextField(
                      controller: _globalSearchController,
                      onChanged: _controller.setGlobalSearchQuery,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Книги, заметки, выделения',
                        prefixIcon: Icon(Icons.manage_search),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (searching) const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: query.isEmpty
                          ? const Center(
                              child: Text(
                                'Введите запрос для поиска.',
                              ),
                            )
                          : results.isEmpty && !searching
                              ? const Center(
                                  child: Text('Ничего не найдено.'),
                                )
                              : ListView.separated(
                                  itemCount: results.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final result = results[index];
                                    return _SearchResultTile(
                                      result: result,
                                      onTap: () => _openSearchResult(result),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEventLogDebug() async {
    final store = EventLogStore();
    await store.init();
    final events = store.listEvents(limit: 50);
    if (!mounted) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Event log',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Копировать JSON',
                      onPressed: events.isEmpty
                          ? null
                          : () async {
                              final payload = events
                                  .map((event) => event.toMap())
                                  .toList();
                              final json = jsonEncode(payload);
                              await Clipboard.setData(
                                ClipboardData(text: json),
                              );
                              if (!context.mounted) {
                                return;
                              }
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Event log скопирован в буфер'),
                                ),
                              );
                            },
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: events.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Пока нет событий в журнале.'),
                        ),
                      )
                    : ListView.separated(
                        itemCount: events.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final event = events[index];
                          return ListTile(
                            title: Text('${event.entityType} · ${event.op}'),
                            subtitle: Text(
                              '${event.entityId} · ${event.createdAt.toIso8601String()}',
                            ),
                            dense: true,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSearchResult(LibrarySearchResult result) async {
    Navigator.of(context).pop();
    if (result.type == LibrarySearchResultType.book) {
      await _open(result.bookId);
      return;
    }
    await _open(
      result.bookId,
      initialNoteId:
          result.type == LibrarySearchResultType.note ? result.markId : null,
      initialHighlightId: result.type == LibrarySearchResultType.highlight
          ? result.markId
          : null,
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
            tooltip: 'Event log',
            onPressed: _showEventLogDebug,
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(
            tooltip: 'Глобальный поиск',
            onPressed: _controller.books.isEmpty ? null : _showGlobalSearch,
            icon: const Icon(Icons.manage_search),
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
                onDestinationSelected: (index) {
                  if (index == 0) {
                    return;
                  }
                  if (index == 1) {
                    _showGlobalSearch();
                    return;
                  }
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
                          onGlobalSearch:
                              _controller.books.isEmpty ? null : _showGlobalSearch,
                          onEventLog: _showEventLogDebug,
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
                          initialNoteId: _pendingNoteId,
                          initialHighlightId: _pendingHighlightId,
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
    required this.onGlobalSearch,
    required this.onEventLog,
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
  final VoidCallback? onGlobalSearch;
  final VoidCallback onEventLog;
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
                tooltip: 'Event log',
                onPressed: onEventLog,
                icon: const Icon(Icons.bug_report_outlined),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Глобальный поиск',
                onPressed: onGlobalSearch,
                icon: const Icon(Icons.manage_search),
              ),
              const SizedBox(width: 4),
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
  const _ReaderPanel({
    required this.bookId,
    required this.initialNoteId,
    required this.initialHighlightId,
  });

  final String? bookId;
  final String? initialNoteId;
  final String? initialHighlightId;

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
    return ReaderScreen(
      bookId: bookId!,
      embedded: true,
      initialNoteId: initialNoteId,
      initialHighlightId: initialHighlightId,
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.onTap,
  });

  final LibrarySearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = result.sourceLabel;
    final bookSubtitle = [
      if (result.bookAuthor != null && result.bookAuthor!.trim().isNotEmpty)
        result.bookAuthor,
      label,
    ].whereType<String>().join(' · ');
    return ListTile(
      leading: Icon(
        _iconForResult(result.type),
        color: scheme.primary,
      ),
      title: Text(
        result.type == LibrarySearchResultType.book
            ? result.bookTitle
            : result.snippet,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        result.type == LibrarySearchResultType.book
            ? bookSubtitle
            : '${result.bookTitle} · $label',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }

  IconData _iconForResult(LibrarySearchResultType type) {
    switch (type) {
      case LibrarySearchResultType.book:
        return Icons.menu_book_outlined;
      case LibrarySearchResultType.note:
        return Icons.edit_note_outlined;
      case LibrarySearchResultType.highlight:
        return Icons.highlight_outlined;
    }
  }
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.'
      '${date.year}';
}
