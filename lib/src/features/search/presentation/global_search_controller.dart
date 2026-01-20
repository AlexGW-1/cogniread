import 'dart:async';

import 'package:cogniread/src/features/search/search_index_service.dart';
import 'package:cogniread/src/features/search/search_models.dart';
import 'package:flutter/foundation.dart';

enum GlobalSearchTab { books, notes, quotes }

class GlobalSearchController extends ChangeNotifier {
  GlobalSearchController({SearchIndexService? searchIndex})
      : _searchIndex = searchIndex ?? SearchIndexService();

  static const int minQueryLength = 2;

  final SearchIndexService _searchIndex;

  String _query = '';
  GlobalSearchTab _tab = GlobalSearchTab.books;
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
  Timer? _debounce;
  int _nonce = 0;
  bool _autoRebuildRequested = false;

  String get query => _query;
  GlobalSearchTab get tab => _tab;
  bool get searching => _searching;
  bool get rebuilding => _rebuilding;
  bool get cancelingRebuild => _cancelingRebuild;
  String? get error => _error;
  SearchIndexStatus? get status => _status;
  List<BookTextHit> get bookResults => List<BookTextHit>.unmodifiable(_bookResults);
  List<SearchHit> get noteResults => List<SearchHit>.unmodifiable(_noteResults);
  List<SearchHit> get quoteResults => List<SearchHit>.unmodifiable(_quoteResults);
  SearchIndexBooksRebuildProgress? get rebuildProgress => _rebuildProgress;

  Future<void> init() async {
    await _refreshStatus();
    await _maybeAutoRebuild();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rebuildSubscription?.cancel();
    _rebuildHandle?.cancel();
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

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (_rebuilding) {
      _searching = false;
      notifyListeners();
      return;
    }
    if (trimmed.isEmpty) {
      _searching = false;
      _error = null;
      _bookResults = const <BookTextHit>[];
      _noteResults = const <SearchHit>[];
      _quoteResults = const <SearchHit>[];
      notifyListeners();
      return;
    }
    if (trimmed.length < minQueryLength) {
      _searching = false;
      _error = null;
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
      unawaited(_runSearch(trimmed, nonce: nonce));
    });
  }

  Future<void> _runSearch(String trimmed, {required int nonce}) async {
    try {
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
      _searching = false;
      await _refreshStatus();
      notifyListeners();
    } catch (error) {
      if (nonce != _nonce) {
        return;
      }
      _searching = false;
      _error = error.toString();
      await _refreshStatus();
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
    unawaited(rebuildIndex());
  }
}
