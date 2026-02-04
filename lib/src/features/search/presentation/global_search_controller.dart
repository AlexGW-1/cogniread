import 'dart:async';

import 'package:cogniread/src/features/ai/ai_models.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/search/search_index_service.dart';
import 'package:cogniread/src/features/search/search_models.dart';
import 'package:cogniread/src/features/search/semantic/semantic_search_service.dart';
import 'package:flutter/foundation.dart';

enum GlobalSearchTab { books, notes, quotes }

enum GlobalSearchMode { lexical, semantic }

class GlobalSearchController extends ChangeNotifier {
  GlobalSearchController({
    SearchIndexService? searchIndex,
    SemanticSearchService? semanticSearch,
    AiConfig? aiConfig,
  }) : _searchIndex = searchIndex ?? SearchIndexService(),
       _semanticSearch = semanticSearch ?? SemanticSearchService(),
       _aiConfig = aiConfig ?? const AiConfig();

  static const int minQueryLength = 2;

  final SearchIndexService _searchIndex;
  final SemanticSearchService _semanticSearch;
  AiConfig _aiConfig;

  String _query = '';
  GlobalSearchTab _tab = GlobalSearchTab.books;
  GlobalSearchMode _mode = GlobalSearchMode.lexical;
  bool _searching = false;
  bool _rebuilding = false;
  bool _cancelingRebuild = false;
  String? _error;
  SearchIndexStatus? _status;
  List<BookTextHit> _bookResults = const <BookTextHit>[];
  List<SearchHit> _noteResults = const <SearchHit>[];
  List<SearchHit> _quoteResults = const <SearchHit>[];
  SearchIndexBooksRebuildProgress? _rebuildProgress;
  SearchIndexBooksRebuildHandle? _rebuildHandle;
  StreamSubscription<SearchIndexBooksRebuildProgress>? _rebuildSubscription;
  bool _semanticRebuilding = false;
  bool _semanticCancelingRebuild = false;
  String? _semanticError;
  SemanticSearchStatus? _semanticStatus;
  SemanticSearchRebuildProgress? _semanticRebuildProgress;
  SemanticSearchRebuildHandle? _semanticRebuildHandle;
  StreamSubscription<SemanticSearchRebuildProgress>? _semanticSubscription;
  Timer? _debounce;
  int _nonce = 0;
  bool _autoRebuildRequested = false;
  bool _autoSemanticRebuildRequested = false;

  String get query => _query;
  GlobalSearchTab get tab => _tab;
  GlobalSearchMode get mode => _mode;
  bool get searching => _searching;
  bool get rebuilding => _rebuilding;
  bool get cancelingRebuild => _cancelingRebuild;
  String? get error => _error;
  SearchIndexStatus? get status => _status;
  SemanticSearchStatus? get semanticStatus => _semanticStatus;
  bool get semanticRebuilding => _semanticRebuilding;
  bool get semanticCancelingRebuild => _semanticCancelingRebuild;
  SemanticSearchRebuildProgress? get semanticRebuildProgress =>
      _semanticRebuildProgress;
  String? get semanticError => _semanticError;
  List<BookTextHit> get bookResults => List<BookTextHit>.unmodifiable(_bookResults);
  List<SearchHit> get noteResults => List<SearchHit>.unmodifiable(_noteResults);
  List<SearchHit> get quoteResults => List<SearchHit>.unmodifiable(_quoteResults);
  SearchIndexBooksRebuildProgress? get rebuildProgress => _rebuildProgress;

  Future<void> init() async {
    await _refreshStatus();
    await _refreshSemanticStatus();
    await _maybeAutoRebuild();
    await _maybeAutoSemanticRebuild();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rebuildSubscription?.cancel();
    _rebuildHandle?.cancel();
    _semanticSubscription?.cancel();
    _semanticRebuildHandle?.cancel();
    super.dispose();
  }

  void setTab(GlobalSearchTab tab) {
    if (_tab == tab) {
      return;
    }
    _tab = tab;
    notifyListeners();
    if (_query.trim().isNotEmpty) {
      _scheduleSearch(_query);
    }
  }

  void setMode(GlobalSearchMode mode) {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    _error = null;
    _semanticError = null;
    if (mode == GlobalSearchMode.semantic) {
      _autoSemanticRebuildRequested = false;
    }
    notifyListeners();
    if (_query.trim().isNotEmpty) {
      _scheduleSearch(_query);
    }
    if (mode == GlobalSearchMode.semantic) {
      unawaited(_maybeAutoSemanticRebuild());
    }
  }

  void setAiConfig(AiConfig config) {
    _aiConfig = config;
    _semanticError = null;
    _autoSemanticRebuildRequested = false;
    unawaited(
      _refreshSemanticStatus().then((_) {
        notifyListeners();
      }),
    );
    if (_mode == GlobalSearchMode.semantic && _query.trim().isNotEmpty) {
      _scheduleSearch(_query);
    }
  }

  void setQuery(String value) {
    _query = value;
    _scheduleSearch(value);
  }

  Future<void> cancelRebuild() async {
    if (!_rebuilding || _cancelingRebuild) {
      return;
    }
    _cancelingRebuild = true;
    notifyListeners();
    try {
      await _rebuildHandle?.cancel();
    } finally {
      _cancelingRebuild = false;
      notifyListeners();
    }
  }

  Future<void> rebuildIndex() async {
    if (_rebuilding) {
      return;
    }
    _rebuilding = true;
    _cancelingRebuild = false;
    _error = null;
    _rebuildProgress = null;
    notifyListeners();
    try {
      final handle = await _searchIndex.startBooksRebuildInIsolate();
      _rebuildHandle = handle;
      _rebuildSubscription = handle.progress.listen((event) {
        _rebuildProgress = event;
        notifyListeners();
      });
      await handle.done;
      _rebuildProgress = SearchIndexBooksRebuildProgress(
        processedBooks: 0,
        totalBooks: 0,
        stage: 'marks',
        insertedRows: 0,
        elapsedMs: 0,
      );
      notifyListeners();
      await _searchIndex.rebuildMarksIndex();
      await _refreshStatus();
      if (_query.trim().isNotEmpty) {
        await _runSearch(_query, nonce: ++_nonce);
      }
    } catch (error) {
      if (error is StateError && error.message == 'Rebuild canceled') {
        _error = null;
      } else {
        _error = error.toString();
      }
      await _refreshStatus();
    } finally {
      _rebuilding = false;
      _cancelingRebuild = false;
      _rebuildHandle = null;
      await _rebuildSubscription?.cancel();
      _rebuildSubscription = null;
      _rebuildProgress = null;
      notifyListeners();
    }
  }

  Future<void> cancelSemanticRebuild() async {
    if (!_semanticRebuilding || _semanticCancelingRebuild) {
      return;
    }
    _semanticCancelingRebuild = true;
    notifyListeners();
    try {
      await _semanticRebuildHandle?.cancel();
    } finally {
      _semanticCancelingRebuild = false;
      notifyListeners();
    }
  }

  Future<void> rebuildSemanticIndex() async {
    if (_semanticRebuilding) {
      return;
    }
    _semanticRebuilding = true;
    _semanticCancelingRebuild = false;
    _semanticError = null;
    _semanticRebuildProgress = null;
    notifyListeners();
    try {
      final handle = await _semanticSearch.rebuildIndex(_aiConfig);
      _semanticRebuildHandle = handle;
      _semanticSubscription = handle.progress.listen((event) {
        _semanticRebuildProgress = event;
        notifyListeners();
      });
      await handle.done;
      await _refreshSemanticStatus();
      final status = _semanticStatus;
      if (status?.lastError != null && status!.lastError!.trim().isNotEmpty) {
        _semanticError = status.lastError;
      }
      if (_mode == GlobalSearchMode.semantic &&
          _query.trim().isNotEmpty &&
          !_searching) {
        await _runSearch(_query, nonce: ++_nonce);
      }
    } catch (error) {
      if (error is StateError && error.message == 'Rebuild canceled') {
        _semanticError = null;
      } else {
        _semanticError = error.toString();
      }
      await _refreshSemanticStatus();
    } finally {
      _semanticRebuilding = false;
      _semanticCancelingRebuild = false;
      _semanticRebuildHandle = null;
      await _semanticSubscription?.cancel();
      _semanticSubscription = null;
      _semanticRebuildProgress = null;
      notifyListeners();
    }
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if ((_mode == GlobalSearchMode.lexical && _rebuilding) ||
        (_mode == GlobalSearchMode.semantic && _semanticRebuilding)) {
      _searching = false;
      notifyListeners();
      return;
    }
    if (trimmed.isEmpty) {
      _searching = false;
      _error = null;
      _semanticError = null;
      _bookResults = const <BookTextHit>[];
      _noteResults = const <SearchHit>[];
      _quoteResults = const <SearchHit>[];
      notifyListeners();
      return;
    }
    if (trimmed.length < minQueryLength) {
      _searching = false;
      _error = null;
      _semanticError = null;
      _bookResults = const <BookTextHit>[];
      _noteResults = const <SearchHit>[];
      _quoteResults = const <SearchHit>[];
      notifyListeners();
      return;
    }
    _searching = true;
    _error = null;
    notifyListeners();
    final nonce = ++_nonce;
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_runSearch(trimmed, nonce: nonce).catchError((Object error) {
        Log.d('Search failed: $error');
      }));
    });
  }

  Future<void> _runSearch(String trimmed, {required int nonce}) async {
    try {
      if (_mode == GlobalSearchMode.semantic) {
        _error = null;
        switch (_tab) {
          case GlobalSearchTab.books:
            final results = await _semanticSearch.searchBooks(
              trimmed,
              config: _aiConfig,
            );
            if (nonce != _nonce) {
              return;
            }
            _bookResults = results;
            break;
          case GlobalSearchTab.notes:
            final results = await _semanticSearch.searchMarks(
              trimmed,
              onlyType: SearchHitType.note,
              config: _aiConfig,
            );
            if (nonce != _nonce) {
              return;
            }
            _noteResults = results;
            break;
          case GlobalSearchTab.quotes:
            final results = await _semanticSearch.searchMarks(
              trimmed,
              onlyType: SearchHitType.highlight,
              config: _aiConfig,
            );
            if (nonce != _nonce) {
              return;
            }
            _quoteResults = results;
            break;
        }
        _semanticError = null;
        await _refreshSemanticStatus();
      } else {
        switch (_tab) {
          case GlobalSearchTab.books:
            final results = await _searchIndex.searchBooksText(trimmed);
            if (nonce != _nonce) {
              return;
            }
            _bookResults = results;
            break;
          case GlobalSearchTab.notes:
            final results = await _searchIndex.searchMarks(
              trimmed,
              onlyType: SearchHitType.note,
            );
            if (nonce != _nonce) {
              return;
            }
            _noteResults = results;
            break;
          case GlobalSearchTab.quotes:
            final results = await _searchIndex.searchMarks(
              trimmed,
              onlyType: SearchHitType.highlight,
            );
            if (nonce != _nonce) {
              return;
            }
            _quoteResults = results;
            break;
        }
        _error = null;
        await _refreshStatus();
      }
      _searching = false;
      notifyListeners();
    } catch (error) {
      if (nonce != _nonce) {
        return;
      }
      _searching = false;
      if (_mode == GlobalSearchMode.semantic) {
        _error = null;
        _semanticError = error.toString();
        await _refreshSemanticStatus();
      } else {
        _error = error.toString();
        await _refreshStatus();
      }
      notifyListeners();
    }
  }

  Future<void> _refreshStatus() async {
    try {
      _status = await _searchIndex.status();
    } catch (_) {
      _status = null;
    }
  }

  Future<void> _refreshSemanticStatus() async {
    try {
      _semanticStatus = await _semanticSearch.status();
    } catch (_) {
      _semanticStatus = null;
    }
  }

  Future<void> _maybeAutoRebuild() async {
    if (_autoRebuildRequested) {
      return;
    }
    _autoRebuildRequested = true;
    final status = _status;
    final needsRebuild =
        status == null ||
        status.lastError != null ||
        status.booksRows == null ||
        status.booksRows == 0;
    if (!needsRebuild) {
      return;
    }
    try {
      final count = await _searchIndex.libraryBooksCount();
      if (count <= 0) {
        return;
      }
    } catch (_) {
      return;
    }
    unawaited(rebuildIndex().catchError((Object error) {
      Log.d('Rebuild index failed: $error');
    }));
  }

  Future<void> _maybeAutoSemanticRebuild() async {
    if (_autoSemanticRebuildRequested) {
      return;
    }
    if (_mode != GlobalSearchMode.semantic) {
      return;
    }
    _autoSemanticRebuildRequested = true;
    final status = _semanticStatus;
    final needsRebuild =
        status == null ||
        status.lastError != null ||
        status.itemsCount == null ||
        status.itemsCount == 0 ||
        !_semanticSearch.isCompatibleWith(_aiConfig, status);
    if (!needsRebuild) {
      return;
    }
    if (!_aiConfig.isConfigured) {
      return;
    }
    unawaited(rebuildSemanticIndex().catchError((Object error) {
      Log.d('Semantic rebuild failed: $error');
    }));
  }
}
