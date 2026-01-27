import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class SearchIndexExtractedChapter {
  const SearchIndexExtractedChapter({
    required this.title,
    required this.paragraphs,
    required this.href,
  });

  final String title;
  final List<String> paragraphs;
  final String href;
}

class SearchIndexBookTextExtractor {
  static List<SearchIndexExtractedChapter> extractFromFile(
    String localPath, {
    required String tocMode,
    required bool hasStoredToc,
  }) {
    if (localPath.trim().isEmpty) {
      return const <SearchIndexExtractedChapter>[];
    }
    final bytes = File(localPath).readAsBytesSync();
    final ext = p.extension(localPath).toLowerCase();
    if (ext == '.fb2') {
      final decoded = _decodeFb2Bytes(bytes);
      final sources = _chaptersFromFb2(decoded);
      return _buildChapters(sources);
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final tocResult = _buildTocResult(archive);
    final resolvedMode = _resolveTocMode(
      tocMode,
      hasStoredToc: hasStoredToc,
      tocResult: tocResult,
    );
    final entries = _entriesForMode(resolvedMode, tocResult);
    final chapterSources = entries.isNotEmpty
        ? _chaptersFromTocEntries(archive, entries, preferTocTitle: true)
        : const <_ChapterSource>[];
    if (chapterSources.isNotEmpty) {
      return _buildChapters(chapterSources);
    }
    final chapters = _chaptersFromArchive(archive);
    if (chapters.isNotEmpty) {
      return _buildChapters(chapters);
    }
    return const <SearchIndexExtractedChapter>[];
  }
}

List<SearchIndexExtractedChapter> _buildChapters(List<_ChapterSource> sources) {
  final chapters = <SearchIndexExtractedChapter>[];
  for (var i = 0; i < sources.length; i += 1) {
    final source = sources[i];
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
    final href = source.href ?? 'index:$i';
    chapters.add(
      SearchIndexExtractedChapter(
        title: title,
        paragraphs: _splitParagraphs(cleanedText),
        href: href,
      ),
    );
  }
  return chapters;
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

enum _TocMode { official, generated }

class _TocEntry {
  const _TocEntry({
    required this.title,
    required this.href,
    required this.level,
    required this.fragment,
  });

  final String title;
  final String href;
  final int level;
  final String? fragment;
}

enum _TocSource { nav, ncx, headings, spine, none }

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

  int get score {
    if (total <= 0) {
      return 0;
    }
    var result = 0;
    result += (100 * (1 - emptyRatio)).round();
    result += (30 * (1 - longRatio)).round();
    result += (20 * chapterRatio).round();
    result += hasPrologue ? 5 : 0;
    result += hasEpilogue ? 5 : 0;
    result -= (20 * sentenceRatio).round();
    return result;
  }

  bool get preferGenerated => sentenceRatio > 0.35 && chapterRatio < 0.35;
}

class _TocCandidate {
  const _TocCandidate({
    required this.source,
    required this.entries,
    required this.quality,
    required this.preferTocTitle,
  });

  final _TocSource source;
  final List<_TocEntry> entries;
  final _TocQuality quality;
  final bool preferTocTitle;

  static const _TocCandidate empty = _TocCandidate(
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
    preferTocTitle: false,
  );
}

class _GeneratedToc {
  const _GeneratedToc({required this.entries, required this.source});

  final List<_TocEntry> entries;
  final _TocSource source;
}

class _TocParseResult {
  const _TocParseResult({
    required this.officialEntries,
    required this.generatedEntries,
    required this.defaultMode,
    required this.officialSource,
    required this.generatedSource,
  });

  final List<_TocEntry> officialEntries;
  final List<_TocEntry> generatedEntries;
  final _TocMode defaultMode;
  final _TocSource officialSource;
  final _TocSource generatedSource;
}

_TocMode _resolveTocMode(
  String tocMode, {
  required bool hasStoredToc,
  required _TocParseResult tocResult,
}) {
  if (!hasStoredToc) {
    return tocResult.defaultMode;
  }
  final effective = tocMode == 'generated'
      ? _TocMode.generated
      : _TocMode.official;
  if (effective == _TocMode.generated &&
      tocResult.generatedEntries.isEmpty &&
      tocResult.officialEntries.isNotEmpty) {
    return _TocMode.official;
  }
  if (effective == _TocMode.official &&
      tocResult.officialEntries.isEmpty &&
      tocResult.generatedEntries.isNotEmpty) {
    return _TocMode.generated;
  }
  return effective;
}

List<_TocEntry> _entriesForMode(_TocMode mode, _TocParseResult tocResult) {
  if (mode == _TocMode.generated && tocResult.generatedEntries.isNotEmpty) {
    return tocResult.generatedEntries;
  }
  if (tocResult.officialEntries.isNotEmpty) {
    return tocResult.officialEntries;
  }
  return tocResult.generatedEntries;
}

bool _isFictionBookXml(String xml) => xml.contains('<FictionBook');

String _decodeFb2Bytes(List<int> bytes) {
  final utf = utf8.decode(bytes, allowMalformed: true);
  if (utf.contains('encoding="windows-1251"') ||
      utf.contains("encoding='windows-1251'")) {
    return utf;
  }
  return utf;
}

List<_ChapterSource> _chaptersFromFb2(String xml) {
  if (!_isFictionBookXml(xml)) {
    return const <_ChapterSource>[];
  }
  try {
    final doc = XmlDocument.parse(xml);
    final bodies = doc.findAllElements('body');
    final primary = bodies.isEmpty ? null : bodies.first;
    if (primary == null) {
      return const <_ChapterSource>[];
    }
    final sections = primary.findElements('section').toList(growable: false);
    if (sections.isEmpty) {
      return const <_ChapterSource>[];
    }
    final result = <_ChapterSource>[];
    for (final section in sections) {
      final titleNode = section.findElements('title').firstOrNull;
      final title = titleNode?.innerText ?? '';
      final text = section.innerText;
      if (text.trim().isEmpty) {
        continue;
      }
      result.add(
        _ChapterSource(
          html: text,
          fallbackTitle: title.trim(),
          tocLevel: 0,
          href: null,
          preferTocTitle: true,
        ),
      );
    }
    return result;
  } catch (_) {
    return const <_ChapterSource>[];
  }
}

List<_ChapterSource> _chaptersFromArchive(Archive archive) {
  final fb2Chapters = _fb2ChaptersFromArchive(archive);
  if (fb2Chapters.isNotEmpty) {
    return fb2Chapters;
  }

  final spineHrefs = _spineHrefsFromArchive(archive);
  if (spineHrefs.isNotEmpty) {
    final headingEntries = _tocEntriesFromHeadings(archive, spineHrefs);
    if (headingEntries.isNotEmpty) {
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
  var bestScore = 0;
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
      final decoded = utf8.decode(content, allowMalformed: true).trim();
      consider(decoded);
      continue;
    }
    if (name.endsWith('.fb2') || name.endsWith('.xml')) {
      final decoded = utf8.decode(content, allowMalformed: true);
      if (_isFictionBookXml(decoded)) {
        consider(decoded);
      }
    }
  }
  if (best != null && best!.trim().isNotEmpty) {
    return <_ChapterSource>[_ChapterSource(html: best!)];
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
    final chapters = _chaptersFromFb2(decoded);
    if (chapters.isNotEmpty) {
      return chapters;
    }
    if (decoded.trim().isNotEmpty) {
      return <_ChapterSource>[_ChapterSource(html: decoded)];
    }
  }
  return const <_ChapterSource>[];
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
      final fullPath = node.getAttribute('full-path');
      if (fullPath != null && fullPath.trim().isNotEmpty) {
        return fullPath.trim();
      }
    }
  } catch (_) {}
  return null;
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
  } catch (_) {
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
    final title = _extractChapterTitle(
      decoded,
      p.basenameWithoutExtension(href),
    );
    if (title.trim().isEmpty) {
      continue;
    }
    entries.add(_TocEntry(title: title, href: href, level: 0, fragment: null));
  }
  return entries;
}

class _ParsedHtml {
  const _ParsedHtml({required this.fullText, required this.fragments});

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
    final parsed = cache.putIfAbsent(entry.href, () {
      final fragments = _extractFragmentTexts(decoded, entries, entry.href);
      return _ParsedHtml(fullText: _toPlainText(decoded), fragments: fragments);
    });

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

_TocParseResult _buildTocResult(Archive archive) {
  final tocCandidate = _buildEpubTocCandidate(archive);
  final officialEntries = tocCandidate.entries;
  final generated = _buildGeneratedEntries(archive);
  final generatedEntries = generated.entries;
  final defaultMode = officialEntries.isEmpty
      ? _TocMode.generated
      : tocCandidate.quality.preferGenerated && generatedEntries.isNotEmpty
      ? _TocMode.generated
      : _TocMode.official;
  return _TocParseResult(
    officialEntries: officialEntries,
    generatedEntries: generatedEntries,
    defaultMode: defaultMode,
    officialSource: tocCandidate.source,
    generatedSource: generated.source,
  );
}

_GeneratedToc _buildGeneratedEntries(Archive archive) {
  final spineHrefs = _spineHrefsFromArchive(archive);
  if (spineHrefs.isEmpty) {
    return const _GeneratedToc(entries: <_TocEntry>[], source: _TocSource.none);
  }
  final headingEntries = _tocEntriesFromHeadings(archive, spineHrefs);
  if (headingEntries.isNotEmpty) {
    return _GeneratedToc(entries: headingEntries, source: _TocSource.headings);
  }
  final entries = <_TocEntry>[];
  var order = 0;
  for (final href in spineHrefs) {
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

_TocCandidate _buildEpubTocCandidate(Archive archive) {
  try {
    final opfPath = _findOpfPath(archive);
    if (opfPath == null) {
      return _TocCandidate.empty;
    }
    final opfFile = _archiveFileByName(archive, opfPath);
    if (opfFile == null || opfFile.content is! List<int>) {
      return _TocCandidate.empty;
    }
    final opfDir = p.posix.dirname(opfPath);
    final xml = utf8.decode(opfFile.content as List<int>, allowMalformed: true);
    final doc = XmlDocument.parse(xml);

    String? navPath;
    String? ncxPath;
    for (final item in doc.findAllElements('item')) {
      final properties = item.getAttribute('properties') ?? '';
      final mediaType = item.getAttribute('media-type') ?? '';
      final href = item.getAttribute('href');
      if (href == null || href.trim().isEmpty) {
        continue;
      }
      final resolved = p.posix.normalize(p.posix.join(opfDir, href));
      if (properties.contains('nav')) {
        navPath = resolved;
      }
      if (mediaType.contains('ncx') || href.toLowerCase().endsWith('.ncx')) {
        ncxPath = resolved;
      }
    }

    final navEntries = navPath == null
        ? const <_TocEntry>[]
        : _tocEntriesFromNav(archive, navPath);
    final ncxEntries = ncxPath == null
        ? const <_TocEntry>[]
        : _tocEntriesFromNcx(archive, ncxPath);
    final normalizedNav = _normalizeTocEntries(navEntries);
    final normalizedNcx = _normalizeTocEntries(ncxEntries);
    final navQuality = _evaluateTocQuality(normalizedNav);
    final ncxQuality = _evaluateTocQuality(normalizedNcx);
    final useNav = navQuality.score >= ncxQuality.score;
    final chosen = useNav ? normalizedNav : normalizedNcx;
    final chosenQuality = useNav ? navQuality : ncxQuality;
    return _TocCandidate(
      source: useNav ? _TocSource.nav : _TocSource.ncx,
      entries: chosen,
      quality: chosenQuality,
      preferTocTitle: true,
    );
  } catch (_) {
    return _TocCandidate.empty;
  }
}

class _TocTarget {
  const _TocTarget(this.path, this.fragment);

  final String path;
  final String? fragment;
}

_TocTarget _resolveTocTarget(String baseDir, String href) {
  final trimmed = href.trim();
  final parts = trimmed.split('#');
  final path = parts.first.trim();
  final fragment = parts.length > 1 ? parts[1].trim() : null;
  final resolved = p.posix.normalize(p.posix.join(baseDir, path));
  return _TocTarget(resolved, fragment?.isEmpty == true ? null : fragment);
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
    XmlElement? tocNav;
    for (final nav in doc.findAllElements('nav')) {
      final type =
          nav.getAttribute('type') ?? nav.getAttribute('epub:type') ?? '';
      if (type.contains('toc')) {
        tocNav = nav;
        break;
      }
    }
    if (tocNav == null) {
      return const <_TocEntry>[];
    }
    final entries = <_TocEntry>[];

    void walkOl(XmlElement ol, int depth) {
      for (final li in ol.findElements('li')) {
        final link =
            li.findElements('a').firstOrNull ??
            li.descendants.whereType<XmlElement>().firstWhereOrNull(
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
        final olChild = li.findElements('ol').firstOrNull;
        if (olChild != null) {
          walkOl(olChild, depth + 1);
        }
      }
    }

    final ol = tocNav.findAllElements('ol').firstOrNull;
    if (ol != null) {
      walkOl(ol, 0);
    }
    return entries;
  } catch (_) {
    return const <_TocEntry>[];
  }
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

    void walk(XmlElement node, int depth) {
      if (node.name.local == 'navPoint') {
        final label =
            node.findAllElements('text').firstOrNull?.innerText.trim() ?? '';
        final src = node
            .findAllElements('content')
            .firstOrNull
            ?.getAttribute('src');
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
      for (final child in node.findElements('navPoint')) {
        walk(child, depth + 1);
      }
    }

    final navMap = doc.findAllElements('navMap').firstOrNull;
    if (navMap == null) {
      return const <_TocEntry>[];
    }
    for (final point in navMap.findElements('navPoint')) {
      walk(point, 0);
    }
    return entries;
  } catch (_) {
    return const <_TocEntry>[];
  }
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
  return normalized ?? filtered;
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
  var chapterLike = 0;
  for (final entry in entries) {
    final label = entry.title;
    if (RegExp(r'[.!?]|—|…').hasMatch(label) && label.length > 30) {
      sentenceLike += 1;
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
    if (_isFb2Prologue(raw) || (isFirst && !_containsPrologue(entries))) {
      label = 'Пролог';
    } else if (_isFb2Epilogue(raw) || (isLast && _containsEpilogue(entries))) {
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

bool _containsPrologue(List<_TocEntry> entries) =>
    entries.any((e) => _isFb2Prologue(e.title));
bool _containsEpilogue(List<_TocEntry> entries) =>
    entries.any((e) => _isFb2Epilogue(e.title));

bool _looksLikeChapterLabel(String value) {
  final lower = value.toLowerCase().trim();
  if (lower.isEmpty) {
    return false;
  }
  if (lower.contains('глава')) {
    return true;
  }
  if (RegExp(r'^chapter\\s*\\d+').hasMatch(lower)) {
    return true;
  }
  return RegExp(r'^\\d+$').hasMatch(lower);
}

bool _isFb2Prologue(String value) {
  final lower = value.toLowerCase();
  return lower.contains('пролог') || lower.contains('prologue');
}

bool _isFb2Epilogue(String value) {
  final lower = value.toLowerCase();
  return lower.contains('эпилог') || lower.contains('epilogue');
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
            buffer.write('\\n');
          }
        }
      }

      walk(document);
      return buffer
          .toString()
          .replaceAll(RegExp(r'\\s+\\n'), '\\n')
          .replaceAll(RegExp(r'\\n\\s+'), '\\n')
          .replaceAll(RegExp(r'[ \\t]+'), ' ')
          .trim();
    } catch (_) {}
  }
  return _stripHtmlToText(html);
}

bool _looksLikeXml(String html) {
  final lower = html.toLowerCase();
  if (lower.contains('<!doctype') || lower.contains('<html')) {
    return false;
  }
  return lower.contains('<?xml') ||
      lower.contains('<body') ||
      lower.contains('<html');
}

String _stripHtmlToText(String html) {
  var text = html;
  text = text.replaceAll(
    RegExp(
      r'<(script|style)[^>]*>.*?</\1>',
      dotAll: true,
      caseSensitive: false,
    ),
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
  return text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
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

String? _deriveTitleFromText(String text) {
  final lines = text.split('\\n');
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
  return RegExp(r'^(ch|chapter)\\d+(-\\d+)?$').hasMatch(compact) ||
      RegExp(r'^\\d+(-\\d+)?$').hasMatch(compact) ||
      RegExp(r'^ch\\d+(\\d+)?$').hasMatch(compactNoDash);
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
  return RegExp(r'^[a-z]{1,3}\\d{1,3}$').hasMatch(lower);
}

bool _isNormalizedChapterLabel(String value) {
  final lower = value.trim().toLowerCase();
  return lower == 'пролог' ||
      lower == 'эпилог' ||
      RegExp(r'^глава\\s+\\d+([\\-_.]\\d+)?$').hasMatch(lower);
}

bool _isBareChapterTitle(String value) {
  final lower = value.trim().toLowerCase();
  return RegExp(r'^глава\\s*\\d+([\\-_.]\\d+)?$').hasMatch(lower) ||
      RegExp(r'^chapter\\s*\\d+([\\-_.]\\d+)?$').hasMatch(lower);
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

String _cleanTextForReading(String text) {
  final lines = text.split('\\n');
  final cleaned = <String>[];
  final maxHeadLines = 30;
  var lineIndex = 0;

  for (final raw in lines) {
    lineIndex += 1;
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

  return cleaned.join('\\n').replaceAll(RegExp(r'\\n{3,}'), '\\n\\n').trim();
}

bool _looksLikeFrontMatter(String line) {
  final lower = line.toLowerCase();
  return lower.contains('©') ||
      lower.contains('copyright') ||
      lower.contains('издательство') ||
      lower.contains('серия') ||
      lower.contains('isbn');
}

List<String> _splitParagraphs(String text) {
  final lines = text.split('\\n');
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

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final item in this) {
      if (test(item)) {
        return item;
      }
    }
    return null;
  }
}
