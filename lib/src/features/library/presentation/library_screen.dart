import 'dart:io';

import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/library/presentation/library_controller.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_provider.dart';
import 'package:flutter/material.dart';

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
  String? _selectedBookId;
  String? _lastNotice;
  bool _showSearch = false;
  String? _pendingNoteId;
  String? _pendingHighlightId;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
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
                                  separatorBuilder: (context, index) =>
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

  Future<void> _toggleViewMode() async {
    final next = _controller.viewMode == LibraryViewMode.list
        ? LibraryViewMode.grid
        : LibraryViewMode.list;
    await _controller.setViewMode(next);
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
    final viewMode = _controller.viewMode;
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
            tooltip: viewMode == LibraryViewMode.list
                ? 'Плитка'
                : 'Список',
            onPressed: _controller.books.isEmpty ? null : _toggleViewMode,
            icon: Icon(
              viewMode == LibraryViewMode.list
                  ? Icons.grid_view_outlined
                  : Icons.view_list_outlined,
            ),
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
                                    final crossAxisCount =
                                        width >= 600 ? 4 : 3;
                                    return GridView.builder(
                                      padding: const EdgeInsets.all(12),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
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
                  if (index == 1) {
                    _showGlobalSearch();
                  }
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
                  child: _buildSection(
                    filtered: filtered,
                    viewMode: viewMode,
                  ),
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
            onGlobalSearch:
                _controller.books.isEmpty ? null : _showGlobalSearch,
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
                value: controller.syncProvider,
                onChanged: (value) {
                  if (value != null) {
                    controller.setSyncProvider(value);
                  }
                },
                items: const [
                  SyncProvider.googleDrive,
                  SyncProvider.dropbox,
                  SyncProvider.oneDrive,
                  SyncProvider.yandexDisk,
                  SyncProvider.webDav,
                ]
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
                      : 'Синхронизировать сейчас',
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
                oauthConnected ? 'Статус: подключено' : 'Статус: не подключено',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (authError != null) ...[
                const SizedBox(height: 6),
                Text(
                  authError,
                  style: TextStyle(color: scheme.error),
                ),
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
                                : () {
                                    if (isNas) {
                                      _showNasDialog(context, controller);
                                    } else {
                                      controller.connectSyncProvider();
                                    }
                                  },
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
                        OutlinedButton.icon(
                          onPressed: connectionInProgress || !oauthConnected
                              ? null
                              : controller.testSyncConnection,
                          icon: connectionInProgress
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_done),
                          label: const Text('Проверить'),
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
                  label: Text(
                    listingFolders ? 'Загрузка...' : 'Выбрать папку',
                  ),
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
          'Будут удалены event_log.json, state.json и meta.json из облака.',
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

class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({
    required this.title,
    required this.subtitle,
  });

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
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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
                tooltip: viewMode == LibraryViewMode.list
                    ? 'Плитка'
                    : 'Список',
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
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final crossAxisCount =
                                  (constraints.maxWidth / 200).floor().clamp(
                                        3,
                                        5,
                                      );
                              return GridView.builder(
                                padding: const EdgeInsets.all(8),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.error,
                          ),
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
