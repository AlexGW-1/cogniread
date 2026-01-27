import 'package:cogniread/src/features/ai/ai_models.dart';
import 'package:cogniread/src/features/search/presentation/global_search_controller.dart';
import 'package:cogniread/src/features/search/search_index_service.dart';
import 'package:cogniread/src/features/search/search_models.dart';
import 'package:cogniread/src/features/search/semantic/semantic_search_service.dart';
import 'package:flutter/material.dart';

typedef BookTitleResolver = String Function(String bookId);
typedef BookAuthorResolver = String? Function(String bookId);

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({
    super.key,
    required this.onOpen,
    required this.resolveBookTitle,
    required this.resolveBookAuthor,
    this.searchIndex,
    this.initialQuery = '',
    this.embedded = false,
    this.aiConfig = const AiConfig(),
    this.onSaveQuery,
    this.recentQueries = const <String>[],
    this.onClearRecentQueries,
    this.onRemoveRecentQuery,
    this.onOpenFreeNote,
  });

  final void Function(
    String bookId, {
    String? initialNoteId,
    String? initialHighlightId,
    String? initialAnchor,
    String? initialSearchQuery,
  })
  onOpen;

  final BookTitleResolver resolveBookTitle;
  final BookAuthorResolver resolveBookAuthor;
  final SearchIndexService? searchIndex;
  final String initialQuery;
  final bool embedded;
  final AiConfig aiConfig;
  final ValueChanged<String>? onSaveQuery;
  final List<String> recentQueries;
  final VoidCallback? onClearRecentQueries;
  final ValueChanged<String>? onRemoveRecentQuery;
  final ValueChanged<String>? onOpenFreeNote;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen>
    with SingleTickerProviderStateMixin {
  late final GlobalSearchController _controller;
  late final TextEditingController _textController;
  late final TabController _tabController;
  late List<String> _recentQueries;

  void _setQuery(String query) {
    final value = query.trim();
    if (value.isEmpty) {
      return;
    }
    _textController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _controller.setQuery(value);
  }

  void _removeRecentQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    setState(() {
      _recentQueries = _recentQueries.where((q) => q != trimmed).toList();
    });
    widget.onRemoveRecentQuery?.call(trimmed);
  }

  void _clearRecentQueries() {
    if (_recentQueries.isEmpty) {
      return;
    }
    setState(() {
      _recentQueries = <String>[];
    });
    widget.onClearRecentQueries?.call();
  }

  void _commitQuery({bool updateState = true, bool deferCallback = false}) {
    final query = _textController.text.trim();
    if (query.isEmpty) {
      return;
    }
    var updated = <String>[
      query,
      ..._recentQueries.where((item) => item != query),
    ];
    if (updated.length > 50) {
      updated = updated.sublist(0, 50);
    }
    if (updateState && mounted) {
      setState(() {
        _recentQueries = updated;
      });
    } else {
      _recentQueries = updated;
    }
    if (deferCallback) {
      final callback = widget.onSaveQuery;
      if (callback != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          callback(query);
        });
      }
    } else {
      widget.onSaveQuery?.call(query);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = GlobalSearchController(
      searchIndex: widget.searchIndex,
      aiConfig: widget.aiConfig,
    );
    _textController = TextEditingController(text: widget.initialQuery);
    _tabController = TabController(length: 3, vsync: this);
    _recentQueries = List<String>.from(widget.recentQueries);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        return;
      }
      _controller.setTab(_tabForIndex(_tabController.index));
    });
    _controller.init();
    if (widget.initialQuery.trim().isNotEmpty) {
      _controller.setQuery(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _commitQuery(updateState: false, deferCallback: true);
    _tabController.dispose();
    _textController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GlobalSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aiConfig != widget.aiConfig) {
      _controller.setAiConfig(widget.aiConfig);
    }
  }

  GlobalSearchTab _tabForIndex(int index) {
    switch (index) {
      case 1:
        return GlobalSearchTab.notes;
      case 2:
        return GlobalSearchTab.quotes;
      default:
        return GlobalSearchTab.books;
    }
  }

  String _rebuildLabel(SearchIndexBooksRebuildProgress? progress) {
    if (progress == null) {
      return 'Подготовка…';
    }
    if (progress.stage == 'marks') {
      return 'Индексируем заметки и цитаты…';
    }
    final title = progress.currentTitle?.trim();
    final message = progress.message?.trim();
    final total = progress.totalBooks;
    final processed = progress.processedBooks;
    final base = total > 0 ? 'Книги: $processed/$total' : 'Книги: $processed';
    if (message != null && message.isNotEmpty) {
      return '$base · $message';
    }
    if (title == null || title.isEmpty) {
      return base;
    }
    return '$base · $title';
  }

  String _semanticRebuildLabel(SemanticSearchRebuildProgress? progress) {
    if (progress == null) {
      return 'Подготовка эмбеддингов…';
    }
    final title = progress.currentTitle?.trim();
    final message = progress.message?.trim();
    final total = progress.totalItems;
    final processed = progress.processedItems;
    final base =
        total > 0 ? 'Эмбеддинги: $processed/$total' : 'Эмбеддинги: $processed';
    if (message != null && message.isNotEmpty) {
      return '$base · $message';
    }
    if (title == null || title.isEmpty) {
      return base;
    }
    return '$base · $title';
  }

  bool _isSemanticConfigReady(AiConfig config) {
    if (!config.isConfigured) {
      return false;
    }
    final model = config.embeddingModel?.trim();
    if (model != null && model.isNotEmpty) {
      return true;
    }
    final fallback = config.model?.trim();
    return fallback != null && fallback.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final gap = isLandscape ? 8.0 : 12.0;
    final content = SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final query = _controller.query.trim();
          final searching = _controller.searching;
          final mode = _controller.mode;
          final isSemantic = mode == GlobalSearchMode.semantic;
          final rebuilding = isSemantic
              ? _controller.semanticRebuilding
              : _controller.rebuilding;
          final lexicalProgress = _controller.rebuildProgress;
          final semanticProgress = _controller.semanticRebuildProgress;
          final progressValue = isSemantic
              ? semanticProgress?.fraction
              : lexicalProgress?.fraction;
          final cancelingRebuild = isSemantic
              ? _controller.semanticCancelingRebuild
              : _controller.cancelingRebuild;
          final error = isSemantic
              ? (_controller.semanticError ??
                  _controller.semanticStatus?.lastError)
              : (_controller.error ?? _controller.status?.lastError);
          final semanticStatus = _controller.semanticStatus;
          final semanticItems = semanticStatus?.itemsCount ?? 0;
          final semanticConfigReady = _isSemanticConfigReady(widget.aiConfig);
          final showSemanticEmptyState =
              isSemantic &&
              !rebuilding &&
              semanticItems == 0 &&
              (error == null || error.trim().isEmpty);
          final tooShort =
              query.isNotEmpty &&
              query.length < GlobalSearchController.minQueryLength;
          return Padding(
            padding: EdgeInsets.only(
              left: isLandscape ? 12 : 16,
              right: isLandscape ? 12 : 16,
              top: isLandscape ? 8 : 12,
              bottom: (isLandscape ? 8 : 16) + media.viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('global-search-v2-field'),
                  controller: _textController,
                  onChanged: _controller.setQuery,
                  onSubmitted: (_) => _commitQuery(),
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Книги, заметки, цитаты',
                    prefixIcon: Icon(Icons.manage_search),
                    isDense: isLandscape,
                    contentPadding: isLandscape
                        ? const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          )
                        : null,
                  ),
                ),
                SizedBox(height: gap),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<GlobalSearchMode>(
                    segments: const [
                      ButtonSegment(
                        value: GlobalSearchMode.lexical,
                        label: Text('Текстовый'),
                      ),
                      ButtonSegment(
                        value: GlobalSearchMode.semantic,
                        label: Text('Семантический'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) {
                        return;
                      }
                      _controller.setMode(selection.first);
                    },
                  ),
                ),
                SizedBox(height: gap),
                TabBar(
                  controller: _tabController,
                  isScrollable: isLandscape,
                  labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontSize: isLandscape ? 12 : null,
                        fontWeight: FontWeight.w600,
                      ),
                  unselectedLabelStyle:
                      Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontSize: isLandscape ? 12 : null,
                          ),
                  labelPadding: EdgeInsets.symmetric(
                    horizontal: isLandscape ? 12 : 16,
                  ),
                  tabs: const [
                    Tab(text: 'Books'),
                    Tab(text: 'Notes'),
                    Tab(text: 'Quotes'),
                  ],
                ),
                SizedBox(height: gap),
                if (searching) const LinearProgressIndicator(),
                if (rebuilding) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isSemantic ? 'Эмбеддинги' : 'Индексирование',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed:
                                  (cancelingRebuild ||
                                      (!isSemantic &&
                                          lexicalProgress?.stage == 'marks'))
                                  ? null
                                  : (isSemantic
                                        ? _controller.cancelSemanticRebuild
                                        : _controller.cancelRebuild),
                              child: Text(
                                cancelingRebuild ? 'Отмена…' : 'Отменить',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progressValue,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isSemantic
                              ? _semanticRebuildLabel(semanticProgress)
                              : _rebuildLabel(lexicalProgress),
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: gap),
                ],
                if (showSemanticEmptyState) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Семантический индекс не построен',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          semanticConfigReady
                              ? 'Постройте эмбеддинги, чтобы искать по смыслу.'
                              : 'Укажите AI endpoint и модель эмбеддингов в настройках.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (semanticConfigReady) ...[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _controller.rebuildSemanticIndex,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('Построить эмбеддинги'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: gap),
                ],
                if (error != null && error.trim().isNotEmpty) ...[
                  SizedBox(height: isLandscape ? 8 : 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSemantic
                              ? 'Семантический поиск недоступен'
                              : 'Поиск недоступен',
                          style: TextStyle(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          error,
                          style: TextStyle(color: scheme.onErrorContainer),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: rebuilding
                              ? null
                              : (isSemantic
                                    ? (semanticConfigReady
                                          ? _controller.rebuildSemanticIndex
                                          : null)
                                    : _controller.rebuildIndex),
                          icon: Icon(
                            isSemantic
                                ? Icons.auto_awesome
                                : Icons.restart_alt,
                          ),
                          label: Text(
                            isSemantic
                                ? 'Перестроить эмбеддинги'
                                : 'Перестроить индекс',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: gap),
                Expanded(
                  child: query.isEmpty
                      ? _EmptyQueryState(
                          recentQueries: _recentQueries,
                          onPickQuery: _setQuery,
                          onClear: _clearRecentQueries,
                          onRemove: _removeRecentQuery,
                        )
                      : tooShort
                      ? const Center(child: Text('Введите минимум 2 символа.'))
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _BooksResultsList(
                              items: _controller.bookResults,
                              searchQuery: query,
                              onOpen:
                                  (
                                    bookId, {
                                    String? initialNoteId,
                                    String? initialHighlightId,
                                    String? initialAnchor,
                                    String? initialSearchQuery,
                                  }) {
                                    _commitQuery();
                                    widget.onOpen(
                                      bookId,
                                      initialNoteId: initialNoteId,
                                      initialHighlightId: initialHighlightId,
                                      initialAnchor: initialAnchor,
                                      initialSearchQuery: initialSearchQuery,
                                    );
                                  },
                            ),
                            _MarksResultsList(
                              items: _controller.noteResults,
                              label: 'Заметка',
                              resolveBookTitle: widget.resolveBookTitle,
                              resolveBookAuthor: widget.resolveBookAuthor,
                              onOpen:
                                  (
                                    bookId, {
                                    String? initialNoteId,
                                    String? initialHighlightId,
                                    String? initialAnchor,
                                    String? initialSearchQuery,
                                  }) {
                                    _commitQuery();
                                    widget.onOpen(
                                      bookId,
                                      initialNoteId: initialNoteId,
                                      initialHighlightId: initialHighlightId,
                                      initialAnchor: initialAnchor,
                                      initialSearchQuery: initialSearchQuery,
                                    );
                                  },
                              onOpenFreeNote: widget.onOpenFreeNote,
                              searchQuery: query,
                            ),
                            _MarksResultsList(
                              items: _controller.quoteResults,
                              label: 'Цитата',
                              resolveBookTitle: widget.resolveBookTitle,
                              resolveBookAuthor: widget.resolveBookAuthor,
                              onOpen:
                                  (
                                    bookId, {
                                    String? initialNoteId,
                                    String? initialHighlightId,
                                    String? initialAnchor,
                                    String? initialSearchQuery,
                                  }) {
                                    _commitQuery();
                                    widget.onOpen(
                                      bookId,
                                      initialNoteId: initialNoteId,
                                      initialHighlightId: initialHighlightId,
                                      initialAnchor: initialAnchor,
                                      initialSearchQuery: initialSearchQuery,
                                    );
                                  },
                              onOpenFreeNote: widget.onOpenFreeNote,
                              searchQuery: query,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _commitQuery();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Поиск'),
          toolbarHeight: isLandscape ? 48 : null,
        ),
        body: content,
      ),
    );
  }
}

class GlobalSearchSheet extends StatefulWidget {
  const GlobalSearchSheet({
    super.key,
    required this.onOpen,
    required this.resolveBookTitle,
    required this.resolveBookAuthor,
    this.searchIndex,
    this.initialQuery = '',
    this.aiConfig = const AiConfig(),
    this.onSaveQuery,
    this.recentQueries = const <String>[],
    this.onClearRecentQueries,
    this.onRemoveRecentQuery,
    this.onOpenFreeNote,
  });

  final void Function(
    String bookId, {
    String? initialNoteId,
    String? initialHighlightId,
    String? initialAnchor,
    String? initialSearchQuery,
  })
  onOpen;

  final BookTitleResolver resolveBookTitle;
  final BookAuthorResolver resolveBookAuthor;
  final SearchIndexService? searchIndex;
  final String initialQuery;
  final AiConfig aiConfig;
  final ValueChanged<String>? onSaveQuery;
  final List<String> recentQueries;
  final VoidCallback? onClearRecentQueries;
  final ValueChanged<String>? onRemoveRecentQuery;
  final ValueChanged<String>? onOpenFreeNote;

  @override
  State<GlobalSearchSheet> createState() => _GlobalSearchSheetState();
}

class _GlobalSearchSheetState extends State<GlobalSearchSheet>
    with SingleTickerProviderStateMixin {
  late final GlobalSearchController _controller;
  late final TextEditingController _textController;
  late final TabController _tabController;
  late List<String> _recentQueries;

  void _setQuery(String query) {
    final value = query.trim();
    if (value.isEmpty) {
      return;
    }
    _textController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _controller.setQuery(value);
  }

  void _removeRecentQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    setState(() {
      _recentQueries = _recentQueries.where((q) => q != trimmed).toList();
    });
    widget.onRemoveRecentQuery?.call(trimmed);
  }

  void _clearRecentQueries() {
    if (_recentQueries.isEmpty) {
      return;
    }
    setState(() {
      _recentQueries = <String>[];
    });
    widget.onClearRecentQueries?.call();
  }

  void _commitQuery({bool updateState = true, bool deferCallback = false}) {
    final query = _textController.text.trim();
    if (query.isEmpty) {
      return;
    }
    var updated = <String>[
      query,
      ..._recentQueries.where((item) => item != query),
    ];
    if (updated.length > 50) {
      updated = updated.sublist(0, 50);
    }
    if (updateState && mounted) {
      setState(() {
        _recentQueries = updated;
      });
    } else {
      _recentQueries = updated;
    }
    if (deferCallback) {
      final callback = widget.onSaveQuery;
      if (callback != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          callback(query);
        });
      }
    } else {
      widget.onSaveQuery?.call(query);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = GlobalSearchController(
      searchIndex: widget.searchIndex,
      aiConfig: widget.aiConfig,
    );
    _textController = TextEditingController(text: widget.initialQuery);
    _tabController = TabController(length: 3, vsync: this);
    _recentQueries = List<String>.from(widget.recentQueries);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        return;
      }
      _controller.setTab(_tabForIndex(_tabController.index));
    });
    _controller.init();
    if (widget.initialQuery.trim().isNotEmpty) {
      _controller.setQuery(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _commitQuery(updateState: false, deferCallback: true);
    _tabController.dispose();
    _textController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GlobalSearchSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aiConfig != widget.aiConfig) {
      _controller.setAiConfig(widget.aiConfig);
    }
  }

  GlobalSearchTab _tabForIndex(int index) {
    switch (index) {
      case 1:
        return GlobalSearchTab.notes;
      case 2:
        return GlobalSearchTab.quotes;
      default:
        return GlobalSearchTab.books;
    }
  }

  String _rebuildLabel(SearchIndexBooksRebuildProgress? progress) {
    if (progress == null) {
      return 'Подготовка…';
    }
    if (progress.stage == 'marks') {
      return 'Индексируем заметки и цитаты…';
    }
    final title = progress.currentTitle?.trim();
    final message = progress.message?.trim();
    final total = progress.totalBooks;
    final processed = progress.processedBooks;
    final base = total > 0 ? 'Книги: $processed/$total' : 'Книги: $processed';
    if (message != null && message.isNotEmpty) {
      return '$base · $message';
    }
    if (title == null || title.isEmpty) {
      return base;
    }
    return '$base · $title';
  }

  String _semanticRebuildLabel(SemanticSearchRebuildProgress? progress) {
    if (progress == null) {
      return 'Подготовка эмбеддингов…';
    }
    final title = progress.currentTitle?.trim();
    final message = progress.message?.trim();
    final total = progress.totalItems;
    final processed = progress.processedItems;
    final base =
        total > 0 ? 'Эмбеддинги: $processed/$total' : 'Эмбеддинги: $processed';
    if (message != null && message.isNotEmpty) {
      return '$base · $message';
    }
    if (title == null || title.isEmpty) {
      return base;
    }
    return '$base · $title';
  }

  bool _isSemanticConfigReady(AiConfig config) {
    if (!config.isConfigured) {
      return false;
    }
    final model = config.embeddingModel?.trim();
    if (model != null && model.isNotEmpty) {
      return true;
    }
    final fallback = config.model?.trim();
    return fallback != null && fallback.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final query = _controller.query.trim();
          final searching = _controller.searching;
          final mode = _controller.mode;
          final isSemantic = mode == GlobalSearchMode.semantic;
          final rebuilding = isSemantic
              ? _controller.semanticRebuilding
              : _controller.rebuilding;
          final lexicalProgress = _controller.rebuildProgress;
          final semanticProgress = _controller.semanticRebuildProgress;
          final progressValue = isSemantic
              ? semanticProgress?.fraction
              : lexicalProgress?.fraction;
          final cancelingRebuild = isSemantic
              ? _controller.semanticCancelingRebuild
              : _controller.cancelingRebuild;
          final error = isSemantic
              ? (_controller.semanticError ??
                  _controller.semanticStatus?.lastError)
              : (_controller.error ?? _controller.status?.lastError);
          final semanticStatus = _controller.semanticStatus;
          final semanticItems = semanticStatus?.itemsCount ?? 0;
          final semanticConfigReady = _isSemanticConfigReady(widget.aiConfig);
          final showSemanticEmptyState =
              isSemantic &&
              !rebuilding &&
              semanticItems == 0 &&
              (error == null || error.trim().isEmpty);
          final tooShort =
              query.isNotEmpty &&
              query.length < GlobalSearchController.minQueryLength;
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Поиск',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () {
                        _commitQuery();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                TextField(
                  key: const ValueKey('global-search-v2-field'),
                  controller: _textController,
                  onChanged: _controller.setQuery,
                  onSubmitted: (_) => _commitQuery(),
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Книги, заметки, цитаты',
                    prefixIcon: Icon(Icons.manage_search),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<GlobalSearchMode>(
                    segments: const [
                      ButtonSegment(
                        value: GlobalSearchMode.lexical,
                        label: Text('Текстовый'),
                      ),
                      ButtonSegment(
                        value: GlobalSearchMode.semantic,
                        label: Text('Семантический'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) {
                        return;
                      }
                      _controller.setMode(selection.first);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Books'),
                    Tab(text: 'Notes'),
                    Tab(text: 'Quotes'),
                  ],
                ),
                const SizedBox(height: 12),
                if (searching) const LinearProgressIndicator(),
                if (rebuilding) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isSemantic ? 'Эмбеддинги' : 'Индексирование',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed:
                                  (cancelingRebuild ||
                                      (!isSemantic &&
                                          lexicalProgress?.stage == 'marks'))
                                  ? null
                                  : (isSemantic
                                        ? _controller.cancelSemanticRebuild
                                        : _controller.cancelRebuild),
                              child: Text(
                                cancelingRebuild ? 'Отмена…' : 'Отменить',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progressValue,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isSemantic
                              ? _semanticRebuildLabel(semanticProgress)
                              : _rebuildLabel(lexicalProgress),
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (showSemanticEmptyState) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Семантический индекс не построен',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          semanticConfigReady
                              ? 'Постройте эмбеддинги, чтобы искать по смыслу.'
                              : 'Укажите AI endpoint и модель эмбеддингов в настройках.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (semanticConfigReady) ...[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _controller.rebuildSemanticIndex,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('Построить эмбеддинги'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (error != null && error.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSemantic
                              ? 'Семантический поиск недоступен'
                              : 'Поиск недоступен',
                          style: TextStyle(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          error,
                          style: TextStyle(color: scheme.onErrorContainer),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: rebuilding
                              ? null
                              : (isSemantic
                                    ? (semanticConfigReady
                                          ? _controller.rebuildSemanticIndex
                                          : null)
                                    : _controller.rebuildIndex),
                          icon: Icon(
                            isSemantic
                                ? Icons.auto_awesome
                                : Icons.restart_alt,
                          ),
                          label: Text(
                            isSemantic
                                ? 'Перестроить эмбеддинги'
                                : 'Перестроить индекс',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: query.isEmpty
                      ? _EmptyQueryState(
                          recentQueries: _recentQueries,
                          onPickQuery: _setQuery,
                          onClear: _clearRecentQueries,
                          onRemove: _removeRecentQuery,
                        )
                      : tooShort
                      ? const Center(child: Text('Введите минимум 2 символа.'))
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _BooksResultsList(
                              items: _controller.bookResults,
                              searchQuery: query,
                              onClose: () => Navigator.of(context).pop(),
                              onOpen:
                                  (
                                    bookId, {
                                    String? initialNoteId,
                                    String? initialHighlightId,
                                    String? initialAnchor,
                                    String? initialSearchQuery,
                                  }) {
                                    _commitQuery();
                                    widget.onOpen(
                                      bookId,
                                      initialNoteId: initialNoteId,
                                      initialHighlightId: initialHighlightId,
                                      initialAnchor: initialAnchor,
                                      initialSearchQuery: initialSearchQuery,
                                    );
                                  },
                            ),
                            _MarksResultsList(
                              items: _controller.noteResults,
                              label: 'Заметка',
                              resolveBookTitle: widget.resolveBookTitle,
                              resolveBookAuthor: widget.resolveBookAuthor,
                              onClose: () => Navigator.of(context).pop(),
                              onOpen:
                                  (
                                    bookId, {
                                    String? initialNoteId,
                                    String? initialHighlightId,
                                    String? initialAnchor,
                                    String? initialSearchQuery,
                                  }) {
                                    _commitQuery();
                                    widget.onOpen(
                                      bookId,
                                      initialNoteId: initialNoteId,
                                      initialHighlightId: initialHighlightId,
                                      initialAnchor: initialAnchor,
                                      initialSearchQuery: initialSearchQuery,
                                    );
                                  },
                              onOpenFreeNote: widget.onOpenFreeNote,
                              searchQuery: query,
                            ),
                            _MarksResultsList(
                              items: _controller.quoteResults,
                              label: 'Цитата',
                              resolveBookTitle: widget.resolveBookTitle,
                              resolveBookAuthor: widget.resolveBookAuthor,
                              onClose: () => Navigator.of(context).pop(),
                              onOpen:
                                  (
                                    bookId, {
                                    String? initialNoteId,
                                    String? initialHighlightId,
                                    String? initialAnchor,
                                    String? initialSearchQuery,
                                  }) {
                                    _commitQuery();
                                    widget.onOpen(
                                      bookId,
                                      initialNoteId: initialNoteId,
                                      initialHighlightId: initialHighlightId,
                                      initialAnchor: initialAnchor,
                                      initialSearchQuery: initialSearchQuery,
                                    );
                                  },
                              onOpenFreeNote: widget.onOpenFreeNote,
                              searchQuery: query,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BooksResultsList extends StatelessWidget {
  const _BooksResultsList({
    required this.items,
    required this.searchQuery,
    required this.onOpen,
    this.onClose,
  });

  final List<BookTextHit> items;
  final String searchQuery;
  final VoidCallback? onClose;
  final void Function(
    String bookId, {
    String? initialNoteId,
    String? initialHighlightId,
    String? initialAnchor,
    String? initialSearchQuery,
  })
  onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('Ничего не найдено.'));
    }
    final scheme = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(context).textTheme.bodySmall;
    final highlightStyle = baseStyle?.copyWith(
      backgroundColor: scheme.primaryContainer.withAlpha(160),
      color: scheme.onPrimaryContainer,
      fontWeight: FontWeight.w600,
    );
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final subtitleParts = <String>[
          if (item.chapterTitle.trim().isNotEmpty) item.chapterTitle.trim(),
          if (item.bookAuthor.trim().isNotEmpty) item.bookAuthor.trim(),
        ];
        final subtitle = subtitleParts.isEmpty
            ? null
            : subtitleParts.join(' · ');
        final snippet = item.snippet.trim();
        return ListTile(
          title: Text(item.bookTitle.isEmpty ? 'Книга' : item.bookTitle),
          isThreeLine: item.snippet.trim().isNotEmpty,
          leading: const Icon(Icons.menu_book_outlined),
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
          minLeadingWidth: 28,
          minVerticalPadding: 8,
          titleTextStyle: Theme.of(context).textTheme.bodyMedium,
          subtitleTextStyle: Theme.of(context).textTheme.bodySmall,
          subtitle: snippet.isEmpty
              ? subtitle == null
                    ? null
                    : Text(subtitle)
              : Text.rich(
                  TextSpan(
                    children: [
                      if (subtitle != null) ...[
                        TextSpan(text: subtitle),
                        const TextSpan(text: '\n'),
                      ],
                      ..._highlightedSnippetSpans(
                        snippet,
                        style: baseStyle,
                        highlightStyle: highlightStyle,
                      ),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            onClose?.call();
            onOpen(
              item.bookId,
              initialAnchor: item.anchor,
              initialSearchQuery: searchQuery,
            );
          },
        );
      },
    );
  }
}

class _MarksResultsList extends StatelessWidget {
  const _MarksResultsList({
    required this.items,
    required this.label,
    required this.resolveBookTitle,
    required this.resolveBookAuthor,
    required this.onOpen,
    this.onClose,
    this.onOpenFreeNote,
    required this.searchQuery,
  });

  final List<SearchHit> items;
  final String label;
  final BookTitleResolver resolveBookTitle;
  final BookAuthorResolver resolveBookAuthor;
  final VoidCallback? onClose;
  final void Function(
    String bookId, {
    String? initialNoteId,
    String? initialHighlightId,
    String? initialAnchor,
    String? initialSearchQuery,
  })
  onOpen;
  final ValueChanged<String>? onOpenFreeNote;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('Ничего не найдено.'));
    }
    final scheme = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(context).textTheme.bodySmall;
    final highlightStyle = baseStyle?.copyWith(
      backgroundColor: scheme.primaryContainer.withAlpha(160),
      color: scheme.onPrimaryContainer,
      fontWeight: FontWeight.w600,
    );
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final isFreeNote = item.isFreeNote;
        final title = isFreeNote
            ? 'Свободная заметка'
            : resolveBookTitle(item.bookId);
        final author = isFreeNote ? null : resolveBookAuthor(item.bookId);
        final subtitleParts = <String>[
          label,
          if (!isFreeNote && author != null && author.trim().isNotEmpty)
            author.trim(),
        ];
        final subtitle = subtitleParts.isEmpty
            ? null
            : subtitleParts.join(' · ');
        final snippet = item.snippet.trim();
        final hasSnippet = snippet.isNotEmpty;
        return ListTile(
          title: Text(title),
          subtitle: hasSnippet
              ? Text.rich(
                  TextSpan(
                    children: [
                      if (subtitle != null) ...[
                        TextSpan(text: subtitle),
                        const TextSpan(text: '\n'),
                      ],
                      ..._highlightedSnippetSpans(
                        snippet,
                        style: baseStyle,
                        highlightStyle: highlightStyle,
                      ),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                )
              : (subtitle == null
                    ? null
                    : Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )),
          isThreeLine: hasSnippet,
          leading: item.type == SearchHitType.note
              ? const Icon(Icons.sticky_note_2_outlined)
              : const Icon(Icons.format_quote_outlined),
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
          minLeadingWidth: 28,
          minVerticalPadding: 8,
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            if (isFreeNote) {
              onClose?.call();
              onOpenFreeNote?.call(item.markId);
              return;
            }
            onClose?.call();
            onOpen(
              item.bookId,
              initialNoteId: item.type == SearchHitType.note
                  ? item.markId
                  : null,
              initialHighlightId: item.type == SearchHitType.highlight
                  ? item.markId
                  : null,
              initialAnchor: item.anchor,
              initialSearchQuery: searchQuery,
            );
          },
        );
      },
    );
  }
}

List<TextSpan> _highlightedSnippetSpans(
  String snippet, {
  required TextStyle? style,
  required TextStyle? highlightStyle,
}) {
  if (snippet.isEmpty) {
    return const <TextSpan>[];
  }
  final spans = <TextSpan>[];
  final buffer = StringBuffer();
  var highlighted = false;
  void flush() {
    if (buffer.isEmpty) {
      return;
    }
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: highlighted ? highlightStyle : style,
      ),
    );
    buffer.clear();
  }

  for (var i = 0; i < snippet.length; i += 1) {
    final char = snippet[i];
    if (char == '[') {
      flush();
      highlighted = true;
      continue;
    }
    if (char == ']') {
      flush();
      highlighted = false;
      continue;
    }
    buffer.write(char);
  }
  flush();
  return spans;
}

class _EmptyQueryState extends StatelessWidget {
  const _EmptyQueryState({
    required this.recentQueries,
    required this.onPickQuery,
    required this.onClear,
    required this.onRemove,
  });

  final List<String> recentQueries;
  final ValueChanged<String> onPickQuery;
  final VoidCallback onClear;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (recentQueries.isEmpty) {
      return const Center(child: Text('Введите запрос для поиска.'));
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Недавние запросы',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Очистить')),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: recentQueries
              .map(
                (query) => InputChip(
                  label: Text(query),
                  onPressed: () => onPickQuery(query),
                  onDeleted: () => onRemove(query),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}
