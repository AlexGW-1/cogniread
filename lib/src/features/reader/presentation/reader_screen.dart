import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:xml/xml.dart';

class _ReaderController extends ChangeNotifier {
  _ReaderController({LibraryStore? store, bool? perfLogsEnabled})
      : _store = store ?? LibraryStore(),
        _perfLogsEnabled = perfLogsEnabled ?? kDebugMode;

  final LibraryStore _store;
  final bool _perfLogsEnabled;

  static const int _cacheLimit = 3;
  static final Map<String, List<_Chapter>> _chapterCache =
      <String, List<_Chapter>>{};
  static final List<String> _cacheOrder = <String>[];

  bool _loading = true;
  String? _error;
  String? _title;
  ReadingPosition? _initialPosition;
  List<_Chapter> _chapters = const <_Chapter>[];
  String? _activeBookId;

  bool get loading => _loading;
  String? get error => _error;
  String? get title => _title;
  ReadingPosition? get initialPosition => _initialPosition;
  List<_Chapter> get chapters => _chapters;

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

      final file = File(entry.localPath);
      if (!await file.exists()) {
        _error = 'Файл книги недоступен';
        _loading = false;
        notifyListeners();
        return;
      }

      final cached = _chapterCache[bookId];
      if (cached != null) {
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
      final chapterSources = await _extractChapters(bytes)
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
      final chapters = <_Chapter>[];
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
        );
        totalTextLength += cleanedText.length;
        chapters.add(
          _Chapter(
            title: title,
            level: source.tocLevel ?? 0,
            paragraphs: _splitParagraphs(cleanedText),
            href: source.href,
          ),
        );
      }
      buildWatch.stop();
      _logPerf(
        'Reader perf: build chapters ${buildWatch.elapsedMilliseconds}ms'
        ' (${chapters.length})',
      );
      Log.d('Reader extracted text length: $totalTextLength');

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

  void retry() {
    final bookId = _activeBookId;
    if (bookId == null) {
      return;
    }
    load(bookId);
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

  void _storeCache(String bookId, List<_Chapter> chapters) {
    _chapterCache[bookId] = List<_Chapter>.from(chapters);
    _touchCache(bookId);
    if (_cacheOrder.length <= _cacheLimit) {
      return;
    }
    final evicted = _cacheOrder.removeAt(0);
    _chapterCache.remove(evicted);
  }

  void _touchCache(String bookId) {
    _cacheOrder.remove(bookId);
    _cacheOrder.add(bookId);
  }

  Future<void> saveReadingPosition(
    String bookId,
    ReadingPosition position,
  ) async {
    await _store.init();
    await _store.updateReadingPosition(bookId, position);
  }

  Future<List<_ChapterSource>> _extractChapters(List<int> bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final chapters = _chaptersFromArchive(archive);
      if (chapters.isNotEmpty) {
        return chapters;
      }
    } catch (e) {
      Log.d('Failed to decode EPUB archive: $e');
    }
    return const <_ChapterSource>[
      _ChapterSource(
        html: 'Не удалось извлечь текст книги. См. логи в консоли (CogniRead).',
        fallbackTitle: 'Ошибка',
      ),
    ];
  }
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.bookId,
    this.embedded = false,
  });

  final String bookId;
  final bool embedded;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final ScrollOffsetController _scrollOffsetController =
      ScrollOffsetController();
  late final _ReaderController _controller;
  late final VoidCallback _controllerListener;
  ReadingPosition? _initialPosition;
  Timer? _positionDebounce;
  bool _didRestore = false;
  int _restoreAttempts = 0;
  double _viewportExtent = 0;

  @override
  void initState() {
    super.initState();
    _controller = _ReaderController();
    _controllerListener = () {
      if (!mounted) {
        return;
      }
      setState(() {
        _initialPosition ??= _controller.initialPosition;
      });
      _scheduleRestorePosition();
    };
    _controller.addListener(_controllerListener);
    _itemPositionsListener.itemPositions.addListener(_onScroll);
    _controller.load(widget.bookId);
  }

  @override
  void dispose() {
    _positionDebounce?.cancel();
    _persistReadingPosition();
    _controller.removeListener(_controllerListener);
    _controller.dispose();
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (_controller.loading || _controller.chapters.isEmpty) {
      return;
    }
    _positionDebounce?.cancel();
    _positionDebounce = Timer(
      const Duration(milliseconds: 500),
      _persistReadingPosition,
    );
  }

  void _scheduleRestorePosition() {
    if (_didRestore || _initialPosition == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreReadingPosition();
    });
  }

  void _restoreReadingPosition() {
    if (_didRestore || _initialPosition == null) {
      return;
    }
    if (!_itemScrollController.isAttached) {
      _retryRestore();
      return;
    }
    final index = _resolveChapterIndex(_initialPosition!);
    if (index == null ||
        index < 0 ||
        index >= _controller.chapters.length) {
      _didRestore = true;
      return;
    }
    final itemIndex = _itemIndexForChapter(index);
    if (itemIndex == null) {
      _didRestore = true;
      return;
    }
    _itemScrollController.jumpTo(index: itemIndex);
    final offsetWithin = _initialPosition?.offset ?? 0;
    if (offsetWithin > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollOffsetController.animateScroll(
          offset: offsetWithin.toDouble(),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
        );
      });
    }
    _didRestore = true;
  }

  void _retryRestore() {
    _restoreAttempts += 1;
    if (_restoreAttempts > 5) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreReadingPosition();
    });
  }

  int? _resolveChapterIndex(ReadingPosition position) {
    final chapterHref = position.chapterHref;
    if (chapterHref == null || chapterHref.isEmpty) {
      return null;
    }
    if (chapterHref.startsWith('index:')) {
      return int.tryParse(chapterHref.substring('index:'.length));
    }
    final index =
        _controller.chapters.indexWhere((chapter) => chapter.href == chapterHref);
    return index == -1 ? null : index;
  }

  Future<void> _persistReadingPosition() async {
    if (_controller.loading ||
        _controller.chapters.isEmpty ||
        _itemPositionsListener.itemPositions.value.isEmpty) {
      return;
    }
    final position = _computeReadingPosition();
    if (position == null) {
      return;
    }
    await _controller.saveReadingPosition(widget.bookId, position);
  }

  ReadingPosition? _computeReadingPosition() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      return null;
    }
    final visible = positions.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final active = visible.firstWhere(
      (pos) => pos.itemLeadingEdge <= 0 && pos.itemTrailingEdge > 0,
      orElse: () => visible.first,
    );
    final currentItemIndex = active.index;

    final chapterIndex = currentItemIndex;
    if (chapterIndex < 0 || chapterIndex >= _controller.chapters.length) {
      return null;
    }
    final chapter = _controller.chapters[chapterIndex];
    final chapterHref = chapter.href ?? 'index:$chapterIndex';
    final offsetWithin = _viewportExtent <= 0
        ? 0
        : (-active.itemLeadingEdge * _viewportExtent).round();
    return ReadingPosition(
      chapterHref: chapterHref,
      anchor: null,
      offset: offsetWithin < 0 ? 0 : offsetWithin,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasToc = _controller.chapters.length > 1;
    final body = _buildBody(context);
    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_controller.title ?? 'Reader'),
        actions: [
          IconButton(
            tooltip: 'Оглавление',
            onPressed: hasToc ? _showToc : null,
            icon: const Icon(Icons.list),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasToc = _controller.chapters.length > 1;
    final readerSurface = scheme.surface.withAlpha(242);
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: readerSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: _controller.loading
              ? const Center(child: CircularProgressIndicator())
              : _controller.error != null
                  ? _ReaderErrorPanel(
                      message: _controller.error!,
                      onRetry: _controller.retry,
                    )
                  : _controller.chapters.isEmpty
                      ? const Center(
                          child: Text('Нет данных для отображения'),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ReaderHeader(
                              title: _controller.title ?? 'Reader',
                              hasToc: hasToc,
                              onTocTap: _showToc,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  _viewportExtent = constraints.maxHeight;
                                  return SelectionArea(
                                    child: ScrollablePositionedList.builder(
                                      itemScrollController:
                                          _itemScrollController,
                                      itemPositionsListener:
                                          _itemPositionsListener,
                                      scrollOffsetController:
                                          _scrollOffsetController,
                                      itemCount: _controller.chapters.length,
                                      itemBuilder: (context, index) {
                                        final chapter =
                                            _controller.chapters[index];
                                        return _ChapterContent(
                                          chapter: chapter,
                                          dividerColor: scheme.outlineVariant,
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
        ),
      ),
    );
    final wrapped = widget.embedded ? content : SafeArea(child: content);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.surfaceContainerHighest.withAlpha(64),
            scheme.surface.withAlpha(13),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: wrapped,
    );
  }

  void _showToc() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Оглавление',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _exportToc,
                      child: const Text('Экспорт'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: _controller.chapters.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final chapter = _controller.chapters[index];
                    final indent = 16.0 + (chapter.level * 18.0);
                    return ListTile(
                      contentPadding: EdgeInsets.only(
                        left: indent,
                        right: 16,
                        top: 4,
                        bottom: 4,
                      ),
                      title: Text(chapter.title),
                      onTap: () {
                        Navigator.of(context).pop();
                        _scrollToChapter(index);
                      },
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

  Future<void> _exportToc() async {
    if (_controller.chapters.isEmpty) {
      return;
    }
    final buffer = StringBuffer();
    for (final chapter in _controller.chapters) {
      final indent = '  ' * chapter.level;
      buffer.writeln('$indent${chapter.title}');
    }
    final safeTitle = _sanitizeFileName(_controller.title ?? 'toc');
    final fileName = 'cogniread_toc_$safeTitle.txt';
    final appSupport = await getApplicationSupportDirectory();
    var writtenPath = '';
    Future<bool> tryWrite(String path) async {
      try {
        await File(path).writeAsString(buffer.toString());
        return true;
      } catch (e) {
        Log.d('TOC export failed: $path ($e)');
        return false;
      }
    }

    final candidates = <String>[
      p.join(appSupport.path, fileName),
      p.join(Directory.systemTemp.path, fileName),
    ];

    for (final candidate in candidates) {
      if (await tryWrite(candidate)) {
        writtenPath = candidate;
        break;
      }
    }

    if (writtenPath.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось экспортировать оглавление.')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Оглавление экспортировано: $writtenPath')),
    );
  }

  String _sanitizeFileName(String value) {
    final cleaned =
        value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').trim();
    return cleaned.isEmpty ? 'toc' : cleaned;
  }

  void _scrollToChapter(int index) {
    if (index < 0 || index >= _controller.chapters.length) {
      return;
    }
    final itemIndex = _itemIndexForChapter(index);
    if (itemIndex == null) {
      return;
    }
    _itemScrollController.scrollTo(
      index: itemIndex,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  int? _itemIndexForChapter(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _controller.chapters.length) {
      return null;
    }
    return chapterIndex;
  }
}

class _Chapter {
  const _Chapter({
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

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
    );
  }
}

class _ReaderErrorPanel extends StatelessWidget {
  const _ReaderErrorPanel({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterContent extends StatelessWidget {
  const _ChapterContent({
    required this.chapter,
    required this.dividerColor,
  });

  final _Chapter chapter;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: _ChapterHeader(
              title: chapter.title,
            ),
          ),
          for (final paragraph in chapter.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                paragraph,
                textAlign: TextAlign.justify,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.65,
                  fontFamily: 'Georgia',
                  fontFamilyFallback: [
                    'Times New Roman',
                    'Times',
                    'serif',
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(
              height: 32,
              color: dividerColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.title,
    required this.hasToc,
    required this.onTocTap,
  });

  final String title;
  final bool hasToc;
  final VoidCallback onTocTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Оглавление',
          onPressed: hasToc ? onTocTap : null,
          icon: Icon(Icons.list, color: scheme.primary),
        ),
      ],
    );
  }
}

class _ChapterSource {
  const _ChapterSource({
    required this.html,
    this.fallbackTitle,
    this.tocTitle,
    this.tocLevel,
    this.href,
  });

  final String html;
  final String? fallbackTitle;
  final String? tocTitle;
  final int? tocLevel;
  final String? href;
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
  final collapsed = text.replaceAll(RegExp(r'[ \\t]+'), ' ').trim();
  return collapsed;
}

String _normalizeChapterTitle(
  String title,
  int index,
  String fallback,
  String? derivedTitle,
) {
  final trimmed = title.trim();
  final fallbackResolved = fallbackTitleForIndex(index, fallback);
  if (trimmed.isEmpty || _looksLikeChapterId(trimmed) || trimmed.length <= 3) {
    if (derivedTitle != null &&
        derivedTitle.trim().isNotEmpty &&
        !_looksLikeChapterId(derivedTitle)) {
      return derivedTitle;
    }
    return fallbackResolved;
  }
  if (_isBareChapterTitle(trimmed)) {
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
    for (final section in body.findElements('section')) {
      final rawTitle = _extractFb2SectionTitle(section);
      if (_shouldSkipFb2Title(rawTitle)) {
        continue;
      }
      var isSpecial = _isFb2Prologue(rawTitle) || _isFb2Epilogue(rawTitle);
      if (!isSpecial) {
        chapterCounter += 1;
      }
      final normalized =
          _normalizeFb2ChapterTitle(rawTitle, chapterCounter, isSpecial);
      if (normalized.isEmpty || normalized == lastTitle) {
        continue;
      }
      lastTitle = normalized;
      chapters.add(
        _ChapterSource(
          html: section.toXmlString(),
          fallbackTitle: normalized,
          tocTitle: normalized,
          tocLevel: 0,
          href: null,
        ),
      );
    }

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
  if (RegExp(r'^глава\\s*\\d+').hasMatch(lower)) {
    return true;
  }
  if (RegExp(r'^chapter\\s*\\d+').hasMatch(lower)) {
    return true;
  }
  return RegExp(r'^\\d+$').hasMatch(lower);
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
  final match = RegExp(r'глава\\s*(\\d+)', caseSensitive: false).firstMatch(lower);
  if (match != null) {
    return 'Глава ${match.group(1)}';
  }
  if (RegExp(r'^\\d+$').hasMatch(title.trim())) {
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
  final tocEntries = _tocEntriesFromArchive(archive);
  if (tocEntries.isNotEmpty) {
    final chapters = _chaptersFromTocEntries(archive, tocEntries);
    if (chapters.isNotEmpty && !_isTocQualityPoor(tocEntries, chapters)) {
      Log.d('Reader toc order: ${chapters.length} items');
      return chapters;
    }
    Log.d(
      'Reader toc quality poor: entries=${tocEntries.length}, chapters=${chapters.length}',
    );
  }

  final spineHrefs = _spineHrefsFromArchive(archive);
  if (spineHrefs.isNotEmpty) {
    Log.d('Reader spine order: ${spineHrefs.length} items');
    final headingChapters = _chaptersFromHeadings(archive, spineHrefs);
    if (headingChapters.isNotEmpty) {
      Log.d('Reader headings order: ${headingChapters.length} items');
      return headingChapters;
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

bool _isTocQualityPoor(
  List<_TocEntry> tocEntries,
  List<_ChapterSource> chapters,
) {
  if (tocEntries.isEmpty) {
    return true;
  }
  if (chapters.isEmpty) {
    return true;
  }
  final ratio = chapters.length / tocEntries.length;
  return tocEntries.length >= 8 && ratio < 0.4;
}

List<_ChapterSource> _chaptersFromHeadings(
  Archive archive,
  List<String> spineHrefs,
) {
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
    final fallback = p.basenameWithoutExtension(href);
    final heading = _extractChapterTitle(decoded, fallback);
    if (heading.trim().isEmpty) {
      continue;
    }
    chapters.add(
      _ChapterSource(
        html: decoded,
        fallbackTitle: fallback,
        tocTitle: heading,
        tocLevel: 0,
        href: href,
      ),
    );
  }
  return chapters;
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

List<_TocEntry> _tocEntriesFromArchive(Archive archive) {
  final opfPath = _findOpfPath(archive);
  if (opfPath == null) {
    return const <_TocEntry>[];
  }
  final opfFile = _archiveFileByName(archive, opfPath);
  if (opfFile == null || opfFile.content is! List<int>) {
    return const <_TocEntry>[];
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
    final navToc = navPath == null
        ? const <_TocEntry>[]
        : _tocEntriesFromNav(archive, navPath);
    final ncxToc = ncxPath == null
        ? const <_TocEntry>[]
        : _tocEntriesFromNcx(archive, ncxPath);
    if (navToc.isEmpty && ncxToc.isEmpty) {
      return const <_TocEntry>[];
    }
    if (navToc.isEmpty) {
      Log.d('Reader toc source: ncx (${ncxToc.length})');
      return _normalizeTocEntries(ncxToc);
    }
    if (ncxToc.isEmpty) {
      Log.d('Reader toc source: nav (${navToc.length})');
      return _normalizeTocEntries(navToc);
    }
    final navScore = _tocQualityScore(navToc);
    final ncxScore = _tocQualityScore(ncxToc);
    final chosen = navScore >= ncxScore ? navToc : ncxToc;
    Log.d(
      'Reader toc source: ${navScore >= ncxScore ? 'nav' : 'ncx'} '
      '(nav=$navScore, ncx=$ncxScore)',
    );
    return _normalizeTocEntries(chosen);
  } catch (e) {
    Log.d('Reader failed to parse OPF toc: $e');
  }
  return const <_TocEntry>[];
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
  if (ratio < 0.2 && chapterRatio >= 0.4) {
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

double _tocQualityScore(List<_TocEntry> entries) {
  if (entries.isEmpty) {
    return 0;
  }
  var empty = 0;
  var long = 0;
  var sentence = 0;
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
  }
  final total = entries.length.toDouble();
  final emptyRatio = empty / total;
  final longRatio = long / total;
  final sentenceRatio = sentence / total;
  var score = 1.0 - (emptyRatio * 0.6) - (longRatio * 0.3) - (sentenceRatio * 0.2);
  if (score < 0) {
    score = 0;
  }
  return double.parse(score.toStringAsFixed(2));
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
  List<_TocEntry> entries,
) {
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
      final text = entry.value
          .toString()
          .replaceAll(RegExp(r'\s+\n'), '\n')
          .replaceAll(RegExp(r'\n\s+'), '\n')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .trim();
      if (text.isNotEmpty) {
        result[entry.key] = text;
      }
    }
    return result;
  } catch (e) {
    Log.d('Reader failed to parse fragment text: $e');
    return const <String, String>{};
  }
}

bool _isBlockElement(String name) {
  switch (name) {
    case 'p':
    case 'div':
    case 'br':
    case 'li':
    case 'blockquote':
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      return true;
    default:
      return false;
  }
}

String _resolveHref(String baseDir, String href) {
  final clean = href.split('#').first.trim();
  if (clean.isEmpty) {
    return '';
  }
  return p.posix.normalize(p.posix.join(baseDir, clean));
}

List<String> _spineHrefsFromArchive(Archive archive) {
  final opfPath = _findOpfPath(archive);
  if (opfPath == null) {
    return const <String>[];
  }
  final opfFile = _archiveFileByName(archive, opfPath);
  if (opfFile == null) {
    return const <String>[];
  }
  final content = opfFile.content;
  if (content is! List<int>) {
    return const <String>[];
  }
  final opfDir = p.posix.dirname(opfPath);
  try {
    final xml = utf8.decode(content, allowMalformed: true);
    final doc = XmlDocument.parse(xml);
    final manifest = <String, String>{};
    for (final node in doc.descendants.whereType<XmlElement>()) {
      if (node.name.local == 'item') {
        final id = node.getAttribute('id');
        final href = node.getAttribute('href');
        if (id != null && href != null) {
          manifest[id] = href;
        }
      }
    }
    final spine = <String>[];
    for (final node in doc.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'itemref') {
        continue;
      }
      final linear = node.getAttribute('linear');
      if (linear != null && linear.toLowerCase() == 'no') {
        continue;
      }
      final idref = node.getAttribute('idref');
      if (idref == null) {
        continue;
      }
      final href = manifest[idref];
      if (href == null || href.trim().isEmpty) {
        continue;
      }
      final resolved = p.posix.normalize(p.posix.join(opfDir, href));
      spine.add(resolved);
    }
    return spine;
  } catch (e) {
    Log.d('Reader failed to parse OPF spine: $e');
    return const <String>[];
  }
}

bool _isFictionBookXml(String xml) {
  return xml.contains('<FictionBook') || xml.contains('<fictionbook');
}
