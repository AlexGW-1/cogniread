import 'dart:async';
import 'dart:io';

import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/core/ui/mark_colors.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/library/presentation/library_controller.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
import 'package:cogniread/src/features/search/presentation/global_search_sheet.dart';
import 'package:cogniread/src/features/search/search_index_service.dart';
import 'package:cogniread/src/features/search/search_models.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.pickEpubPath,
    this.storageService,
    this.syncAdapter,
    this.stubImport = false,
  });

  final Future<String?> Function()? pickEpubPath;
  final StorageService? storageService;
  final SyncAdapter? syncAdapter;
  final bool stubImport;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryController _controller;
  late final VoidCallback _controllerListener;
  late final TextEditingController _searchController;
  late final TextEditingController _globalSearchController;
  late final TextEditingController _historyFilterController;
  String? _selectedBookId;
  String? _lastOpenedBookId;
  String? _lastNotice;
  bool _showSearch = false;
  String? _pendingNoteId;
  String? _pendingHighlightId;
  String? _pendingAnchor;
  String? _pendingSearchQuery;
  int _sectionIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = LibraryController(
      storageService: widget.storageService,
      pickEpubPath: widget.pickEpubPath,
      syncAdapter: widget.syncAdapter,
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
    _controller.init().catchError((Object error, StackTrace stackTrace) {
      Log.d('LibraryController init failed: $error');
    });
    _searchController = TextEditingController(text: _controller.query);
    _globalSearchController = TextEditingController(
      text: _controller.globalSearchQuery,
    );
    _historyFilterController = TextEditingController();
  }

  @override
  void dispose() {
    _controller.removeListener(_controllerListener);
    _controller.dispose();
    _searchController.dispose();
    _globalSearchController.dispose();
    _historyFilterController.dispose();
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
    String? initialAnchor,
    String? initialSearchQuery,
  }) async {
    final book = await _controller.prepareOpen(id);
    if (book == null) {
      return;
    }
    _lastOpenedBookId = book.id;
    if (!mounted) {
      return;
    }
    final isDesktop = MediaQuery.of(context).size.width >= 1000;
    if (isDesktop) {
      setState(() {
        _sectionIndex = 0;
        _selectedBookId = book.id;
        _pendingNoteId = initialNoteId;
        _pendingHighlightId = initialHighlightId;
        _pendingAnchor = initialAnchor;
        _pendingSearchQuery = initialSearchQuery;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          bookId: book.id,
          initialNoteId: initialNoteId,
          initialHighlightId: initialHighlightId,
          initialAnchor: initialAnchor,
          initialSearchQuery: initialSearchQuery,
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
          'Все сохраненные EPUB будут удалены из хранилища приложения.\n\n'
          'Если синхронизация включена, книги могут снова загрузиться из облака.',
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
    final authError = _controller.authError;
    final info = _controller.infoMessage;
    final message = error ?? authError ?? info;
    if (message == null || message == _lastNotice) {
      return;
    }
    _lastNotice = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      _controller.clearNotices();
    });
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

  void _showGlobalSearch({String? initialQuery}) {
    if (initialQuery != null) {
      _globalSearchController.text = initialQuery;
    }
    final meta = <String, ({String title, String? author})>{
      for (final book in _controller.books)
        book.id: (title: book.title, author: book.author),
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return GlobalSearchScreen(
            initialQuery: _globalSearchController.text,
            searchIndex: _controller.searchIndex,
            resolveBookTitle: (bookId) => meta[bookId]?.title ?? 'Книга',
            resolveBookAuthor: (bookId) => meta[bookId]?.author,
            recentQueries: _controller.searchHistory,
            onClearRecentQueries: _controller.clearSearchHistory,
            onRemoveRecentQuery: _controller.removeSearchHistoryQuery,
            onSaveQuery: (query) {
              unawaited(_controller.addSearchHistoryQuery(query));
            },
            onOpen:
                (
                  bookId, {
                  String? initialNoteId,
                  String? initialHighlightId,
                  String? initialAnchor,
                  String? initialSearchQuery,
                }) async {
                  await _open(
                    bookId,
                    initialNoteId: initialNoteId,
                    initialHighlightId: initialHighlightId,
                    initialAnchor: initialAnchor,
                    initialSearchQuery: initialSearchQuery,
                  );
                },
          );
        },
      ),
    );
  }

  Future<void> _toggleViewMode() async {
    final next = _controller.viewMode == LibraryViewMode.list
        ? LibraryViewMode.grid
        : LibraryViewMode.list;
    await _controller.setViewMode(next);
  }

  Future<void> _selectMobileSection(int index) async {
    if (!mounted) {
      return;
    }
    if (index == 2) {
      final bookId = _lastOpenedBookId;
      if (bookId != null && _controller.books.any((b) => b.id == bookId)) {
        setState(() {
          _sectionIndex = 0;
        });
        await _open(bookId);
        return;
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Откройте книгу в библиотеке')),
      );
      setState(() {
        _sectionIndex = 0;
      });
      return;
    }
    setState(() {
      _sectionIndex = index;
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
    final viewMode = _controller.viewMode;
    return Scaffold(
      appBar: AppBar(
        title: Text(_sectionTitle(_sectionIndex)),
        actions: [
          if (_sectionIndex == 0) ...[
            IconButton(
              tooltip: 'Очистить библиотеку',
              onPressed: _controller.books.isEmpty ? null : _clearLibrary,
              icon: const Icon(Icons.delete_outline),
            ),
            IconButton(
              tooltip: viewMode == LibraryViewMode.list ? 'Плитка' : 'Список',
              onPressed: _controller.books.isEmpty ? null : _toggleViewMode,
              icon: Icon(
                viewMode == LibraryViewMode.list
                    ? Icons.grid_view_outlined
                    : Icons.view_list_outlined,
              ),
            ),
          ],
          IconButton(
            tooltip: 'Глобальный поиск',
            onPressed: _controller.books.isEmpty ? null : _showGlobalSearch,
            icon: const Icon(Icons.manage_search),
          ),
          if (_sectionIndex == 0)
            IconButton(
              tooltip: _showSearch ? 'Скрыть поиск' : 'Поиск',
              onPressed: _controller.books.isEmpty ? null : _toggleSearch,
              key: const ValueKey('library-search-toggle'),
              icon: Icon(_showSearch ? Icons.close : Icons.search),
            ),
        ],
      ),
      body: _buildMobileSection(
        scheme: scheme,
        filtered: filtered,
        viewMode: viewMode,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _sectionIndex,
        onDestinationSelected: _selectMobileSection,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Библиотека',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Поиск',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Читалка',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: 'Заметки',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
      ),
      floatingActionButton: _sectionIndex == 0
          ? FloatingActionButton(
              key: const ValueKey('import-epub-fab'),
              onPressed: _importEpub,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildMobileSection({
    required ColorScheme scheme,
    required List<LibraryBookItem> filtered,
    required LibraryViewMode viewMode,
  }) {
    if (_sectionIndex == 4) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _SettingsPanel(controller: _controller),
        ),
      );
    }
    if (_sectionIndex == 1) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _SearchHistoryPanel(
            history: _controller.searchHistory,
            filterController: _historyFilterController,
            onOpenSearch: _controller.books.isEmpty ? null : _showGlobalSearch,
            onOpenQuery: (query) {
              unawaited(_controller.addSearchHistoryQuery(query));
              _showGlobalSearch(initialQuery: query);
            },
            onDeleteQuery: (query) {
              unawaited(_controller.removeSearchHistoryQuery(query));
            },
            onClear: () {
              unawaited(_controller.clearSearchHistory());
            },
          ),
        ),
      );
    }
    if (_sectionIndex == 2) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: const _SectionPlaceholder(
            title: 'Читалка',
            subtitle: 'Откройте книгу из библиотеки — она появится здесь.',
          ),
        ),
      );
    }
    if (_sectionIndex == 3) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _NotesPanel(
            controller: _controller,
            onOpenNote: (bookId, noteId) {
              _open(bookId, initialNoteId: noteId);
            },
            onOpenHighlight: (bookId, highlightId) {
              _open(bookId, initialHighlightId: highlightId);
            },
          ),
        ),
      );
    }
    return _buildMobileLibrarySection(
      scheme: scheme,
      filtered: filtered,
      viewMode: viewMode,
    );
  }

  Widget _buildMobileLibrarySection({
    required ColorScheme scheme,
    required List<LibraryBookItem> filtered,
    required LibraryViewMode viewMode,
  }) {
    if (_controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.books.isEmpty) {
      return Center(
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
      );
    }
    return Column(
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
                fillColor: scheme.surfaceContainerHighest.withAlpha(128),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
              ),
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Ничего не найдено.'))
              : viewMode == LibraryViewMode.list
              ? ListView.separated(
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
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = width >= 600 ? 4 : 3;
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.68,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final book = filtered[i];
                        return _BookGridTile(
                          key: ValueKey('library-book-grid-$i'),
                          book: book,
                          onTap: () => _open(book.id),
                          onDelete: () => _deleteBook(i),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDesktopScaffold() {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _controller.filteredBooks;
    final viewMode = _controller.viewMode;
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
                selectedIndex: _sectionIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _sectionIndex = index;
                  });
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
                  child: _buildSection(filtered: filtered, viewMode: viewMode),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required List<LibraryBookItem> filtered,
    required LibraryViewMode viewMode,
  }) {
    if (_sectionIndex == 4) {
      return _SettingsPanel(controller: _controller);
    }
    if (_sectionIndex == 1) {
      return _SearchHistoryPanel(
        history: _controller.searchHistory,
        filterController: _historyFilterController,
        onOpenSearch: _controller.books.isEmpty ? null : _showGlobalSearch,
        onOpenQuery: (query) {
          unawaited(_controller.addSearchHistoryQuery(query));
          _showGlobalSearch(initialQuery: query);
        },
        onDeleteQuery: (query) {
          unawaited(_controller.removeSearchHistoryQuery(query));
        },
        onClear: () {
          unawaited(_controller.clearSearchHistory());
        },
      );
    }
    if (_sectionIndex == 2) {
      final selected = _selectedBookId;
      final bookId =
          selected != null && _controller.books.any((b) => b.id == selected)
          ? selected
          : _lastOpenedBookId;
      return _ReaderPanel(
        bookId: bookId,
        initialNoteId: _pendingNoteId,
        initialHighlightId: _pendingHighlightId,
        initialAnchor: _pendingAnchor,
        initialSearchQuery: _pendingSearchQuery,
      );
    }
    if (_sectionIndex == 3) {
      return _NotesPanel(
        controller: _controller,
        onOpenNote: (bookId, noteId) {
          _open(bookId, initialNoteId: noteId);
        },
        onOpenHighlight: (bookId, highlightId) {
          _open(bookId, initialHighlightId: highlightId);
        },
      );
    }
    if (_sectionIndex != 0) {
      return _SectionPlaceholder(
        title: _sectionTitle(_sectionIndex),
        subtitle: 'Раздел в разработке',
      );
    }
    return Row(
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
            viewMode: viewMode,
            onToggleViewMode: _toggleViewMode,
            onToggleSearch: _toggleSearch,
            onGlobalSearch: _controller.books.isEmpty
                ? null
                : _showGlobalSearch,
            onClearLibrary: _controller.books.isEmpty ? null : _clearLibrary,
            onImport: _importEpub,
            onOpen: (index) => _open(filtered[index].id),
            onDelete: (index) => _deleteBook(index),
            selectedId: _selectedBookId,
            onSelect: (id) {
              setState(() {
                _selectedBookId = id;
                _pendingNoteId = null;
                _pendingHighlightId = null;
                _pendingAnchor = null;
                _pendingSearchQuery = null;
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
            initialAnchor: _pendingAnchor,
            initialSearchQuery: _pendingSearchQuery,
          ),
        ),
      ],
    );
  }

  String _sectionTitle(int index) {
    switch (index) {
      case 0:
        return 'Библиотека';
      case 1:
        return 'Поиск';
      case 2:
        return 'Читалка';
      case 3:
        return 'Заметки';
      case 4:
        return 'Настройки';
      default:
        return 'Раздел';
    }
  }

  Widget? _buildBookSubtitle(LibraryBookItem book, ColorScheme scheme) {
    if (book.isMissing) {
      final text = book.author == null
          ? 'Файл отсутствует'
          : '${book.author} · файл отсутствует';
      return Text(text, style: TextStyle(color: scheme.error));
    }
    if (book.author == null) {
      return null;
    }
    return Text(book.author!);
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final lastSync = controller.lastSyncAt;
        final lastSyncOk = controller.lastSyncOk;
        final syncSummary = controller.lastSyncSummary;
        final syncLabel = controller.syncAdapterLabel;
        final syncAvailable = syncLabel != 'none';
        final oauthConnected = controller.isSyncProviderConnected;
        final isNas = controller.isNasProvider;
        final isBasicAuth = controller.isBasicAuthProvider;
        final authInProgress = controller.authInProgress;
        final connectionInProgress = controller.connectionInProgress;
        final deleteInProgress = controller.deleteInProgress;
        final authError = controller.authError;
        final basicCredentials = controller.basicAuthCredentials;
        final smbCredentials = controller.smbCredentials;
        final providers = controller.availableSyncProviders;
        final selectedProvider = providers.contains(controller.syncProvider)
            ? controller.syncProvider
            : providers.first;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Синхронизация',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Провайдер',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<SyncProvider>(
                      value: selectedProvider,
                      onChanged: (value) {
                        if (value != null) {
                          controller.setSyncProvider(value);
                        }
                      },
                      items: providers
                          .map(
                            (provider) => DropdownMenuItem(
                              value: provider,
                              child: Text(_providerLabel(provider)),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Адаптер: $syncLabel',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (!syncAvailable) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Адаптер не подключен. Проверь настройки подключения.',
                        style: TextStyle(color: scheme.error),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: controller.syncInProgress || !syncAvailable
                          ? null
                          : controller.syncNow,
                      icon: controller.syncInProgress
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        controller.syncInProgress
                            ? 'Синхронизация...'
                            : (lastSyncOk == false
                                  ? 'Повторить'
                                  : 'Синхронизировать сейчас'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: deleteInProgress || !syncAvailable
                          ? null
                          : () => _confirmDeleteRemote(context, controller),
                      icon: deleteInProgress
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_forever),
                      label: const Text('Удалить файлы синка в облаке'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      lastSync == null
                          ? 'Последняя синхронизация: ещё не выполнялась'
                          : 'Последняя синхронизация: ${lastSync.toLocal()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (lastSyncOk != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        lastSyncOk ? 'Статус: успех' : 'Статус: ошибка',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: lastSyncOk ? scheme.primary : scheme.error,
                        ),
                      ),
                    ],
                    if (syncSummary != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Результат: $syncSummary',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Подключение',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    if (isBasicAuth) ...[
                      const SizedBox(height: 6),
                      Text(
                        'NAS использует WebDAV логин/пароль и SMB путь (резервный доступ).',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (basicCredentials != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'WebDAV URL: ${basicCredentials.baseUrl}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          'WebDAV логин: ${basicCredentials.username}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          basicCredentials.syncPath.isEmpty
                              ? 'WebDAV папка: /'
                              : 'WebDAV папка: ${basicCredentials.syncPath}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          basicCredentials.allowInsecure
                              ? 'SSL: проверка отключена'
                              : 'SSL: проверка включена',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                    if (isNas) ...[
                      const SizedBox(height: 6),
                      Text(
                        'SMB использует путь к смонтированной папке.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (smbCredentials != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'SMB путь: ${smbCredentials.mountPath}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    Text(
                      oauthConnected
                          ? 'Статус: подключено'
                          : 'Статус: не подключено',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (authError != null) ...[
                      const SizedBox(height: 6),
                      Text(authError, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!oauthConnected)
                          FilledButton.icon(
                            onPressed: authInProgress
                                ? null
                                : () => _startConnectFlow(context, controller),
                            icon: authInProgress
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.login),
                            label: Text(
                              authInProgress
                                  ? 'Открываем браузер...'
                                  : (isBasicAuth
                                        ? 'Настроить'
                                        : 'Подключить ${_providerLabel(controller.syncProvider)}'),
                            ),
                          ),
                        if (oauthConnected)
                          OutlinedButton.icon(
                            onPressed: authInProgress
                                ? null
                                : controller.disconnectSyncProvider,
                            icon: const Icon(Icons.logout),
                            label: const Text('Отключить'),
                          ),
                        if (oauthConnected && !isNas)
                          OutlinedButton.icon(
                            onPressed: authInProgress
                                ? null
                                : () async {
                                    await controller.disconnectSyncProvider();
                                    if (!context.mounted) {
                                      return;
                                    }
                                    await _startConnectFlow(
                                      context,
                                      controller,
                                    );
                                  },
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Переподключить'),
                          ),
                        OutlinedButton.icon(
                          onPressed: connectionInProgress || !oauthConnected
                              ? null
                              : controller.testSyncConnection,
                          icon: connectionInProgress
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_done),
                          label: const Text('Проверить'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Диагностика',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Лог: ${controller.logFilePath ?? 'не доступен'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: controller.copyLogPath,
                          icon: const Icon(Icons.copy),
                          label: const Text('Копировать путь'),
                        ),
                        OutlinedButton.icon(
                          onPressed: controller.openLogFolder,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Открыть папку'),
                        ),
                        OutlinedButton.icon(
                          onPressed: controller.exportLog,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Экспорт лога'),
                        ),
                        OutlinedButton.icon(
                          onPressed: controller.isSyncProviderConnected
                              ? () => controller.uploadDiagnosticsToCloud()
                              : null,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('В облако'),
                        ),
                        _SearchIndexDiagnosticsCard(
                          searchIndex: controller.searchIndex,
                        ),
                        if (kDebugMode)
                          OutlinedButton.icon(
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Сбросить синхронизацию?'),
                                  content: const Text(
                                    'Будут удалены токены/настройки синхронизации и '
                                    'статус последней синхронизации. '
                                    'Нужно для “чистого” ручного теста.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Отмена'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Сбросить'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true || !context.mounted) {
                                return;
                              }
                              await controller.resetSyncSettingsForTesting();
                            },
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Сбросить (тест)'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _providerLabel(SyncProvider provider) {
    switch (provider) {
      case SyncProvider.googleDrive:
        return 'Google Drive';
      case SyncProvider.dropbox:
        return 'Dropbox';
      case SyncProvider.oneDrive:
        return 'OneDrive';
      case SyncProvider.yandexDisk:
        return 'Yandex Disk';
      case SyncProvider.webDav:
        return 'NAS (WebDAV/SMB)';
      case SyncProvider.synologyDrive:
      case SyncProvider.smb:
        return 'NAS (WebDAV/SMB)';
    }
  }

  Future<void> _startConnectFlow(
    BuildContext context,
    LibraryController controller,
  ) async {
    if (controller.isNasProvider) {
      await _showNasDialog(context, controller);
      return;
    }
    if (controller.requiresManualOAuthCode) {
      await _connectYandexWithManualCode(context, controller);
      return;
    }
    await controller.connectSyncProvider();
  }

  Future<void> _showNasDialog(
    BuildContext context,
    LibraryController controller,
  ) async {
    final credentials = controller.webDavCredentials;
    final smbCredentials = controller.smbCredentials;
    final baseController = TextEditingController(
      text: credentials?.baseUrl ?? '',
    );
    final userController = TextEditingController(
      text: credentials?.username ?? '',
    );
    final passController = TextEditingController(
      text: credentials?.password ?? '',
    );
    final pathController = TextEditingController(
      text: credentials?.syncPath ?? 'cogniread',
    );
    final smbController = TextEditingController(
      text: smbCredentials?.mountPath ?? '',
    );
    bool obscurePassword = true;
    bool allowInsecure = credentials?.allowInsecure ?? false;
    bool testingWebDav = false;
    bool testingSmb = false;
    bool listingFolders = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('NAS (WebDAV/SMB)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'WebDAV (предпочтительно)',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: baseController,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://nas.local/dav/',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pathController,
                  decoration: const InputDecoration(
                    labelText: 'Папка синхронизации',
                    hintText: 'cogniread (пусто = корень)',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: listingFolders
                      ? null
                      : () async {
                          setDialogState(() {
                            listingFolders = true;
                          });
                          final selected = await _pickWebDavFolder(
                            context,
                            controller,
                            label: 'WebDAV',
                            baseUrl: baseController.text,
                            username: userController.text,
                            password: passController.text,
                            allowInsecure: allowInsecure,
                          );
                          if (selected != null) {
                            pathController.text = selected;
                          }
                          if (context.mounted) {
                            setDialogState(() {
                              listingFolders = false;
                            });
                          }
                        },
                  icon: listingFolders
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open),
                  label: Text(listingFolders ? 'Загрузка...' : 'Выбрать папку'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userController,
                  decoration: const InputDecoration(labelText: 'Логин'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passController,
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setDialogState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ),
                  obscureText: obscurePassword,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Принимать все сертификаты'),
                  value: allowInsecure,
                  onChanged: (value) {
                    setDialogState(() {
                      allowInsecure = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: testingWebDav
                      ? null
                      : () async {
                          setDialogState(() {
                            testingWebDav = true;
                          });
                          await controller.testWebDavCredentials(
                            baseUrl: baseController.text,
                            username: userController.text,
                            password: passController.text,
                            allowInsecure: allowInsecure,
                            syncPath: pathController.text,
                          );
                          if (context.mounted) {
                            setDialogState(() {
                              testingWebDav = false;
                            });
                          }
                        },
                  icon: testingWebDav
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_done),
                  label: Text(
                    testingWebDav ? 'Проверяем WebDAV...' : 'Проверить WebDAV',
                  ),
                ),
                const Divider(height: 24),
                Text(
                  'SMB (резервный доступ)',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Укажи путь к смонтированной папке. Подпапка берется из поля "Папка синхронизации".',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: smbController,
                  decoration: const InputDecoration(
                    labelText: 'SMB путь',
                    hintText: '/Volumes/Share или \\\\server\\share',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: testingSmb
                      ? null
                      : () async {
                          setDialogState(() {
                            testingSmb = true;
                          });
                          await controller.testSmbCredentials(
                            mountPath: smbController.text,
                          );
                          if (context.mounted) {
                            setDialogState(() {
                              testingSmb = false;
                            });
                          }
                        },
                  icon: testingSmb
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_done),
                  label: Text(
                    testingSmb ? 'Проверяем SMB...' : 'Проверить SMB',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                final saved = await controller.saveNasCredentials(
                  baseUrl: baseController.text,
                  username: userController.text,
                  password: passController.text,
                  allowInsecure: allowInsecure,
                  syncPath: pathController.text,
                  smbMountPath: smbController.text,
                );
                if (saved && context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectYandexWithManualCode(
    BuildContext context,
    LibraryController controller,
  ) async {
    final authUrl = await controller.beginOAuthConnection();
    if (authUrl == null) {
      return;
    }
    final launched = await launchUrl(
      authUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      controller.cancelOAuthConnection('Не удалось открыть браузер');
      return;
    }

    if (!context.mounted) {
      return;
    }

    final codeController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yandex Disk'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'В браузере откроется страница Яндекса с кодом. '
              'Скопируй код и вставь сюда:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: 'Код'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.cancelOAuthConnection('Подключение отменено');
              Navigator.of(context).pop();
            },
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              final code = codeController.text;
              await controller.submitOAuthCode(code);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Подключить'),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickWebDavFolder(
    BuildContext context,
    LibraryController controller, {
    required String label,
    required String baseUrl,
    required String username,
    required String password,
    required bool allowInsecure,
  }) async {
    final folders = await controller.listWebDavFolders(
      label: label,
      baseUrl: baseUrl,
      username: username,
      password: password,
      allowInsecure: allowInsecure,
    );
    if (!context.mounted) {
      return null;
    }
    if (folders.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Папки не найдены'),
          content: const Text(
            'Не удалось найти папки на сервере. Проверь URL и доступ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Ок'),
            ),
          ],
        ),
      );
      return null;
    }
    final selection = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Выбери папку'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Корень (/)'),
          ),
          for (final folder in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(folder),
              child: Text(folder),
            ),
        ],
      ),
    );
    return selection;
  }

  Future<void> _confirmDeleteRemote(
    BuildContext context,
    LibraryController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить файлы синка?'),
        content: const Text(
          'Будут удалены event_log.json, state.json, meta.json, books_index.json '
          'и папка books/ из облака.',
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
    if (confirmed == true) {
      await controller.deleteRemoteSyncFiles();
    }
  }
}

class _SearchHistoryPanel extends StatefulWidget {
  const _SearchHistoryPanel({
    required this.history,
    required this.filterController,
    required this.onOpenQuery,
    required this.onDeleteQuery,
    required this.onClear,
    this.onOpenSearch,
  });

  final List<String> history;
  final TextEditingController filterController;
  final VoidCallback? onOpenSearch;
  final ValueChanged<String> onOpenQuery;
  final ValueChanged<String> onDeleteQuery;
  final VoidCallback onClear;

  @override
  State<_SearchHistoryPanel> createState() => _SearchHistoryPanelState();
}

class _SearchHistoryPanelState extends State<_SearchHistoryPanel> {
  @override
  void initState() {
    super.initState();
    widget.filterController.addListener(_onFilterChanged);
  }

  @override
  void didUpdateWidget(covariant _SearchHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterController != widget.filterController) {
      oldWidget.filterController.removeListener(_onFilterChanged);
      widget.filterController.addListener(_onFilterChanged);
    }
  }

  @override
  void dispose() {
    widget.filterController.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onFilterChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needle = widget.filterController.text.trim().toLowerCase();
    final history = widget.history;
    final filtered = needle.isEmpty
        ? history
        : history
              .where((value) => value.toLowerCase().contains(needle))
              .toList();
    final hasQuery = needle.isNotEmpty;
    final openSearch = widget.onOpenSearch;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface.withAlpha(230),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(16),
            blurRadius: 22,
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
                  'Поиск',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (openSearch != null) ...[
                FilledButton.icon(
                  onPressed: openSearch,
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Открыть поиск'),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: history.isEmpty ? null : widget.onClear,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Очистить историю'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.filterController,
            decoration: InputDecoration(
              hintText: 'Поиск в истории',
              prefixIcon: const Icon(Icons.history),
              suffixIcon: hasQuery
                  ? IconButton(
                      tooltip: 'Очистить',
                      onPressed: () => widget.filterController.clear(),
                      icon: const Icon(Icons.close),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      hasQuery ? 'Ничего не найдено.' : 'История поиска пуста.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (context, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final query = filtered[index];
                      return ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(
                          query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'Удалить из истории',
                          onPressed: () => widget.onDeleteQuery(query),
                          icon: const Icon(Icons.close),
                        ),
                        onTap: () => widget.onOpenQuery(query),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _NotesGroupMode { feed, books }

class _NotesPanel extends StatefulWidget {
  const _NotesPanel({
    required this.controller,
    required this.onOpenNote,
    required this.onOpenHighlight,
  });

  final LibraryController controller;
  final void Function(String bookId, String noteId) onOpenNote;
  final void Function(String bookId, String highlightId) onOpenHighlight;

  @override
  State<_NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<_NotesPanel> {
  late final Listenable _dataListenable;
  final TextEditingController _searchController = TextEditingController();
  Timer? _reloadDebounce;
  bool _loading = true;
  Object? _loadError;
  List<NotesItem> _items = const <NotesItem>[];
  _NotesGroupMode _groupMode = _NotesGroupMode.feed;
  final Set<String> _selected = <String>{};
  final Set<String> _selectedColors = <String>{};

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _dataListenable = widget.controller.notesDataListenable;
    _dataListenable.addListener(_onDataChanged);
    _load();
  }

  @override
  void dispose() {
    _dataListenable.removeListener(_onDataChanged);
    _reloadDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    _ensureDataListenable();
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 120), _load);
  }

  void _ensureDataListenable() {
    final next = widget.controller.notesDataListenable;
    if (identical(next, _dataListenable)) {
      return;
    }
    _dataListenable.removeListener(_onDataChanged);
    _dataListenable = next;
    _dataListenable.addListener(_onDataChanged);
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    _ensureDataListenable();
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final items = await widget.controller.loadAllNotesItems();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  List<NotesItem> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    return _items.where((item) {
      if (_selectedColors.isNotEmpty && !_selectedColors.contains(item.color)) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final haystack = <String>[
        item.text,
        item.excerpt,
        item.bookTitle ?? '',
        item.bookAuthor ?? '',
      ].join('\n').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  Future<void> _confirmDeleteSelected() async {
    final selectedItems = _selectedItems();
    if (selectedItems.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить выбранное?'),
        content: Text('Будет удалено: ${selectedItems.length}'),
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
    if (confirmed != true || !mounted) {
      return;
    }
    await widget.controller.deleteNotesItems(selectedItems);
    if (!mounted) {
      return;
    }
    setState(_selected.clear);
  }

  Future<void> _exportSelected() async {
    final selectedItems = _selectedItems();
    if (selectedItems.isEmpty) {
      return;
    }
    await widget.controller.exportNotesItems(selectedItems);
  }

  List<NotesItem> _selectedItems() {
    return _items.where((item) => _selected.contains(item.key)).toList();
  }

  void _toggleSelected(NotesItem item) {
    setState(() {
      if (_selected.contains(item.key)) {
        _selected.remove(item.key);
      } else {
        _selected.add(item.key);
      }
    });
  }

  Future<void> _openItem(NotesItem item) async {
    if (item.type == NotesItemType.freeNote) {
      await _editFreeNote(existing: item);
      return;
    }
    final bookId = item.bookId;
    if (bookId == null) {
      return;
    }
    if (item.type == NotesItemType.note) {
      widget.onOpenNote(bookId, item.id);
      return;
    }
    widget.onOpenHighlight(bookId, item.id);
  }

  Future<void> _previewItem(NotesItem item) async {
    if (item.type == NotesItemType.freeNote) {
      await _editFreeNote(existing: item);
      return;
    }
    final bookId = item.bookId;
    if (bookId == null) {
      return;
    }
    final title = item.bookTitle ?? 'Книга';
    final author = item.bookAuthor;
    final typeLabel =
        item.type == NotesItemType.note ? 'Заметка' : 'Выделение';
    final color = item.color;
    final noteText = item.type == NotesItemType.note ? item.text.trim() : '';
    final excerpt = item.excerpt.trim();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$typeLabel · $title'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  <String>[
                    if (author != null && author.trim().isNotEmpty) author.trim(),
                    if (color.trim().isNotEmpty) 'color=$color',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (noteText.isNotEmpty) ...[
                  Text(noteText),
                  const SizedBox(height: 12),
                ],
                if (excerpt.isNotEmpty) ...[
                  const Text(
                    'Фрагмент',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(excerpt),
                ],
                if (noteText.isEmpty && excerpt.isEmpty)
                  const Text('(без текста)'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openItem(item);
            },
            child: const Text('Перейти'),
          ),
        ],
      ),
    );
  }

  Future<void> _editFreeNote({NotesItem? existing}) async {
    final controller = TextEditingController(text: existing?.text ?? '');
    var selectedColor = markColorOptions.firstWhere(
      (option) => option.key == (existing?.color ?? 'yellow'),
      orElse: () => markColorOptions.first,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'Новая заметка' : 'Редактировать'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Введите заметку',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in markColorOptions)
                    ChoiceChip(
                      label: Text(option.label),
                      selected: option.key == selectedColor.key,
                      avatar: _MarkSwatch(color: option.color),
                      onSelected: (_) {
                        setState(() {
                          selectedColor = option;
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final text = controller.text;
    if (saved != true) {
      return;
    }
    if (existing == null) {
      await widget.controller.addFreeNote(
        text: text,
        color: selectedColor.key,
      );
      return;
    }
    await widget.controller.updateFreeNote(
      id: existing.id,
      text: text,
      color: selectedColor.key,
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Заметки',
            style: Theme.of(context).textTheme.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SegmentedButton<_NotesGroupMode>(
          segments: const [
            ButtonSegment(
              value: _NotesGroupMode.feed,
              icon: Icon(Icons.view_agenda_outlined),
              label: Text('Лента'),
            ),
            ButtonSegment(
              value: _NotesGroupMode.books,
              icon: Icon(Icons.library_books_outlined),
              label: Text('Книги'),
            ),
          ],
          selected: {_groupMode},
          onSelectionChanged: (value) {
            setState(() {
              _groupMode = value.first;
            });
          },
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Новая заметка',
          onPressed: () => _editFreeNote(),
          icon: const Icon(Icons.add),
        ),
        if (_selectionMode) ...[
          IconButton(
            tooltip: 'Экспорт',
            onPressed: _exportSelected,
            icon: const Icon(Icons.archive_outlined),
          ),
          IconButton(
            tooltip: 'Удалить',
            onPressed: _confirmDeleteSelected,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Снять выбор',
            onPressed: () {
              setState(_selected.clear);
            },
            icon: const Icon(Icons.close),
          ),
        ] else
          IconButton(
            tooltip: 'Выбрать',
            onPressed: _filteredItems.isEmpty
                ? null
                : () {
                    setState(() {
                      _selected
                        ..clear()
                        ..add(_filteredItems.first.key);
                    });
                  },
            icon: const Icon(Icons.checklist_outlined),
          ),
      ],
    );
  }

  Widget _buildColorFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in markColorOptions)
          FilterChip(
            label: Text(option.label),
            selected: _selectedColors.contains(option.key),
            avatar: _MarkSwatch(color: option.color),
            onSelected: (_) {
              setState(() {
                if (_selectedColors.contains(option.key)) {
                  _selectedColors.remove(option.key);
                } else {
                  _selectedColors.add(option.key);
                }
              });
            },
          ),
      ],
    );
  }

  Widget _buildList(List<NotesItem> items) {
    if (items.isEmpty) {
      return const Center(child: Text('Пока нет заметок и выделений.'));
    }
    if (_groupMode == _NotesGroupMode.feed) {
      return ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return _NotesTile(
            item: item,
            selected: _selected.contains(item.key),
            selectionMode: _selectionMode,
            onTap: () {
              if (_selectionMode) {
                _toggleSelected(item);
              } else {
                _openItem(item);
              }
            },
            onLongPress: () => _toggleSelected(item),
            onSelectToggle: () => _toggleSelected(item),
            onPreview: _selectionMode ? null : () => _previewItem(item),
          );
        },
      );
    }

    final groups = <String, List<NotesItem>>{};
    for (final item in items) {
      final key = item.bookId ?? '__free__';
      groups.putIfAbsent(key, () => <NotesItem>[]).add(item);
    }
    final orderedKeys = groups.keys.toList()
      ..sort((a, b) {
        final aAt = groups[a]!.first.updatedAt;
        final bAt = groups[b]!.first.updatedAt;
        return bAt.compareTo(aAt);
      });
    final widgets = <Widget>[];
    for (final key in orderedKeys) {
      final groupItems = groups[key]!
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final title = key == '__free__'
          ? 'Без книги'
          : (groupItems.first.bookTitle ?? 'Без названия');
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(
            '$title · ${groupItems.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
      for (final item in groupItems) {
        widgets.add(
          _NotesTile(
            item: item,
            selected: _selected.contains(item.key),
            selectionMode: _selectionMode,
            onTap: () {
              if (_selectionMode) {
                _toggleSelected(item);
              } else {
                _openItem(item);
              }
            },
            onLongPress: () => _toggleSelected(item),
            onSelectToggle: () => _toggleSelected(item),
            onPreview: _selectionMode ? null : () => _previewItem(item),
          ),
        );
        widgets.add(const Divider(height: 1));
      }
    }
    return ListView(children: widgets);
  }

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
          _buildHeader(),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Поиск по заметкам и выделениям',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withAlpha(128),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _buildColorFilters(),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? Center(child: Text('Не удалось загрузить: $_loadError'))
                : _buildList(_filteredItems),
          ),
        ],
      ),
    );
  }
}

class _MarkSwatch extends StatelessWidget {
  const _MarkSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

class _NotesTile extends StatelessWidget {
  const _NotesTile({
    required this.item,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onSelectToggle,
    this.onPreview,
  });

  final NotesItem item;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelectToggle;
  final VoidCallback? onPreview;

  String get _title {
    switch (item.type) {
      case NotesItemType.note:
        final text = item.text.trim();
        final excerpt = item.excerpt.trim();
        if (text.isNotEmpty) {
          return text;
        }
        return excerpt.isEmpty ? '(без текста)' : excerpt;
      case NotesItemType.highlight:
        final excerpt = item.excerpt.trim();
        return excerpt.isEmpty ? '(без текста)' : excerpt;
      case NotesItemType.freeNote:
        final text = item.text.trim();
        return text.isEmpty ? '(без текста)' : text;
    }
  }

  String get _subtitle {
    final date = item.updatedAt
        .toLocal()
        .toIso8601String()
        .replaceFirst('T', ' ');
    final typeLabel = switch (item.type) {
      NotesItemType.note => 'Заметка',
      NotesItemType.highlight => 'Выделение',
      NotesItemType.freeNote => 'Без книги',
    };
    final book = item.type == NotesItemType.freeNote
        ? null
        : (item.bookTitle ?? 'Без названия');
    final parts = <String>[
      typeLabel,
      if (book != null) book,
      date,
    ];
    final excerpt = item.type == NotesItemType.note ? item.excerpt.trim() : '';
    final subtitle = parts.join(' · ');
    return excerpt.isEmpty ? subtitle : '$subtitle\n$excerpt';
  }

  @override
  Widget build(BuildContext context) {
    final swatchColor = markColorForKey(item.color);
    final typeLabel =
        switch (item.type) {
          NotesItemType.note => 'Заметка',
          NotesItemType.highlight => 'Выделение',
          NotesItemType.freeNote => 'Без книги',
        };
    return ListTile(
      title: Row(
        children: [
          _TypeBadge(label: typeLabel),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(
        _subtitle,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      leading: _MarkSwatch(color: swatchColor),
      trailing: selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => onSelectToggle(),
            )
          : onPreview == null
          ? null
          : IconButton(
              tooltip: 'Открыть и прочитать',
              onPressed: onPreview,
              icon: const Icon(Icons.visibility_outlined),
            ),
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(160),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
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
    required this.viewMode,
    required this.onToggleViewMode,
    required this.onToggleSearch,
    required this.onGlobalSearch,
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
  final LibraryViewMode viewMode;
  final VoidCallback onToggleViewMode;
  final VoidCallback onToggleSearch;
  final VoidCallback? onGlobalSearch;
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
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
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
                tooltip: viewMode == LibraryViewMode.list ? 'Плитка' : 'Список',
                onPressed: onToggleViewMode,
                icon: Icon(
                  viewMode == LibraryViewMode.list
                      ? Icons.grid_view_outlined
                      : Icons.view_list_outlined,
                ),
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
                : viewMode == LibraryViewMode.list
                ? ListView.separated(
                    itemCount: books.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
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
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = (constraints.maxWidth / 200)
                          .floor()
                          .clamp(3, 5);
                      return GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.68,
                        ),
                        itemCount: books.length,
                        itemBuilder: (context, index) {
                          final book = books[index];
                          return _BookGridTile(
                            key: ValueKey('library-book-grid-$index'),
                            book: book,
                            selected: book.id == selectedId,
                            onTap: () {
                              onSelect(book.id);
                              onOpen(index);
                            },
                            onDelete: () => onDelete(index),
                          );
                        },
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
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: scheme.error),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Добавлена ${_formatDate(book.addedAt)}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.outline),
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
  const _BookCover({
    required this.title,
    required this.coverPath,
    this.width = 56,
    this.height = 72,
    this.borderRadius = 12,
  });

  final String title;
  final String? coverPath;
  final double width;
  final double height;
  final double borderRadius;

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
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.file(
          coverFile,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _BookCoverPlaceholder(
            initial: initial,
            scheme: scheme,
            width: width,
            height: height,
            borderRadius: borderRadius,
          ),
        ),
      );
    }
    return _BookCoverPlaceholder(
      initial: initial,
      scheme: scheme,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

class _BookCoverPlaceholder extends StatelessWidget {
  const _BookCoverPlaceholder({
    required this.initial,
    required this.scheme,
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final String initial;
  final ColorScheme scheme;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withAlpha(230),
            scheme.tertiaryContainer.withAlpha(204),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
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

class _BookGridTile extends StatelessWidget {
  const _BookGridTile({
    super.key,
    required this.book,
    required this.onTap,
    required this.onDelete,
    this.selected = false,
  });

  final LibraryBookItem book;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selected ? scheme.primaryContainer : scheme.surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: accent.withAlpha(230),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(30),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(10),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _BookCover(
                    title: book.title,
                    coverPath: book.coverPath,
                    width: 120,
                    height: 180,
                    borderRadius: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (book.isMissing)
                  Expanded(
                    child: Text(
                      'Файл отсутствует',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: scheme.error),
                    ),
                  )
                else
                  const Spacer(),
                IconButton(
                  key: ValueKey('library-delete-grid-${book.id}'),
                  onPressed: onDelete,
                  icon: const Icon(Icons.more_horiz, size: 18),
                  tooltip: 'Удалить книгу',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchIndexDiagnosticsCard extends StatefulWidget {
  const _SearchIndexDiagnosticsCard({required this.searchIndex});

  final SearchIndexService searchIndex;

  @override
  State<_SearchIndexDiagnosticsCard> createState() =>
      _SearchIndexDiagnosticsCardState();
}

class _SearchIndexDiagnosticsCardState
    extends State<_SearchIndexDiagnosticsCard> {
  SearchIndexStatus? _status;
  bool _loading = false;
  bool _rebuilding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.searchIndex.status();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _rebuildAll() async {
    if (_rebuilding) {
      return;
    }
    setState(() {
      _rebuilding = true;
      _error = null;
    });
    try {
      await widget.searchIndex.rebuildBooksIndex();
      await widget.searchIndex.rebuildMarksIndex();
      await _refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Индекс перестроен')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: ${error.toString()}')));
    } finally {
      if (mounted) {
        setState(() {
          _rebuilding = false;
        });
      }
    }
  }

  Future<void> _copyError() async {
    final value = (_error ?? _status?.lastError)?.trim();
    if (value == null || value.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Скопировано')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _status;
    final lastError = (_error ?? status?.lastError)?.trim();
    final hasError = lastError != null && lastError.isNotEmpty;

    final captionStyle = Theme.of(context).textTheme.bodySmall;
    return Container(
      constraints: const BoxConstraints(minWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(64),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Search index',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                tooltip: 'Обновить',
                onPressed: _loading ? null : _refresh,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          if (status == null) ...[
            Text(
              'Статус: недоступен',
              style: captionStyle?.copyWith(
                color: hasError ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            Text('Schema: v${status.schemaVersion}', style: captionStyle),
            Text(
              'Rows: books=${status.booksRows ?? 0}, marks=${status.marksRows ?? 0}',
              style: captionStyle,
            ),
            if (status.lastRebuildAt != null)
              Text(
                'Rebuild: ${status.lastRebuildAt!.toLocal()} (${status.lastRebuildMs ?? 0}ms)',
                style: captionStyle,
              ),
            if (status.dbPath != null)
              Text(
                'DB: ${status.dbPath}',
                style: captionStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
          if (hasError) ...[
            const SizedBox(height: 6),
            Text(
              'Ошибка: $lastError',
              style: captionStyle?.copyWith(color: scheme.error),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _rebuilding ? null : _rebuildAll,
                icon: _rebuilding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restart_alt),
                label: Text(_rebuilding ? 'Перестраиваем...' : 'Перестроить'),
              ),
              OutlinedButton.icon(
                onPressed: hasError ? _copyError : null,
                icon: const Icon(Icons.copy),
                label: const Text('Скопировать ошибку'),
              ),
            ],
          ),
        ],
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
    required this.initialAnchor,
    required this.initialSearchQuery,
  });

  final String? bookId;
  final String? initialNoteId;
  final String? initialHighlightId;
  final String? initialAnchor;
  final String? initialSearchQuery;

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
      initialAnchor: initialAnchor,
      initialSearchQuery: initialSearchQuery,
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.'
      '${date.year}';
}
