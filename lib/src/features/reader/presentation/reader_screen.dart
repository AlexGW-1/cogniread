import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class _ReaderController extends ChangeNotifier {
  _ReaderController({LibraryStore? store}) : _store = store ?? LibraryStore();

  final LibraryStore _store;

  bool _loading = true;
  String? _error;
  String? _title;
  ReadingPosition? _initialPosition;
  List<_Chapter> _chapters = const <_Chapter>[];
  List<_ReaderItem> _items = const <_ReaderItem>[];

  bool get loading => _loading;
  String? get error => _error;
  String? get title => _title;
  ReadingPosition? get initialPosition => _initialPosition;
  List<_Chapter> get chapters => _chapters;
  List<_ReaderItem> get items => _items;

  Future<void> load(String bookId) async {
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

      final file = File(entry.localPath);
      if (!await file.exists()) {
        _error = 'Файл книги недоступен';
        _loading = false;
        notifyListeners();
        return;
      }

      final bytes = await file.readAsBytes();
      Log.d('Reader loading file: ${entry.localPath} (${bytes.length} bytes)');
      final chapterSources = await _extractChapters(bytes)
          .timeout(const Duration(seconds: 8), onTimeout: () {
        throw Exception('EPUB parse timeout');
      });
      Log.d('Reader extracted chapters: ${chapterSources.length}');
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
            key: GlobalKey(),
            title: title,
            level: source.tocLevel ?? 0,
            paragraphs: _splitParagraphs(cleanedText),
            href: source.href,
          ),
        );
      }
      Log.d('Reader extracted text length: $totalTextLength');

      _chapters = chapters;
      _items = _flattenChapters(chapters);
      _title = entry.title;
      _loading = false;
      notifyListeners();
    } catch (e) {
      Log.d('Failed to load book: $e');
      _error = 'Не удалось открыть книгу: $e';
      _loading = false;
      notifyListeners();
    }
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
  final ScrollController _scrollController = ScrollController();
  late final _ReaderController _controller;
  late final VoidCallback _controllerListener;
  ReadingPosition? _initialPosition;
  Timer? _positionDebounce;
  bool _didRestore = false;
  int _restoreAttempts = 0;

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
    _scrollController.addListener(_onScroll);
    _controller.load(widget.bookId);
  }

  @override
  void dispose() {
    _positionDebounce?.cancel();
    _persistReadingPosition();
    _controller.removeListener(_controllerListener);
    _controller.dispose();
    _scrollController.dispose();
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
    if (!_scrollController.hasClients) {
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
    final targetKey = _controller.chapters[index].key;
    final context = targetKey.currentContext;
    if (context == null) {
      _retryRestore();
      return;
    }
    final renderObject = context.findRenderObject();
    final viewport = renderObject == null
        ? null
        : RenderAbstractViewport.of(renderObject);
    if (renderObject == null || viewport == null) {
      _retryRestore();
      return;
    }
    final baseOffset = viewport.getOffsetToReveal(renderObject, 0.0).offset;
    final offsetWithin = (_initialPosition?.offset ?? 0).toDouble();
    final maxOffset = _scrollController.position.maxScrollExtent;
    final target = (baseOffset + offsetWithin).clamp(0.0, maxOffset);
    _scrollController.jumpTo(target);
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
        !_scrollController.hasClients) {
      return;
    }
    final position = _computeReadingPosition();
    if (position == null) {
      return;
    }
    await _controller.saveReadingPosition(widget.bookId, position);
  }

  ReadingPosition? _computeReadingPosition() {
    final scrollOffset = _scrollController.offset;
    int? currentIndex;
    double? currentBase;
    for (var i = 0; i < _controller.chapters.length; i++) {
      final context = _controller.chapters[i].key.currentContext;
      if (context == null) {
        continue;
      }
      final renderObject = context.findRenderObject();
      final viewport = renderObject == null
          ? null
          : RenderAbstractViewport.of(renderObject);
      if (renderObject == null || viewport == null) {
        continue;
      }
      final offset = viewport.getOffsetToReveal(renderObject, 0.0).offset;
      if (offset <= scrollOffset + 1) {
        currentIndex = i;
        currentBase = offset;
      } else {
        break;
      }
    }
    if (currentIndex == null) {
      return null;
    }
    final chapter = _controller.chapters[currentIndex];
    final chapterHref = chapter.href ?? 'index:$currentIndex';
    final offsetWithin = scrollOffset - (currentBase ?? scrollOffset);
    return ReadingPosition(
      chapterHref: chapterHref,
      anchor: null,
      offset: offsetWithin.round(),
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
                  ? Center(child: Text(_controller.error!))
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
                              child: SelectionArea(
                                child: ListView.builder(
                                  controller: _scrollController,
                                  itemCount: _controller.items.length,
                                  itemBuilder: (context, index) {
                                    final item = _controller.items[index];
                                    switch (item.kind) {
                                      case _ReaderItemKind.header:
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                            bottom: 10,
                                          ),
                                          child: _ChapterHeader(
                                            key: item.chapter!.key,
                                            title: item.chapter!.title,
                                          ),
                                        );
                                      case _ReaderItemKind.paragraph:
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: Text(
                                            item.text ?? '',
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
                                        );
                                      case _ReaderItemKind.divider:
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          child: Divider(
                                            height: 32,
                                            color: scheme.outlineVariant,
                                          ),
                                        );
                                    }
                                  },
                                ),
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
          child: ListView.separated(
            itemCount: _controller.chapters.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final chapter = _controller.chapters[index];
              final indent = 16.0 + (chapter.level * 18.0);
              return ListTile(
                contentPadding:
                    EdgeInsets.only(left: indent, right: 16, top: 4, bottom: 4),
                title: Text(chapter.title),
                onTap: () {
                  Navigator.of(context).pop();
                  _scrollToChapter(index);
                },
              );
            },
          ),
        );
      },
    );
  }

  void _scrollToChapter(int index) {
    if (index < 0 || index >= _controller.chapters.length) {
      return;
    }
    final key = _controller.chapters[index].key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = key.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
      }
    });
  }
}

class _Chapter {
  const _Chapter({
    required this.key,
    required this.title,
    required this.level,
    required this.paragraphs,
    required this.href,
  });

  final GlobalKey key;
  final String title;
  final int level;
  final List<String> paragraphs;
  final String? href;
}

enum _ReaderItemKind { header, paragraph, divider }

class _ReaderItem {
  const _ReaderItem.header(this.chapter)
      : kind = _ReaderItemKind.header,
        text = null;
  const _ReaderItem.paragraph(this.text)
      : kind = _ReaderItemKind.paragraph,
        chapter = null;
  const _ReaderItem.divider()
      : kind = _ReaderItemKind.divider,
        chapter = null,
        text = null;

  final _ReaderItemKind kind;
  final _Chapter? chapter;
  final String? text;
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

List<_ReaderItem> _flattenChapters(List<_Chapter> chapters) {
  final items = <_ReaderItem>[];
  for (final chapter in chapters) {
    items.add(_ReaderItem.header(chapter));
    for (final paragraph in chapter.paragraphs) {
      items.add(_ReaderItem.paragraph(paragraph));
    }
    items.add(_ReaderItem.divider());
  }
  return items;
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

List<_ChapterSource> _chaptersFromArchive(Archive archive) {
  final tocEntries = _tocEntriesFromArchive(archive);
  if (tocEntries.isNotEmpty) {
    final chapters = _chaptersFromTocEntries(archive, tocEntries);
    if (chapters.isNotEmpty) {
      Log.d('Reader toc order: ${chapters.length} items');
      return chapters;
    }
  }

  final spineHrefs = _spineHrefsFromArchive(archive);
  if (spineHrefs.isNotEmpty) {
    Log.d('Reader spine order: ${spineHrefs.length} items');
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
    if (navPath != null) {
      final toc = _tocEntriesFromNav(archive, navPath);
      if (toc.isNotEmpty) {
        return toc;
      }
    }
    if (ncxPath != null) {
      final toc = _tocEntriesFromNcx(archive, ncxPath);
      if (toc.isNotEmpty) {
        return toc;
      }
    }
  } catch (e) {
    Log.d('Reader failed to parse OPF toc: $e');
  }
  return const <_TocEntry>[];
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

    for (final ol in tocNav.findElements('ol')) {
      walkOl(ol, 0);
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
