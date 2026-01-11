import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/core/types/anchor.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class ReaderChapter {
  const ReaderChapter({
    required this.title,
    required this.level,
    required this.paragraphs,
    required this.href,
  });

  final String title;
  final int level;
  final List<String> paragraphs;
  final String? href;
}

class SearchResult {
  const SearchResult({
    required this.chapterIndex,
    required this.chapterHref,
    required this.chapterTitle,
    required this.offset,
    required this.matchLength,
    required this.snippet,
  });

  final int chapterIndex;
  final String chapterHref;
  final String chapterTitle;
  final int offset;
  final int matchLength;
  final String snippet;
}

class ReaderController extends ChangeNotifier {
  ReaderController({LibraryStore? store, bool? perfLogsEnabled})
      : _store = store ?? LibraryStore(),
        _perfLogsEnabled = perfLogsEnabled ?? kDebugMode;

  final LibraryStore _store;
  final bool _perfLogsEnabled;

  static const int _cacheLimit = 3;
  static final Map<String, List<ReaderChapter>> _chapterCache =
      <String, List<ReaderChapter>>{};
  static final List<String> _cacheOrder = <String>[];
  static final Map<String, TocMode> _cacheMode = <String, TocMode>{};

  bool _loading = true;
  String? _error;
  String? _title;
  ReadingPosition? _initialPosition;
  List<ReaderChapter> _chapters = const <ReaderChapter>[];
  List<Highlight> _highlights = const <Highlight>[];
  List<Note> _notes = const <Note>[];
  List<Bookmark> _bookmarks = const <Bookmark>[];
  Bookmark? _bookmark;
  String _searchQuery = '';
  bool _searching = false;
  List<SearchResult> _searchResults = const <SearchResult>[];
  Timer? _searchDebounce;
  int _searchNonce = 0;
  String? _activeBookId;
  TocMode _tocMode = TocMode.official;
  List<_TocEntry> _officialTocEntries = const <_TocEntry>[];
  List<_TocEntry> _generatedTocEntries = const <_TocEntry>[];
  List<TocNode> _tocOfficialNodes = const <TocNode>[];
  List<TocNode> _tocGeneratedNodes = const <TocNode>[];
  Archive? _lastArchive;

  bool get loading => _loading;
  String? get error => _error;
  String? get title => _title;
  ReadingPosition? get initialPosition => _initialPosition;
  List<ReaderChapter> get chapters => _chapters;
  List<Highlight> get highlights => List<Highlight>.unmodifiable(_highlights);
  List<Note> get notes => List<Note>.unmodifiable(_notes);
  List<Bookmark> get bookmarks => List<Bookmark>.unmodifiable(_bookmarks);
  Bookmark? get bookmark => _bookmark;
  String get searchQuery => _searchQuery;
  bool get searching => _searching;
  List<SearchResult> get searchResults =>
      List<SearchResult>.unmodifiable(_searchResults);
  TocMode get tocMode => _tocMode;
  bool get hasGeneratedToc => _tocGeneratedNodes.isNotEmpty;

  Future<void> load(String bookId) async {
    final totalWatch = Stopwatch()..start();
    _logPerf('Reader perf: load start ($bookId)');
    _activeBookId = bookId;
    _setLoading();
    try {
      await _store.init();
      final entry = await _store.getById(bookId);
      if (entry == null) {
        _error = 'Книга не найдена';
        _loading = false;
        notifyListeners();
        return;
      }

      _initialPosition = entry.readingPosition;
      _title = entry.title;
      _tocMode = entry.tocMode;
      _tocOfficialNodes = entry.tocOfficial;
      _tocGeneratedNodes = entry.tocGenerated;
      _highlights = entry.highlights;
      _notes = entry.notes;
      _bookmarks = entry.bookmarks;
      _bookmark = entry.bookmarks.isEmpty ? null : entry.bookmarks.first;

      final file = File(entry.localPath);
      if (!await file.exists()) {
        _error = 'Файл книги недоступен';
        _loading = false;
        notifyListeners();
        return;
      }

      final cached = _chapterCache[bookId];
      final cachedMode = _cacheMode[bookId];
      final hasStoredToc =
          entry.tocOfficial.isNotEmpty || entry.tocGenerated.isNotEmpty;
      if (cached != null && cachedMode == _tocMode && hasStoredToc) {
        _logCache('Reader cache hit ($bookId, chapters=${cached.length})');
        _touchCache(bookId);
        _chapters = cached;
        _loading = false;
        totalWatch.stop();
        _logPerf(
          'Reader perf: time to content ${totalWatch.elapsedMilliseconds}ms',
        );
        notifyListeners();
        return;
      }
      _logCache('Reader cache miss ($bookId)');

      final readWatch = Stopwatch()..start();
      final bytes = await file.readAsBytes();
      readWatch.stop();
      _logPerf(
        'Reader perf: read bytes ${readWatch.elapsedMilliseconds}ms'
        ' (${bytes.length} bytes)',
      );
      Log.d('Reader loading file: ${entry.localPath} (${bytes.length} bytes)');
      final extractWatch = Stopwatch()..start();
      final chapterSources = await _extractChapters(bytes, entry)
          .timeout(const Duration(seconds: 8), onTimeout: () {
        throw Exception('EPUB parse timeout');
      });
      extractWatch.stop();
      _logPerf(
        'Reader perf: extract chapters ${extractWatch.elapsedMilliseconds}ms'
        ' (${chapterSources.length})',
      );
      Log.d('Reader extracted chapters: ${chapterSources.length}');
      final buildWatch = Stopwatch()..start();
      final chapters = _buildChapters(chapterSources);
      buildWatch.stop();
      _logPerf(
        'Reader perf: build chapters ${buildWatch.elapsedMilliseconds}ms'
        ' (${chapters.length})',
      );

      _chapters = chapters;
      _storeCache(bookId, chapters);
      _loading = false;
      totalWatch.stop();
      _logPerf(
        'Reader perf: time to content ${totalWatch.elapsedMilliseconds}ms',
      );
      notifyListeners();
    } catch (e) {
      Log.d('Failed to load book: $e');
      _error = 'Не удалось открыть книгу: $e';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    final bookId = _activeBookId;
    if (bookId == null) {
      return;
    }
    await load(bookId);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void setSearchQuery(String query, {int limit = 50}) {
    _searchQuery = query;
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searching = false;
      _searchResults = const <SearchResult>[];
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();
    final nonce = ++_searchNonce;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final results = searchMatches(trimmed, limit: limit);
      if (nonce != _searchNonce) {
        return;
      }
      _searchResults = results;
      _searching = false;
      notifyListeners();
    });
  }

  List<SearchResult> searchMatches(String query, {int limit = 50}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || _chapters.isEmpty) {
      return const <SearchResult>[];
    }
    final results = <SearchResult>[];
    final needle = trimmed.toLowerCase();
    for (var i = 0; i < _chapters.length; i += 1) {
      final chapter = _chapters[i];
      final text = _chapterSearchText(chapter);
      if (text.isEmpty) {
        continue;
      }
      final lower = text.toLowerCase();
      var start = 0;
      while (results.length < limit) {
        final index = lower.indexOf(needle, start);
        if (index == -1) {
          break;
        }
        final snippet = _buildSnippet(text, index, trimmed.length);
        results.add(
          SearchResult(
            chapterIndex: i,
            chapterHref: chapter.href ?? 'index:$i',
            chapterTitle: chapter.title,
            offset: index,
            matchLength: trimmed.length,
            snippet: snippet,
          ),
        );
        start = index + trimmed.length;
      }
      if (results.length >= limit) {
        break;
      }
    }
    return results;
  }

  Future<bool> addHighlight({
    required int chapterIndex,
    required int startOffset,
    required int endOffset,
    required String excerpt,
    String color = 'yellow',
  }) async {
    final bookId = _activeBookId;
    if (bookId == null || excerpt.trim().isEmpty) {
      return false;
    }
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) {
      return false;
    }
    if (startOffset < 0 || endOffset <= startOffset) {
      return false;
    }
    await _store.init();
    final chapter = _chapters[chapterIndex];
    final chapterHref = chapter.href ?? 'index:$chapterIndex';
    final anchor = Anchor(
      chapterHref: chapterHref,
      offset: startOffset,
    ).toString();
    final now = DateTime.now();
    final highlight = Highlight(
      id: _makeId(),
      bookId: bookId,
      anchor: anchor,
      endOffset: endOffset,
      excerpt: excerpt.trim(),
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await _store.addHighlight(bookId, highlight);
    _highlights = [..._highlights, highlight];
    notifyListeners();
    return true;
  }

  Future<bool> updateNote(String noteId, String noteText) async {
    final bookId = _activeBookId;
    if (bookId == null) {
      return false;
    }
    await _store.init();
    final now = DateTime.now();
    await _store.updateNote(bookId, noteId, noteText, now);
    _notes = _notes
        .map(
          (note) => note.id == noteId
              ? Note(
                  id: note.id,
                  bookId: note.bookId,
                  anchor: note.anchor,
                  endOffset: note.endOffset,
                  excerpt: note.excerpt,
                  noteText: noteText,
                  color: note.color,
                  createdAt: note.createdAt,
                  updatedAt: now,
                )
              : note,
        )
        .toList();
    notifyListeners();
    return true;
  }

  Future<bool> toggleBookmark(ReadingPosition position) async {
    final bookId = _activeBookId;
    if (bookId == null) {
      return false;
    }
    final chapterHref = position.chapterHref;
    final offset = position.offset;
    if (chapterHref == null || offset == null || offset < 0) {
      return false;
    }
    await _store.init();
    if (_bookmarks.isNotEmpty) {
      final toRemove = _bookmarks.first;
      await _store.removeBookmark(bookId, toRemove.id);
      _bookmarks = const <Bookmark>[];
      _bookmark = null;
      notifyListeners();
      return true;
    }
    final anchor = Anchor(
      chapterHref: chapterHref,
      offset: offset,
    ).toString();
    final now = DateTime.now();
    final bookmark = Bookmark(
      id: _makeId(),
      bookId: bookId,
      anchor: anchor,
      label: 'Закладка',
      createdAt: now,
      updatedAt: now,
    );
    await _store.setBookmark(bookId, bookmark);
    _bookmarks = <Bookmark>[bookmark];
    _bookmark = bookmark;
    notifyListeners();
    return true;
  }

  Future<bool> removeBookmark(String bookmarkId) async {
    final bookId = _activeBookId;
    if (bookId == null) {
      return false;
    }
    await _store.init();
    await _store.removeBookmark(bookId, bookmarkId);
    _bookmarks = _bookmarks.where((item) => item.id != bookmarkId).toList();
    _bookmark = _bookmarks.isEmpty ? null : _bookmarks.first;
    notifyListeners();
    return true;
  }

  Future<bool> addNote({
    required int chapterIndex,
    required int startOffset,
    required int endOffset,
    required String excerpt,
    required String text,
    required String color,
  }) async {
    final bookId = _activeBookId;
    if (bookId == null || excerpt.trim().isEmpty || text.trim().isEmpty) {
      return false;
    }
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) {
      return false;
    }
    if (startOffset < 0 || endOffset <= startOffset) {
      return false;
    }
    await _store.init();
    final chapter = _chapters[chapterIndex];
    final chapterHref = chapter.href ?? 'index:$chapterIndex';
    final anchor = Anchor(
      chapterHref: chapterHref,
      offset: startOffset,
    ).toString();
    final now = DateTime.now();
    final note = Note(
      id: _makeId(),
      bookId: bookId,
      anchor: anchor,
      endOffset: endOffset,
      excerpt: excerpt.trim(),
      noteText: text.trim(),
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await _store.addNote(bookId, note);
    _notes = [..._notes, note];
    notifyListeners();
    return true;
  }

  Future<void> removeNote(String noteId) async {
    final bookId = _activeBookId;
    if (bookId == null) {
      return;
    }
    await _store.init();
    await _store.removeNote(bookId, noteId);
    _notes = _notes.where((item) => item.id != noteId).toList();
    notifyListeners();
  }

  Future<void> removeHighlight(String highlightId) async {
    final bookId = _activeBookId;
    if (bookId == null) {
      return;
    }
    await _store.init();
    await _store.removeHighlight(bookId, highlightId);
    _highlights = _highlights.where((item) => item.id != highlightId).toList();
    notifyListeners();
  }

  void _setLoading() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  void _logPerf(String message) {
    if (_perfLogsEnabled) {
      Log.d(message);
    }
  }

  void _logCache(String message) {
    if (kDebugMode) {
      Log.d(message);
    }
  }

  String _makeId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return _formatUuid(bytes);
  }

  String _formatUuid(List<int> bytes) {
    String toHex(int value) => value.toRadixString(16).padLeft(2, '0');
    final chars = bytes.map(toHex).toList();
    return [
      chars.sublist(0, 4).join(),
      chars.sublist(4, 6).join(),
      chars.sublist(6, 8).join(),
      chars.sublist(8, 10).join(),
      chars.sublist(10, 16).join(),
    ].join('-');
  }

  void _storeCache(String bookId, List<ReaderChapter> chapters) {
    _chapterCache[bookId] = List<ReaderChapter>.from(chapters);
    _touchCache(bookId);
    _cacheMode[bookId] = _tocMode;
    if (_cacheOrder.length <= _cacheLimit) {
      return;
    }
    final evicted = _cacheOrder.removeAt(0);
    _chapterCache.remove(evicted);
    _cacheMode.remove(evicted);
  }

  void _touchCache(String bookId) {
    _cacheOrder.remove(bookId);
    _cacheOrder.add(bookId);
  }

  Future<void> setTocMode(TocMode mode) async {
    if (_tocMode == mode) {
      return;
    }
    _tocMode = mode;
    Archive? archive = _lastArchive;
    final bookId = _activeBookId;
    if (archive == null && bookId != null) {
      await _store.init();
      final entry = await _store.getById(bookId);
      if (entry != null) {
        try {
          final bytes = await File(entry.localPath).readAsBytes();
          archive = ZipDecoder().decodeBytes(bytes, verify: false);
          _lastArchive = archive;
        } catch (e) {
          Log.d('Failed to reload archive for toc mode: $e');
        }
      }
    }
    if (archive != null) {
      final entries = _entriesForMode();
      if (entries.isNotEmpty) {
        final chapters = _chaptersFromTocEntries(
          archive,
          entries,
          preferTocTitle: true,
        );
        if (chapters.isNotEmpty) {
          _chapters = _buildChapters(chapters);
          _storeCache(_activeBookId ?? 'unknown', _chapters);
          notifyListeners();
        }
      }
    }
    if (bookId != null) {
      await _store.init();
      final entry = await _store.getById(bookId);
      if (entry != null) {
        await _store.upsert(
          LibraryEntry(
            id: entry.id,
            title: entry.title,
            author: entry.author,
            localPath: entry.localPath,
            coverPath: entry.coverPath,
            addedAt: entry.addedAt,
            fingerprint: entry.fingerprint,
            sourcePath: entry.sourcePath,
            readingPosition: entry.readingPosition,
            progress: entry.progress,
            lastOpenedAt: entry.lastOpenedAt,
            notes: entry.notes,
            highlights: entry.highlights,
            bookmarks: entry.bookmarks,
            tocOfficial: entry.tocOfficial,
            tocGenerated: entry.tocGenerated,
            tocMode: _tocMode,
          ),
        );
      }
    }
    notifyListeners();
  }

  Future<void> saveReadingPosition(
    String bookId,
    ReadingPosition position,
  ) async {
    await _store.init();
    await _store.updateReadingPosition(bookId, position);
  }

  Future<List<_ChapterSource>> _extractChapters(
    List<int> bytes,
    LibraryEntry entry,
  ) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      _lastArchive = archive;
      final tocResult = _buildTocResult(archive);
      _officialTocEntries = tocResult.officialEntries;
      _generatedTocEntries = tocResult.generatedEntries;
      _tocOfficialNodes = tocResult.officialNodes;
      _tocGeneratedNodes = tocResult.generatedNodes;
      final resolvedMode = _resolveTocMode(
        entry,
        tocResult,
      );
      _tocMode = resolvedMode;
      await _storeToc(entry, resolvedMode);
      final entries = _entriesForMode();
      final chapterSources = entries.isNotEmpty
          ? _chaptersFromTocEntries(
              archive,
              entries,
              preferTocTitle: true,
            )
          : const <_ChapterSource>[];
      if (chapterSources.isNotEmpty) {
        return chapterSources;
      }
      final chapters = _chaptersFromArchive(archive);
      if (chapters.isNotEmpty) {
        return chapters;
      }
      throw Exception('Не удалось извлечь главы');
    } catch (e) {
      Log.d('Failed to decode EPUB archive: $e');
      throw Exception('Ошибка парсинга EPUB');
    }
  }

  List<ReaderChapter> _buildChapters(List<_ChapterSource> chapterSources) {
    final chapters = <ReaderChapter>[];
    var totalTextLength = 0;
    for (var i = 0; i < chapterSources.length; i++) {
      final source = chapterSources[i];
      final fallbackTitle = source.fallbackTitle ?? '';
      final rawTitle =
          source.tocTitle ?? _extractChapterTitle(source.html, fallbackTitle);
      final rawText = _toPlainText(source.html);
      final cleanedText = _cleanTextForReading(rawText);
      final derivedTitle = _deriveTitleFromText(cleanedText);
      final title = _normalizeChapterTitle(
        rawTitle,
        i + 1,
        fallbackTitle,
        derivedTitle,
        source.preferTocTitle,
      );
      totalTextLength += cleanedText.length;
      chapters.add(
        ReaderChapter(
          title: title,
          level: source.tocLevel ?? 0,
          paragraphs: _splitParagraphs(cleanedText),
          href: source.href,
        ),
      );
    }
    Log.d('Reader extracted text length: $totalTextLength');
    return chapters;
  }

  List<_TocEntry> _entriesForMode() {
    if (_tocMode == TocMode.generated && _generatedTocEntries.isNotEmpty) {
      return _generatedTocEntries;
    }
    if (_officialTocEntries.isNotEmpty) {
      return _officialTocEntries;
    }
    return _generatedTocEntries;
  }

  TocMode _resolveTocMode(
    LibraryEntry entry,
    _TocParseResult result,
  ) {
    final hasStored =
        entry.tocOfficial.isNotEmpty || entry.tocGenerated.isNotEmpty;
    if (!hasStored) {
      return result.defaultMode;
    }
    if (entry.tocMode == TocMode.generated &&
        result.generatedEntries.isEmpty &&
        result.officialEntries.isNotEmpty) {
      return TocMode.official;
    }
    if (entry.tocMode == TocMode.official &&
        result.officialEntries.isEmpty &&
        result.generatedEntries.isNotEmpty) {
      return TocMode.generated;
    }
    return entry.tocMode;
  }

  Future<void> _storeToc(
    LibraryEntry entry,
    TocMode mode,
  ) async {
    final needsUpdate = !_tocListsEqual(entry.tocOfficial, _tocOfficialNodes) ||
        !_tocListsEqual(entry.tocGenerated, _tocGeneratedNodes) ||
        entry.tocMode != mode;
    if (!needsUpdate) {
      return;
    }
    await _store.upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: entry.progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: entry.notes,
        highlights: entry.highlights,
        bookmarks: entry.bookmarks,
        tocOfficial: _tocOfficialNodes,
        tocGenerated: _tocGeneratedNodes,
        tocMode: mode,
      ),
    );
  }

  bool _tocListsEqual(List<TocNode> first, List<TocNode> second) {
    if (first.length != second.length) {
      return false;
    }
    for (var i = 0; i < first.length; i++) {
      final a = first[i];
      final b = second[i];
      if (a.label != b.label ||
          a.href != b.href ||
          a.fragment != b.fragment ||
          a.level != b.level ||
          a.parentId != b.parentId ||
          a.order != b.order ||
          a.source != b.source) {
        return false;
      }
    }
    return true;
  }
}

class _ChapterSource {
  const _ChapterSource({
    required this.html,
    this.fallbackTitle,
    this.tocTitle,
    this.tocLevel,
    this.href,
    this.preferTocTitle = false,
  });

  final String html;
  final String? fallbackTitle;
  final String? tocTitle;
  final int? tocLevel;
  final String? href;
  final bool preferTocTitle;
}

String _toPlainText(String html) {
  if (html.trim().isEmpty) {
    return '';
  }
  if (_looksLikeXml(html)) {
    try {
      final document = XmlDocument.parse(html);
      final buffer = StringBuffer();
      void walk(XmlNode node) {
        if (node is XmlText) {
          buffer.write(node.value);
          return;
        }
        if (node is XmlElement) {
          final name = node.name.local.toLowerCase();
          if (name == 'script' || name == 'style') {
            return;
          }
          for (final child in node.children) {
            walk(child);
          }
          if (name == 'p' || name == 'br' || name == 'div') {
            buffer.write('\n');
          }
        }
      }
      walk(document);
      return buffer
          .toString()
          .replaceAll(RegExp(r'\s+\n'), '\n')
          .replaceAll(RegExp(r'\n\s+'), '\n')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .trim();
    } catch (e) {
      Log.d('Reader XML parse failed, using text fallback: $e');
    }
  }
  return _stripHtmlToText(html);
}

bool _looksLikeXml(String html) {
  final lower = html.toLowerCase();
  if (lower.contains('<!doctype') || lower.contains('<html')) {
    return false;
  }
  return lower.contains('<?xml') ||
      lower.contains('<fictionbook') ||
      lower.contains('<body');
}

String _stripHtmlToText(String html) {
  var text = html;
  text = text.replaceAll(
    RegExp(r'<(script|style)[^>]*>.*?</\1>',
        dotAll: true, caseSensitive: false),
    '',
  );
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
  text = text.replaceAll(RegExp(r'<[^>]+>', dotAll: true), '');
  text = text.replaceAll('&nbsp;', ' ');
  text = text.replaceAll('&amp;', '&');
  text = text.replaceAll('&lt;', '<');
  text = text.replaceAll('&gt;', '>');
  text = text.replaceAll('&quot;', '"');
  text = text.replaceAll('&#39;', "'");
  final collapsed = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  return collapsed;
}

String _normalizeChapterTitle(
  String title,
  int index,
  String fallback,
  String? derivedTitle,
  bool preferTocTitle,
) {
  final trimmed = title.trim();
  final fallbackResolved = fallbackTitleForIndex(index, fallback);
  if (preferTocTitle && trimmed.isNotEmpty) {
    if (_isNormalizedChapterLabel(trimmed)) {
      return trimmed;
    }
    if (!_looksLikeChapterId(trimmed)) {
      return trimmed;
    }
  }
  if (trimmed.isEmpty || _looksLikeChapterId(trimmed) || trimmed.length <= 3) {
    if (derivedTitle != null &&
        derivedTitle.trim().isNotEmpty &&
        !_looksLikeChapterId(derivedTitle)) {
      return derivedTitle;
    }
    return fallbackResolved;
  }
  if (_isBareChapterTitle(trimmed)) {
    if (preferTocTitle) {
      return trimmed;
    }
    if (derivedTitle != null &&
        derivedTitle.trim().isNotEmpty &&
        !_looksLikeChapterId(derivedTitle)) {
      return derivedTitle;
    }
  }
  if (_looksLikeChapterId(fallbackResolved)) {
    return 'Глава $index';
  }
  return trimmed;
}

String fallbackTitleForIndex(int index, String fallback) {
  final trimmed = fallback.trim();
  if (trimmed.isNotEmpty && !_looksLikeChapterId(trimmed)) {
    return trimmed;
  }
  return 'Глава $index';
}

bool _looksLikeChapterId(String value) {
  final lower = value.toLowerCase().trim();
  if (lower.isEmpty) {
    return false;
  }
  final compact = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final compactNoDash = compact.replaceAll('-', '');
  return RegExp(r'^(ch|chapter)\d+(-\d+)?$').hasMatch(compact) ||
      RegExp(r'^\d+(-\d+)?$').hasMatch(compact) ||
      RegExp(r'^ch\d+(\d+)?$').hasMatch(compactNoDash);
}

String? _deriveTitleFromText(String text) {
  final lines = text.split('\n');
  String? markerLine;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    if (_looksLikeChapterMarker(line)) {
      markerLine ??= line;
      continue;
    }
    if (_looksLikeChapterId(line)) {
      continue;
    }
    if (line.length < 4 || line.length > 90) {
      continue;
    }
    if (markerLine != null && !_looksLikeChapterId(line)) {
      return _combineChapterTitle(markerLine, line);
    }
    return line;
  }
  if (markerLine != null && markerLine.isNotEmpty) {
    return markerLine;
  }
  return null;
}

List<String> _splitParagraphs(String text) {
  final lines = text.split('\n');
  final paragraphs = <String>[];
  final buffer = StringBuffer();
  void flush() {
    final value = buffer.toString().trim();
    if (value.isNotEmpty) {
      paragraphs.add(value);
    }
    buffer.clear();
  }

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (buffer.isNotEmpty) {
      buffer.write(' ');
    }
    buffer.write(line);
  }
  flush();
  return paragraphs;
}

String _cleanTextForReading(String text) {
  final lines = text.split('\n');
  final cleaned = <String>[];
  final maxHeadLines = 30;
  var lineIndex = 0;

  for (final raw in lines) {
    lineIndex++;
    final line = raw.trim();
    if (line.isEmpty) {
      cleaned.add('');
      continue;
    }
    if (_looksLikeChapterId(line) || _looksLikeChapterMarker(line)) {
      continue;
    }
    if (lineIndex <= maxHeadLines && _looksLikeFrontMatter(line)) {
      continue;
    }
    cleaned.add(line);
  }

  return cleaned.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

bool _looksLikeFrontMatter(String line) {
  final lower = line.toLowerCase();
  return lower.contains('©') ||
      lower.contains('copyright') ||
      lower.contains('издательство') ||
      lower.contains('серия') ||
      lower.contains('isbn');
}

bool _looksLikeChapterMarker(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (_looksLikeChapterId(trimmed)) {
    return true;
  }
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('глава') && lower.length <= 10) {
    return true;
  }
  return RegExp(r'^[a-z]{1,3}\d{1,3}$').hasMatch(lower);
}

bool _isNormalizedChapterLabel(String value) {
  final lower = value.trim().toLowerCase();
  return lower == 'пролог' ||
      lower == 'эпилог' ||
      RegExp(r'^глава\s+\d+([\-_.]\d+)?$').hasMatch(lower);
}

bool _isBareChapterTitle(String value) {
  final lower = value.trim().toLowerCase();
  return RegExp(r'^глава\s*\d+([\-_.]\d+)?$').hasMatch(lower) ||
      RegExp(r'^chapter\s*\d+([\-_.]\d+)?$').hasMatch(lower);
}

String _combineChapterTitle(String marker, String title) {
  final cleanMarker = marker.trim();
  final cleanTitle = title.trim();
  if (cleanMarker.isEmpty) {
    return cleanTitle;
  }
  if (cleanTitle.isEmpty) {
    return cleanMarker;
  }
  if (cleanMarker.endsWith('.')) {
    return '$cleanMarker $cleanTitle';
  }
  return '$cleanMarker. $cleanTitle';
}

String _chapterSearchText(ReaderChapter chapter) {
  final buffer = StringBuffer();
  buffer.write(chapter.title);
  for (final paragraph in chapter.paragraphs) {
    buffer.write(paragraph);
  }
  return buffer.toString();
}

String _buildSnippet(String text, int matchIndex, int matchLength) {
  const context = 40;
  final start = max(0, matchIndex - context);
  final end = min(text.length, matchIndex + matchLength + context);
  final raw = text.substring(start, end);
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final prefix = start > 0 ? '…' : '';
  final suffix = end < text.length ? '…' : '';
  return '$prefix$normalized$suffix';
}

String _extractChapterTitle(String html, String fallback) {
  final patterns = <RegExp>[
    RegExp(r'<h1[^>]*>(.*?)</h1>', dotAll: true, caseSensitive: false),
    RegExp(r'<h2[^>]*>(.*?)</h2>', dotAll: true, caseSensitive: false),
    RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(html);
    if (match == null) {
      continue;
    }
    final raw = match.group(1) ?? '';
    final text = _stripHtmlToText(raw).trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return fallback;
}

String? _extractFb2Body(String xml) {
  final start = xml.indexOf('<body');
  if (start == -1) {
    return null;
  }
  final end = xml.indexOf('</body>');
  if (end == -1 || end <= start) {
    return null;
  }
  return xml.substring(start, end + '</body>'.length);
}

List<_ChapterSource> _chaptersFromFb2(String xml) {
  try {
    final doc = XmlDocument.parse(xml);
    XmlElement? body;
    for (final candidate in doc.findAllElements('body')) {
      final name = candidate.getAttribute('name');
      if (name == null || name.toLowerCase() != 'notes') {
        body = candidate;
        break;
      }
    }
    if (body == null) {
      return const <_ChapterSource>[];
    }
    final chapters = <_ChapterSource>[];
    var chapterCounter = 0;
    String? lastTitle;
    void walkSections(Iterable<XmlElement> sections, int depth) {
      for (final section in sections) {
        final rawTitle = _extractFb2SectionTitle(section);
        if (_shouldSkipFb2Title(rawTitle)) {
          walkSections(section.findElements('section'), depth);
          continue;
        }
        final isSpecial = _isFb2Prologue(rawTitle) || _isFb2Epilogue(rawTitle);
        if (!isSpecial) {
          chapterCounter += 1;
        }
        final normalized =
            _normalizeFb2ChapterTitle(rawTitle, chapterCounter, isSpecial);
        if (normalized.isEmpty || normalized == lastTitle) {
          walkSections(section.findElements('section'), depth);
          continue;
        }
        lastTitle = normalized;
        chapters.add(
          _ChapterSource(
            html: section.toXmlString(),
            fallbackTitle: normalized,
            tocTitle: normalized,
            tocLevel: depth,
            href: null,
            preferTocTitle: true,
          ),
        );
        walkSections(section.findElements('section'), depth + 1);
      }
    }

    walkSections(body.findElements('section'), 0);

    return chapters;
  } catch (e) {
    Log.d('Reader failed to parse FB2 sections: $e');
    return const <_ChapterSource>[];
  }
}

String _extractFb2SectionTitle(XmlElement section) {
  final titleNode = _firstElement(section.findElements('title'));
  var titleText = titleNode == null
      ? ''
      : _stripHtmlToText(titleNode.innerXml).trim();
  if (titleText.isNotEmpty) {
    return _normalizeFb2Title(titleText);
  }
  final firstPara = _firstElement(section.findElements('p'));
  if (firstPara == null) {
    return '';
  }
  titleText = _stripHtmlToText(firstPara.innerXml).trim();
  return _normalizeFb2Title(titleText);
}

String _normalizeFb2Title(String title) {
  var value = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.length > 80) {
    value = '${value.substring(0, 77)}...';
  }
  return value;
}

bool _shouldSkipFb2Title(String title) {
  if (title.isEmpty) {
    return true;
  }
  final lower = title.toLowerCase();
  return lower.contains('от автора') ||
      lower.contains('предисловие') ||
      lower.contains('содержание') ||
      lower.contains('copyright') ||
      lower.contains('правооблад') ||
      lower.contains('издательство');
}

bool _isFb2Prologue(String title) {
  final lower = title.toLowerCase().trim();
  return lower == 'пролог' || lower.startsWith('пролог ');
}

bool _isFb2Epilogue(String title) {
  final lower = title.toLowerCase().trim();
  return lower == 'эпилог' || lower.startsWith('эпилог ');
}

bool _looksLikeChapterLabel(String title) {
  final lower = title.toLowerCase().trim();
  if (_isFb2Prologue(lower) || _isFb2Epilogue(lower)) {
    return true;
  }
  if (RegExp(r'^глава\s*\d+').hasMatch(lower)) {
    return true;
  }
  if (RegExp(r'^chapter\s*\d+').hasMatch(lower)) {
    return true;
  }
  return RegExp(r'^\d+$').hasMatch(lower);
}

String _normalizeFb2ChapterTitle(
  String title,
  int chapterIndex,
  bool isSpecial,
) {
  if (isSpecial) {
    if (_isFb2Prologue(title)) {
      return 'Пролог';
    }
    if (_isFb2Epilogue(title)) {
      return 'Эпилог';
    }
  }
  final lower = title.toLowerCase();
  final match = RegExp(r'глава\s*(\d+)', caseSensitive: false).firstMatch(lower);
  if (match != null) {
    return 'Глава ${match.group(1)}';
  }
  if (RegExp(r'^\d+$').hasMatch(title.trim())) {
    return 'Глава ${title.trim()}';
  }
  if (chapterIndex > 0) {
    return 'Глава $chapterIndex';
  }
  return title;
}

List<_ChapterSource> _chaptersFromArchive(Archive archive) {
  final fb2Chapters = _fb2ChaptersFromArchive(archive);
  if (fb2Chapters.isNotEmpty) {
    Log.d('Reader fb2 sections: ${fb2Chapters.length} items');
    return fb2Chapters;
  }

  final spineHrefs = _spineHrefsFromArchive(archive);
  if (spineHrefs.isNotEmpty) {
    Log.d('Reader spine order: ${spineHrefs.length} items');
    final headingEntries = _tocEntriesFromHeadings(archive, spineHrefs);
    if (headingEntries.isNotEmpty) {
      Log.d('Reader toc source: headings (${headingEntries.length})');
      final sources = _chaptersFromTocEntries(
        archive,
        headingEntries,
        preferTocTitle: true,
      );
      if (sources.isNotEmpty) {
        return sources;
      }
    }
    final chapters = <_ChapterSource>[];
    for (final href in spineHrefs) {
      final file = _archiveFileByName(archive, href);
      if (file == null || !file.isFile) {
        continue;
      }
      final content = file.content;
      if (content is! List<int>) {
        continue;
      }
      final decoded = utf8.decode(content, allowMalformed: true).trim();
      if (decoded.isEmpty) {
        continue;
      }
      if (_isFictionBookXml(decoded)) {
        final fb2Chapters = _chaptersFromFb2(decoded);
        if (fb2Chapters.isNotEmpty) {
          chapters.addAll(fb2Chapters);
          break;
        }
        final fb2Body = _extractFb2Body(decoded);
        if (fb2Body != null && fb2Body.trim().isNotEmpty) {
          chapters.add(
            _ChapterSource(
              html: fb2Body,
              fallbackTitle: p.basenameWithoutExtension(href),
              tocLevel: 0,
              href: href,
              preferTocTitle: true,
            ),
          );
          break;
        }
      }
      final textLen = _toPlainText(decoded).length;
      if (_shouldSkipSpineItem(href, textLen)) {
        continue;
      }
      chapters.add(
        _ChapterSource(
          html: decoded,
          fallbackTitle: p.basenameWithoutExtension(href),
          tocLevel: 0,
          href: href,
          preferTocTitle: true,
        ),
      );
    }
    if (chapters.isNotEmpty) {
      return chapters;
    }
  }

  String? best;
  int bestScore = 0;
  void consider(String? html) {
    if (html == null) {
      return;
    }
    final text = _toPlainText(html);
    final score = text.length;
    if (score > bestScore) {
      bestScore = score;
      best = html;
    }
  }

  var htmlCount = 0;
  var fb2Count = 0;
  for (final file in archive.files) {
    if (!file.isFile) {
      continue;
    }
    final name = file.name.toLowerCase();
    final content = file.content;
    if (content is! List<int>) {
      continue;
    }
    if (name.endsWith('.xhtml') || name.endsWith('.html')) {
      htmlCount++;
      final decoded = utf8.decode(content, allowMalformed: true).trim();
      consider(decoded);
      continue;
    }
    if (name.endsWith('.fb2') || name.endsWith('.xml')) {
      fb2Count++;
      final decoded = utf8.decode(content, allowMalformed: true);
      if (decoded.contains('<FictionBook')) {
        final fb2Body = _extractFb2Body(decoded);
        consider(fb2Body);
      }
    }
  }
  Log.d('Reader archive: ${archive.files.length} files, html=$htmlCount, fb2/xml=$fb2Count');
  if (best != null && best!.trim().isNotEmpty) {
    return <_ChapterSource>[
      _ChapterSource(html: best!),
    ];
  }
  return const <_ChapterSource>[];
}

List<_ChapterSource> _fb2ChaptersFromArchive(Archive archive) {
  for (final file in archive.files) {
    if (!file.isFile) {
      continue;
    }
    final name = file.name.toLowerCase();
    if (!name.endsWith('.fb2') && !name.endsWith('.xml')) {
      continue;
    }
    final content = file.content;
    if (content is! List<int>) {
      continue;
    }
    final decoded = _decodeFb2Bytes(content);
    if (!_isFictionBookXml(decoded)) {
      continue;
    }
    final chapters = _chaptersFromFb2(decoded);
    if (chapters.isNotEmpty) {
      return chapters;
    }
  }
  return const <_ChapterSource>[];
}

String _decodeFb2Bytes(List<int> bytes) {
  final header = utf8.decode(
    bytes.take(200).toList(),
    allowMalformed: true,
  ).toLowerCase();
  final match = RegExp(r'''encoding\s*=\s*['"]([^'"]+)['"]''')
      .firstMatch(header);
  final encoding = match?.group(1) ?? '';
  if (encoding.contains('1251') || encoding.contains('cp1251')) {
    Log.d('Reader fb2 encoding: $encoding');
    return _decodeCp1251(bytes);
  }
  if (encoding.contains('utf-8') || encoding.contains('utf8')) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String _decodeCp1251(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    if (byte <= 0x7F) {
      buffer.writeCharCode(byte);
      continue;
    }
    if (byte >= 0xC0) {
      buffer.writeCharCode(0x0410 + (byte - 0xC0));
      continue;
    }
    switch (byte) {
      case 0x80:
        buffer.writeCharCode(0x0402);
        break;
      case 0x81:
        buffer.writeCharCode(0x0403);
        break;
      case 0x82:
        buffer.writeCharCode(0x201A);
        break;
      case 0x83:
        buffer.writeCharCode(0x0453);
        break;
      case 0x84:
        buffer.writeCharCode(0x201E);
        break;
      case 0x85:
        buffer.writeCharCode(0x2026);
        break;
      case 0x86:
        buffer.writeCharCode(0x2020);
        break;
      case 0x87:
        buffer.writeCharCode(0x2021);
        break;
      case 0x88:
        buffer.writeCharCode(0x20AC);
        break;
      case 0x89:
        buffer.writeCharCode(0x2030);
        break;
      case 0x8A:
        buffer.writeCharCode(0x0409);
        break;
      case 0x8B:
        buffer.writeCharCode(0x2039);
        break;
      case 0x8C:
        buffer.writeCharCode(0x040A);
        break;
      case 0x8D:
        buffer.writeCharCode(0x040C);
        break;
      case 0x8E:
        buffer.writeCharCode(0x040B);
        break;
      case 0x8F:
        buffer.writeCharCode(0x040F);
        break;
      case 0x90:
        buffer.writeCharCode(0x0452);
        break;
      case 0x91:
        buffer.writeCharCode(0x2018);
        break;
      case 0x92:
        buffer.writeCharCode(0x2019);
        break;
      case 0x93:
        buffer.writeCharCode(0x201C);
        break;
      case 0x94:
        buffer.writeCharCode(0x201D);
        break;
      case 0x95:
        buffer.writeCharCode(0x2022);
        break;
      case 0x96:
        buffer.writeCharCode(0x2013);
        break;
      case 0x97:
        buffer.writeCharCode(0x2014);
        break;
      case 0x99:
        buffer.writeCharCode(0x2122);
        break;
      case 0x9A:
        buffer.writeCharCode(0x0459);
        break;
      case 0x9B:
        buffer.writeCharCode(0x203A);
        break;
      case 0x9C:
        buffer.writeCharCode(0x045A);
        break;
      case 0x9D:
        buffer.writeCharCode(0x045C);
        break;
      case 0x9E:
        buffer.writeCharCode(0x045B);
        break;
      case 0x9F:
        buffer.writeCharCode(0x045F);
        break;
      case 0xA0:
        buffer.writeCharCode(0x00A0);
        break;
      case 0xA1:
        buffer.writeCharCode(0x040E);
        break;
      case 0xA2:
        buffer.writeCharCode(0x045E);
        break;
      case 0xA3:
        buffer.writeCharCode(0x0408);
        break;
      case 0xA4:
        buffer.writeCharCode(0x00A4);
        break;
      case 0xA5:
        buffer.writeCharCode(0x0490);
        break;
      case 0xA6:
        buffer.writeCharCode(0x00A6);
        break;
      case 0xA7:
        buffer.writeCharCode(0x00A7);
        break;
      case 0xA8:
        buffer.writeCharCode(0x0401);
        break;
      case 0xA9:
        buffer.writeCharCode(0x00A9);
        break;
      case 0xAA:
        buffer.writeCharCode(0x0404);
        break;
      case 0xAB:
        buffer.writeCharCode(0x00AB);
        break;
      case 0xAC:
        buffer.writeCharCode(0x00AC);
        break;
      case 0xAD:
        buffer.writeCharCode(0x00AD);
        break;
      case 0xAE:
        buffer.writeCharCode(0x00AE);
        break;
      case 0xAF:
        buffer.writeCharCode(0x0407);
        break;
      case 0xB0:
        buffer.writeCharCode(0x00B0);
        break;
      case 0xB1:
        buffer.writeCharCode(0x00B1);
        break;
      case 0xB2:
        buffer.writeCharCode(0x0406);
        break;
      case 0xB3:
        buffer.writeCharCode(0x0456);
        break;
      case 0xB4:
        buffer.writeCharCode(0x0491);
        break;
      case 0xB5:
        buffer.writeCharCode(0x00B5);
        break;
      case 0xB6:
        buffer.writeCharCode(0x00B6);
        break;
      case 0xB7:
        buffer.writeCharCode(0x00B7);
        break;
      case 0xB8:
        buffer.writeCharCode(0x0451);
        break;
      case 0xB9:
        buffer.writeCharCode(0x2116);
        break;
      case 0xBA:
        buffer.writeCharCode(0x0454);
        break;
      case 0xBB:
        buffer.writeCharCode(0x00BB);
        break;
      case 0xBC:
        buffer.writeCharCode(0x0458);
        break;
      case 0xBD:
        buffer.writeCharCode(0x0405);
        break;
      case 0xBE:
        buffer.writeCharCode(0x0455);
        break;
      case 0xBF:
        buffer.writeCharCode(0x0457);
        break;
      default:
        buffer.writeCharCode(0xFFFD);
        break;
    }
  }
  return buffer.toString();
}

bool _shouldSkipSpineItem(String href, int textLength) {
  if (textLength >= 120) {
    return false;
  }
  final lower = href.toLowerCase();
  return lower.contains('toc') ||
      lower.contains('nav') ||
      lower.contains('cover');
}

ArchiveFile? _archiveFileByName(Archive archive, String name) {
  final normalized = name.replaceAll('\\', '/');
  final lower = normalized.toLowerCase();
  for (final file in archive.files) {
    if (file.name == normalized || file.name.toLowerCase() == lower) {
      return file;
    }
  }
  return null;
}

String? _findOpfPath(Archive archive) {
  final containerFile = _archiveFileByName(archive, 'META-INF/container.xml');
  if (containerFile == null) {
    return null;
  }
  final content = containerFile.content;
  if (content is! List<int>) {
    return null;
  }
  try {
    final xml = utf8.decode(content, allowMalformed: true);
    final doc = XmlDocument.parse(xml);
    for (final node in doc.findAllElements('rootfile')) {
      final path = node.getAttribute('full-path');
      if (path != null && path.trim().isNotEmpty) {
        return path.trim();
      }
    }
  } catch (e) {
    Log.d('Reader failed to parse container.xml: $e');
  }
  return null;
}

enum _TocSource {
  nav,
  ncx,
  headings,
  spine,
  fb2,
  none,
}

class _TocQuality {
  const _TocQuality({
    required this.total,
    required this.emptyRatio,
    required this.longRatio,
    required this.sentenceRatio,
    required this.chapterRatio,
    required this.hasPrologue,
    required this.hasEpilogue,
  });

  final int total;
  final double emptyRatio;
  final double longRatio;
  final double sentenceRatio;
  final double chapterRatio;
  final bool hasPrologue;
  final bool hasEpilogue;

  double get score {
    var value =
        1.0 - (emptyRatio * 0.6) - (longRatio * 0.3) - (sentenceRatio * 0.2);
    if (value < 0) {
      value = 0;
    }
    return double.parse(value.toStringAsFixed(2));
  }

  bool get preferGenerated =>
      total >= 8 && sentenceRatio >= 0.35 && chapterRatio < 0.35;
}

class _TocCandidate {
  const _TocCandidate({
    required this.source,
    required this.entries,
    required this.quality,
    this.preferTocTitle = false,
  });

  final _TocSource source;
  final List<_TocEntry> entries;
  final _TocQuality quality;
  final bool preferTocTitle;

  static const empty = _TocCandidate(
    source: _TocSource.none,
    entries: <_TocEntry>[],
    quality: _TocQuality(
      total: 0,
      emptyRatio: 0,
      longRatio: 0,
      sentenceRatio: 0,
      chapterRatio: 0,
      hasPrologue: false,
      hasEpilogue: false,
    ),
  );
}

class _TocParseResult {
  const _TocParseResult({
    required this.officialEntries,
    required this.generatedEntries,
    required this.officialNodes,
    required this.generatedNodes,
    required this.defaultMode,
    required this.officialSource,
    required this.generatedSource,
  });

  final List<_TocEntry> officialEntries;
  final List<_TocEntry> generatedEntries;
  final List<TocNode> officialNodes;
  final List<TocNode> generatedNodes;
  final TocMode defaultMode;
  final _TocSource officialSource;
  final _TocSource generatedSource;
}

class _GeneratedToc {
  const _GeneratedToc({
    required this.entries,
    required this.source,
  });

  final List<_TocEntry> entries;
  final _TocSource source;
}

_TocCandidate _buildEpubTocCandidate(Archive archive) {
  final opfPath = _findOpfPath(archive);
  if (opfPath == null) {
    return _TocCandidate.empty;
  }
  final opfFile = _archiveFileByName(archive, opfPath);
  if (opfFile == null || opfFile.content is! List<int>) {
    return _TocCandidate.empty;
  }
  final opfDir = p.posix.dirname(opfPath);
  try {
    final xml = utf8.decode(opfFile.content as List<int>, allowMalformed: true);
    final doc = XmlDocument.parse(xml);
    String? navPath;
    String? ncxPath;
    for (final node in doc.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'item') {
        continue;
      }
      final href = node.getAttribute('href');
      if (href == null) {
        continue;
      }
      final properties = node.getAttribute('properties') ?? '';
      final mediaType = node.getAttribute('media-type') ?? '';
      if (properties.contains('nav')) {
        navPath = p.posix.normalize(p.posix.join(opfDir, href));
      } else if (mediaType == 'application/x-dtbncx+xml') {
        ncxPath = p.posix.normalize(p.posix.join(opfDir, href));
      }
    }

    final navEntries = navPath == null
        ? const <_TocEntry>[]
        : _normalizeTocEntries(_tocEntriesFromNav(archive, navPath));
    final ncxEntries = ncxPath == null
        ? const <_TocEntry>[]
        : _normalizeTocEntries(_tocEntriesFromNcx(archive, ncxPath));
    if (navEntries.isEmpty && ncxEntries.isEmpty) {
      return _TocCandidate.empty;
    }

    if (navEntries.isEmpty) {
      final quality = _evaluateTocQuality(ncxEntries);
      if (quality.preferGenerated) {
        Log.d('Reader toc source rejected: ncx (prefer headings)');
        return _TocCandidate.empty;
      }
      Log.d('Reader toc source: ncx (${ncxEntries.length})');
      return _TocCandidate(
        source: _TocSource.ncx,
        entries: ncxEntries,
        quality: quality,
        preferTocTitle: true,
      );
    }
    if (ncxEntries.isEmpty) {
      final quality = _evaluateTocQuality(navEntries);
      if (quality.preferGenerated) {
        Log.d('Reader toc source rejected: nav (prefer headings)');
        return _TocCandidate.empty;
      }
      Log.d('Reader toc source: nav (${navEntries.length})');
      return _TocCandidate(
        source: _TocSource.nav,
        entries: navEntries,
        quality: quality,
        preferTocTitle: true,
      );
    }

    final navQuality = _evaluateTocQuality(navEntries);
    final ncxQuality = _evaluateTocQuality(ncxEntries);
    final useNav = navQuality.score >= ncxQuality.score;
    final chosen = useNav ? navEntries : ncxEntries;
    final chosenQuality = useNav ? navQuality : ncxQuality;
    if (chosenQuality.preferGenerated) {
      Log.d(
        'Reader toc source rejected: ${useNav ? 'nav' : 'ncx'} '
        '(prefer headings)',
      );
      return _TocCandidate.empty;
    }
    Log.d(
      'Reader toc source: ${useNav ? 'nav' : 'ncx'} '
      '(nav=${navQuality.score}, ncx=${ncxQuality.score})',
    );
    return _TocCandidate(
      source: useNav ? _TocSource.nav : _TocSource.ncx,
      entries: chosen,
      quality: chosenQuality,
      preferTocTitle: true,
    );
  } catch (e) {
    Log.d('Reader failed to parse OPF toc: $e');
  }
  return _TocCandidate.empty;
}

_TocParseResult _buildTocResult(Archive archive) {
  final fb2Nodes = _tocNodesFromFb2Archive(archive);
  if (fb2Nodes.isNotEmpty) {
    return _TocParseResult(
      officialEntries: const <_TocEntry>[],
      generatedEntries: const <_TocEntry>[],
      officialNodes: fb2Nodes,
      generatedNodes: const <TocNode>[],
      defaultMode: TocMode.official,
      officialSource: _TocSource.fb2,
      generatedSource: _TocSource.none,
    );
  }

  final tocCandidate = _buildEpubTocCandidate(archive);
  final officialEntries = tocCandidate.entries;
  final generated = _buildGeneratedEntries(archive);
  final generatedEntries = generated.entries;
  final officialNodes = _tocNodesFromEntries(
    officialEntries,
    _mapTocSource(tocCandidate.source),
  );
  final generatedNodes = _tocNodesFromEntries(
    generatedEntries,
    _mapTocSource(generated.source),
  );
  final defaultMode = officialEntries.isEmpty
      ? TocMode.generated
      : tocCandidate.quality.preferGenerated && generatedEntries.isNotEmpty
          ? TocMode.generated
          : TocMode.official;
  return _TocParseResult(
    officialEntries: officialEntries,
    generatedEntries: generatedEntries,
    officialNodes: officialNodes,
    generatedNodes: generatedNodes,
    defaultMode: defaultMode,
    officialSource: tocCandidate.source,
    generatedSource: generated.source,
  );
}

_GeneratedToc _buildGeneratedEntries(Archive archive) {
  final spineHrefs = _spineHrefsFromArchive(archive);
  if (spineHrefs.isEmpty) {
    return const _GeneratedToc(
      entries: <_TocEntry>[],
      source: _TocSource.none,
    );
  }
  final headingEntries = _tocEntriesFromHeadings(archive, spineHrefs);
  if (headingEntries.isNotEmpty) {
    return _GeneratedToc(
      entries: headingEntries,
      source: _TocSource.headings,
    );
  }
  final entries = <_TocEntry>[];
  var order = 0;
  for (final href in spineHrefs) {
    final file = _archiveFileByName(archive, href);
    if (file == null || !file.isFile) {
      continue;
    }
    final title = p.basenameWithoutExtension(href);
    entries.add(
      _TocEntry(
        title: title.isEmpty ? 'Section ${order + 1}' : title,
        href: href,
        level: 0,
        fragment: null,
      ),
    );
    order += 1;
  }
  return _GeneratedToc(entries: entries, source: _TocSource.spine);
}

TocSource _mapTocSource(_TocSource source) {
  switch (source) {
    case _TocSource.nav:
      return TocSource.nav;
    case _TocSource.ncx:
      return TocSource.ncx;
    case _TocSource.headings:
      return TocSource.headings;
    case _TocSource.spine:
      return TocSource.spine;
    case _TocSource.fb2:
      return TocSource.fb2;
    case _TocSource.none:
      return TocSource.nav;
  }
}

List<TocNode> _tocNodesFromEntries(
  List<_TocEntry> entries,
  TocSource source,
) {
  if (entries.isEmpty) {
    return const <TocNode>[];
  }
  final nodes = <TocNode>[];
  final parentStack = <String>[];
  final counters = <String?, int>{};

  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    var level = entry.level;
    if (level < 0) {
      level = 0;
    }
    if (level > parentStack.length) {
      level = parentStack.length;
    }
    while (parentStack.length > level) {
      parentStack.removeLast();
    }
    final parentId = parentStack.isEmpty ? null : parentStack.last;
    final order = counters[parentId] ?? 0;
    counters[parentId] = order + 1;
    final id = '${source.name}-$index';
    nodes.add(
      TocNode(
        id: id,
        parentId: parentId,
        label: entry.title,
        href: entry.href,
        fragment: entry.fragment,
        level: level,
        order: order,
        source: source,
      ),
    );
    parentStack.add(id);
  }
  return nodes;
}

List<TocNode> _tocNodesFromFb2Archive(Archive archive) {
  for (final file in archive.files) {
    if (!file.isFile) {
      continue;
    }
    final name = file.name.toLowerCase();
    if (!name.endsWith('.fb2') && !name.endsWith('.xml')) {
      continue;
    }
    final content = file.content;
    if (content is! List<int>) {
      continue;
    }
    final decoded = _decodeFb2Bytes(content);
    if (!_isFictionBookXml(decoded)) {
      continue;
    }
    try {
      final doc = XmlDocument.parse(decoded);
      XmlElement? body;
      for (final candidate in doc.findAllElements('body')) {
        final name = candidate.getAttribute('name');
        if (name == null || name.toLowerCase() != 'notes') {
          body = candidate;
          break;
        }
      }
      if (body == null) {
        return const <TocNode>[];
      }
      final nodes = <TocNode>[];
      var idCounter = 0;
      var chapterCounter = 0;
      String? lastTitle;

      void walkSections(
        Iterable<XmlElement> sections,
        String? parentId,
        int depth,
      ) {
        var order = 0;
        for (final section in sections) {
          final rawTitle = _extractFb2SectionTitle(section);
          if (_shouldSkipFb2Title(rawTitle)) {
            walkSections(section.findElements('section'), parentId, depth);
            continue;
          }
          final isSpecial = _isFb2Prologue(rawTitle) || _isFb2Epilogue(rawTitle);
          if (!isSpecial) {
            chapterCounter += 1;
          }
          final normalized =
              _normalizeFb2ChapterTitle(rawTitle, chapterCounter, isSpecial);
          if (normalized.isEmpty || normalized == lastTitle) {
            walkSections(section.findElements('section'), parentId, depth);
            continue;
          }
          lastTitle = normalized;
          final id = 'fb2-$idCounter';
          idCounter += 1;
          final fragment = section.getAttribute('id');
          nodes.add(
            TocNode(
              id: id,
              parentId: parentId,
              label: normalized,
              href: null,
              fragment: fragment,
              level: depth,
              order: order,
              source: TocSource.fb2,
            ),
          );
          order += 1;
          walkSections(section.findElements('section'), id, depth + 1);
        }
      }

      walkSections(body.findElements('section'), null, 0);
      return nodes;
    } catch (e) {
      Log.d('Reader failed to parse FB2 toc: $e');
      return const <TocNode>[];
    }
  }
  return const <TocNode>[];
}

List<_TocEntry> _normalizeTocEntries(List<_TocEntry> entries) {
  if (entries.isEmpty) {
    return entries;
  }
  final filtered = <_TocEntry>[];
  for (final entry in entries) {
    final label = entry.title.trim();
    if (_shouldSkipTocLabel(label)) {
      continue;
    }
    filtered.add(entry);
  }
  final normalized = _maybeNormalizeChapterLabels(filtered);
  if (normalized != null) {
    Log.d('Reader toc normalized labels');
    return normalized;
  }
  return filtered;
}

bool _shouldSkipTocLabel(String label) {
  if (label.isEmpty) {
    return true;
  }
  final lower = label.toLowerCase();
  return lower.contains('от автора') ||
      lower.contains('содержание') ||
      lower.contains('предисловие') ||
      lower.contains('copyright') ||
      lower.contains('правооблад') ||
      lower.contains('издательство');
}

List<_TocEntry>? _maybeNormalizeChapterLabels(List<_TocEntry> entries) {
  if (entries.length < 5) {
    return null;
  }
  var sentenceLike = 0;
  var hasEpilogue = false;
  var hasPrologue = false;
  var chapterLike = 0;
  for (final entry in entries) {
    final label = entry.title;
    if (RegExp(r'[.!?]|—|…').hasMatch(label) && label.length > 30) {
      sentenceLike += 1;
    }
    if (_isFb2Epilogue(label)) {
      hasEpilogue = true;
    }
    if (_isFb2Prologue(label)) {
      hasPrologue = true;
    }
    if (_looksLikeChapterLabel(label)) {
      chapterLike += 1;
    }
  }
  final ratio = sentenceLike / entries.length;
  final chapterRatio = chapterLike / entries.length;
  if (ratio < 0.25) {
    return null;
  }
  if (chapterRatio >= 0.4) {
    return null;
  }
  var chapterCounter = 0;
  final normalized = <_TocEntry>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final raw = entry.title.trim();
    String label;
    final isFirst = i == 0;
    final isLast = i == entries.length - 1;
    if (_isFb2Prologue(raw) || (isFirst && !hasPrologue)) {
      label = 'Пролог';
    } else if (_isFb2Epilogue(raw) || (isLast && hasEpilogue)) {
      label = 'Эпилог';
    } else {
      chapterCounter += 1;
      label = 'Глава $chapterCounter';
    }
    normalized.add(
      _TocEntry(
        title: label,
        href: entry.href,
        level: entry.level,
        fragment: entry.fragment,
      ),
    );
  }
  return normalized;
}

_TocQuality _evaluateTocQuality(List<_TocEntry> entries) {
  if (entries.isEmpty) {
    return const _TocQuality(
      total: 0,
      emptyRatio: 0,
      longRatio: 0,
      sentenceRatio: 0,
      chapterRatio: 0,
      hasPrologue: false,
      hasEpilogue: false,
    );
  }
  var empty = 0;
  var long = 0;
  var sentence = 0;
  var chapterLike = 0;
  var hasPrologue = false;
  var hasEpilogue = false;
  for (final entry in entries) {
    final label = entry.title.trim();
    if (label.isEmpty) {
      empty += 1;
      continue;
    }
    if (label.length > 50) {
      long += 1;
    }
    if (RegExp(r'[.!?]|—|…').hasMatch(label)) {
      sentence += 1;
    }
    if (_looksLikeChapterLabel(label)) {
      chapterLike += 1;
    }
    if (_isFb2Prologue(label)) {
      hasPrologue = true;
    }
    if (_isFb2Epilogue(label)) {
      hasEpilogue = true;
    }
  }
  final total = entries.length.toDouble();
  return _TocQuality(
    total: entries.length,
    emptyRatio: empty / total,
    longRatio: long / total,
    sentenceRatio: sentence / total,
    chapterRatio: chapterLike / total,
    hasPrologue: hasPrologue,
    hasEpilogue: hasEpilogue,
  );
}

List<_TocEntry> _tocEntriesFromNav(Archive archive, String navPath) {
  final navFile = _archiveFileByName(archive, navPath);
  if (navFile == null || navFile.content is! List<int>) {
    return const <_TocEntry>[];
  }
  try {
    final xml = utf8.decode(navFile.content as List<int>, allowMalformed: true);
    final doc = XmlDocument.parse(xml);
    final navDir = p.posix.dirname(navPath);
    final entries = <_TocEntry>[];
    XmlElement? tocNav;
    for (final nav in doc.findAllElements('nav')) {
      final type = nav.getAttribute('type') ??
          nav.getAttribute('epub:type') ??
          '';
      if (type.contains('toc')) {
        tocNav = nav;
        break;
      }
    }
    if (tocNav == null) {
      return entries;
    }

    void walkOl(XmlElement ol, int depth) {
      for (final li in ol.findElements('li')) {
        XmlElement? link = _firstElement(li.findElements('a'));
        link ??= _firstWhereOrNull(
          li.descendants.whereType<XmlElement>(),
          (node) => node.name.local == 'a',
        );
        if (link != null) {
          final href = link.getAttribute('href');
          if (href != null && href.trim().isNotEmpty) {
            final text = _stripHtmlToText(link.innerXml).trim();
            if (text.isNotEmpty) {
              final target = _resolveTocTarget(navDir, href);
              if (target.path.isNotEmpty) {
                entries.add(
                  _TocEntry(
                    title: text,
                    href: target.path,
                    level: depth,
                    fragment: target.fragment,
                  ),
                );
              }
            }
          }
        }
        for (final childOl in li.findElements('ol')) {
          walkOl(childOl, depth + 1);
        }
      }
    }

    final rootOl = _firstElement(
      tocNav.children.whereType<XmlElement>().where(
            (node) => node.name.local == 'ol',
          ),
    );
    if (rootOl != null) {
      walkOl(rootOl, 0);
    }
    return entries;
  } catch (e) {
    Log.d('Reader failed to parse nav toc: $e');
    return const <_TocEntry>[];
  }
}

XmlElement? _firstElement(Iterable<XmlElement> elements) {
  for (final element in elements) {
    return element;
  }
  return null;
}

XmlElement? _firstWhereOrNull(
  Iterable<XmlElement> elements,
  bool Function(XmlElement) test,
) {
  for (final element in elements) {
    if (test(element)) {
      return element;
    }
  }
  return null;
}

List<_TocEntry> _tocEntriesFromNcx(Archive archive, String ncxPath) {
  final ncxFile = _archiveFileByName(archive, ncxPath);
  if (ncxFile == null || ncxFile.content is! List<int>) {
    return const <_TocEntry>[];
  }
  try {
    final xml = utf8.decode(ncxFile.content as List<int>, allowMalformed: true);
    final doc = XmlDocument.parse(xml);
    final ncxDir = p.posix.dirname(ncxPath);
    final entries = <_TocEntry>[];
    void walk(XmlElement navPoint, int depth) {
      final textNode = navPoint
          .findElements('navLabel')
          .expand((node) => node.findElements('text'))
          .cast<XmlElement?>()
          .firstWhere((_) => true, orElse: () => null);
      final contentNode = navPoint
          .findElements('content')
          .cast<XmlElement?>()
          .firstWhere((_) => true, orElse: () => null);
      if (textNode != null && contentNode != null) {
        final label = textNode.innerText.trim();
        final src = contentNode.getAttribute('src');
        if (label.isNotEmpty && src != null && src.trim().isNotEmpty) {
          final target = _resolveTocTarget(ncxDir, src);
          if (target.path.isNotEmpty) {
            entries.add(
              _TocEntry(
                title: label,
                href: target.path,
                level: depth,
                fragment: target.fragment,
              ),
            );
          }
        }
      }
      for (final child in navPoint.findElements('navPoint')) {
        walk(child, depth + 1);
      }
    }

    final navMaps = doc.findAllElements('navMap');
    final navMap = navMaps.isNotEmpty ? navMaps.first : null;
    if (navMap != null) {
      for (final navPoint in navMap.findElements('navPoint')) {
        walk(navPoint, 0);
      }
    }
    return entries;
  } catch (e) {
    Log.d('Reader failed to parse ncx toc: $e');
    return const <_TocEntry>[];
  }
}

class _TocEntry {
  const _TocEntry({
    required this.title,
    required this.href,
    required this.level,
    this.fragment,
  });

  final String title;
  final String href;
  final int level;
  final String? fragment;
}

class _TocTarget {
  const _TocTarget(this.path, this.fragment);

  final String path;
  final String? fragment;
}

_TocTarget _resolveTocTarget(String baseDir, String href) {
  final parts = href.split('#');
  final path = _resolveHref(baseDir, parts.first);
  final fragment = parts.length > 1 ? parts[1].trim() : null;
  return _TocTarget(path, fragment?.isEmpty == true ? null : fragment);
}

class _ParsedHtml {
  const _ParsedHtml({
    required this.fullText,
    required this.fragments,
  });

  final String fullText;
  final Map<String, String> fragments;
}

List<_ChapterSource> _chaptersFromTocEntries(
  Archive archive,
  List<_TocEntry> entries, {
  required bool preferTocTitle,
}) {
  final chapters = <_ChapterSource>[];
  final cache = <String, _ParsedHtml>{};

  for (final entry in entries) {
    if (entry.title.trim().isEmpty || entry.href.trim().isEmpty) {
      continue;
    }
    final file = _archiveFileByName(archive, entry.href);
    if (file == null || !file.isFile) {
      continue;
    }
    final content = file.content;
    if (content is! List<int>) {
      continue;
    }
    final decoded = utf8.decode(content, allowMalformed: true).trim();
    if (decoded.isEmpty) {
      continue;
    }
    if (_isFictionBookXml(decoded)) {
      final fb2Chapters = _chaptersFromFb2(decoded);
      if (fb2Chapters.isNotEmpty) {
        chapters.addAll(fb2Chapters);
        break;
      }
      final fb2Body = _extractFb2Body(decoded);
      if (fb2Body == null || fb2Body.trim().isEmpty) {
        continue;
      }
      chapters.add(
        _ChapterSource(
          html: fb2Body,
          fallbackTitle: p.basenameWithoutExtension(entry.href),
          tocTitle: entry.title,
          tocLevel: entry.level,
          href: entry.href,
          preferTocTitle: preferTocTitle,
        ),
      );
      break;
    }

    final parsed = cache.putIfAbsent(
      entry.href,
      () {
        final fragments = _extractFragmentTexts(decoded, entries, entry.href);
        return _ParsedHtml(
          fullText: _toPlainText(decoded),
          fragments: fragments,
        );
      },
    );

    String text;
    if (entry.fragment != null) {
      final fragmentText = parsed.fragments[entry.fragment!];
      text = fragmentText?.trim().isNotEmpty == true
          ? fragmentText!
          : parsed.fullText;
    } else {
      text = parsed.fullText;
    }
    if (text.trim().isEmpty) {
      continue;
    }
    chapters.add(
      _ChapterSource(
        html: text,
        fallbackTitle: p.basenameWithoutExtension(entry.href),
        tocTitle: entry.title,
        tocLevel: entry.level,
        href: entry.href,
        preferTocTitle: preferTocTitle,
      ),
    );
  }

  return chapters;
}

Map<String, String> _extractFragmentTexts(
  String html,
  List<_TocEntry> entries,
  String href,
) {
  try {
    final fragments = <String>{};
    for (final entry in entries) {
      if (entry.href == href && entry.fragment != null) {
        fragments.add(entry.fragment!);
      }
    }
    if (fragments.isEmpty) {
      return const <String, String>{};
    }
    final doc = XmlDocument.parse(html);
    final buffers = <String, StringBuffer>{
      for (final fragment in fragments) fragment: StringBuffer(),
    };
    String? current;

    void walk(XmlNode node) {
      if (node is XmlElement) {
        final name = node.name.local.toLowerCase();
        if (name == 'script' || name == 'style') {
          return;
        }
        final id = node.getAttribute('id') ?? node.getAttribute('name');
        final previous = current;
        if (id != null && fragments.contains(id)) {
          current = id;
        }
        for (final child in node.children) {
          walk(child);
        }
        if (current != null && _isBlockElement(name)) {
          buffers[current]!.write('\n');
        }
        current = previous;
        return;
      }
      if (node is XmlText && current != null) {
        buffers[current]!.write(node.value);
      }
    }

    walk(doc);
    final result = <String, String>{};
    for (final entry in buffers.entries) {
      result[entry.key] = entry.value.toString();
    }
    return result;
  } catch (_) {
    return const <String, String>{};
  }
}

bool _isBlockElement(String name) {
  switch (name) {
    case 'p':
    case 'div':
    case 'section':
    case 'article':
    case 'header':
    case 'footer':
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
    case 'li':
    case 'br':
      return true;
  }
  return false;
}

List<String> _spineHrefsFromArchive(Archive archive) {
  final opfPath = _findOpfPath(archive);
  if (opfPath == null) {
    return const <String>[];
  }
  final opfFile = _archiveFileByName(archive, opfPath);
  if (opfFile == null || opfFile.content is! List<int>) {
    return const <String>[];
  }
  final opfDir = p.posix.dirname(opfPath);
  try {
    final xml = utf8.decode(opfFile.content as List<int>, allowMalformed: true);
    final doc = XmlDocument.parse(xml);
    final manifest = <String, String>{};
    for (final node in doc.findAllElements('item')) {
      final id = node.getAttribute('id');
      final href = node.getAttribute('href');
      if (id == null || href == null) {
        continue;
      }
      manifest[id] = p.posix.normalize(p.posix.join(opfDir, href));
    }
    final spine = <String>[];
    for (final node in doc.findAllElements('itemref')) {
      final idref = node.getAttribute('idref');
      if (idref == null) {
        continue;
      }
      final href = manifest[idref];
      if (href != null) {
        spine.add(href);
      }
    }
    return spine;
  } catch (e) {
    Log.d('Reader failed to parse spine: $e');
    return const <String>[];
  }
}

List<_TocEntry> _tocEntriesFromHeadings(
  Archive archive,
  List<String> spineHrefs,
) {
  final entries = <_TocEntry>[];
  for (final href in spineHrefs) {
    final file = _archiveFileByName(archive, href);
    if (file == null || !file.isFile) {
      continue;
    }
    final content = file.content;
    if (content is! List<int>) {
      continue;
    }
    final decoded = utf8.decode(content, allowMalformed: true).trim();
    if (decoded.isEmpty) {
      continue;
    }
    final fallback = p.basenameWithoutExtension(href);
    final heading = _extractChapterTitle(decoded, fallback);
    if (heading.trim().isEmpty) {
      continue;
    }
    entries.add(
      _TocEntry(
        title: heading,
        href: href,
        level: 0,
        fragment: null,
      ),
    );
  }
  return entries;
}

String _resolveHref(String baseDir, String href) {
  final normalized = href.replaceAll('\\', '/');
  if (normalized.startsWith('/')) {
    return normalized.substring(1);
  }
  final joined = p.posix.normalize(p.posix.join(baseDir, normalized));
  return joined.startsWith('/') ? joined.substring(1) : joined;
}

bool _isFictionBookXml(String decoded) {
  return decoded.contains('<FictionBook') || decoded.contains('<fictionbook');
}
