import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

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
  final LibraryStore _store = LibraryStore();
  final ScrollController _scrollController = ScrollController();
  List<_Chapter> _chapters = const <_Chapter>[];
  String? _title;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBook();
  }

  Future<void> _loadBook() async {
    try {
      await _store.init();
      final entry = await _store.getById(widget.bookId);
      if (entry == null) {
        setState(() {
          _error = 'Книга не найдена';
          _loading = false;
        });
        return;
      }

      final file = File(entry.localPath);
      if (!await file.exists()) {
        setState(() {
          _error = 'Файл книги недоступен';
          _loading = false;
        });
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
        final fallbackTitle =
            source.fallbackTitle ?? 'Глава ${i + 1}'.trim();
        final rawTitle = _extractChapterTitle(source.html, fallbackTitle);
        final title = _normalizeChapterTitle(rawTitle, i + 1, fallbackTitle);
        final rawText = _toPlainText(source.html);
        final cleanedText = _cleanTextForReading(rawText);
        totalTextLength += cleanedText.length;
        chapters.add(
          _Chapter(
            key: GlobalKey(),
            title: title,
            paragraphs: _splitParagraphs(cleanedText),
          ),
        );
      }
      Log.d('Reader extracted text length: $totalTextLength');

      if (!mounted) {
        return;
      }
      setState(() {
        _chapters = chapters;
        _title = entry.title;
        _loading = false;
      });
    } catch (e) {
      Log.d('Failed to load book: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Не удалось открыть книгу: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final hasToc = _chapters.length > 1;
    final body = _buildBody(context);
    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_title ?? 'Reader'),
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
    final hasToc = _chapters.length > 1;
    final readerSurface = scheme.surface.withOpacity(0.95);
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
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _chapters.isEmpty
                      ? const Center(
                          child: Text('Нет данных для отображения'),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            return SizedBox(
                              height: constraints.maxHeight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ReaderHeader(
                                    title: _title ?? 'Reader',
                                    hasToc: hasToc,
                                    onTocTap: _showToc,
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    child: SelectionArea(
                                      child: SingleChildScrollView(
                                        controller: _scrollController,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (final chapter in _chapters)
                                              ...[
                                                _ChapterHeader(
                                                  key: chapter.key,
                                                  title: chapter.title,
                                                ),
                                                const SizedBox(height: 10),
                                                for (final paragraph
                                                    in chapter.paragraphs)
                                                  ...[
                                                    Text(
                                                      paragraph,
                                                      textAlign:
                                                          TextAlign.justify,
                                                      style: const TextStyle(
                                                        fontSize: 17,
                                                        height: 1.65,
                                                        fontFamily: 'Georgia',
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                  ],
                                                const SizedBox(height: 12),
                                                Divider(
                                                  height: 32,
                                                  color: scheme.outlineVariant,
                                                ),
                                              ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
        ),
      ),
    );
    final wrapped = widget.embedded ? content : SafeArea(child: content);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.surfaceVariant.withOpacity(0.25),
            scheme.surface.withOpacity(0.05),
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
            itemCount: _chapters.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final chapter = _chapters[index];
              return ListTile(
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
    if (index < 0 || index >= _chapters.length) {
      return;
    }
    final key = _chapters[index].key;
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
    required this.paragraphs,
  });

  final GlobalKey key;
  final String title;
  final List<String> paragraphs;
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
  const _ChapterSource({required this.html, this.fallbackTitle});

  final String html;
  final String? fallbackTitle;
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

String _normalizeChapterTitle(String title, int index, String fallback) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) {
    return fallbackTitleForIndex(index, fallback);
  }
  if (_looksLikeChapterId(trimmed)) {
    return fallbackTitleForIndex(index, fallback);
  }
  if (trimmed.length <= 3) {
    return fallbackTitleForIndex(index, fallback);
  }
  return trimmed;
}

String fallbackTitleForIndex(int index, String fallback) {
  if (fallback.trim().isNotEmpty) {
    return fallback;
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
    if (_looksLikeChapterId(line)) {
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
