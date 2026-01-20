import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cogniread/src/core/types/anchor.dart';
import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/reader/presentation/reader_controller.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLibraryStore extends LibraryStore {
  _FakeLibraryStore(this._entry);

  LibraryEntry _entry;

  @override
  Future<void> init() async {}

  @override
  Future<LibraryEntry?> getById(String id) async {
    if (_entry.id == id) {
      return _entry;
    }
    return null;
  }

  @override
  Future<void> upsert(LibraryEntry entry) async {
    _entry = entry;
  }

  @override
  Future<void> updateReadingPosition(
    String id,
    ReadingPosition position,
  ) async {
    if (_entry.id != id) {
      return;
    }
    _entry = LibraryEntry(
      id: _entry.id,
      title: _entry.title,
      author: _entry.author,
      localPath: _entry.localPath,
      coverPath: _entry.coverPath,
      addedAt: _entry.addedAt,
      fingerprint: _entry.fingerprint,
      sourcePath: _entry.sourcePath,
      readingPosition: position,
      progress: _entry.progress,
      lastOpenedAt: _entry.lastOpenedAt,
      notes: _entry.notes,
      highlights: _entry.highlights,
      bookmarks: _entry.bookmarks,
      tocOfficial: _entry.tocOfficial,
      tocGenerated: _entry.tocGenerated,
      tocMode: _entry.tocMode,
    );
  }
}

File _writeTestEpub({required String title, required List<String> paragraphs}) {
  final tempDir = Directory(
    '${Directory.systemTemp.path}/cogniread-reader-anchor-${DateTime.now().microsecondsSinceEpoch}',
  );
  tempDir.createSync(recursive: true);
  const opfPath = 'OEBPS/content.opf';
  const htmlPath = 'OEBPS/ch1.xhtml';
  final containerXml =
      '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="$opfPath" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';
  final opf =
      '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
  </metadata>
  <manifest>
    <item id="item1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="item1"/>
  </spine>
</package>
''';
  final body = paragraphs.map((p) => '<p>$p</p>').join('\n');
  final html =
      '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>$title</title></head>
  <body>
    <h1>$title</h1>
    $body
  </body>
</html>
''';

  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'META-INF/container.xml',
        containerXml.length,
        containerXml.codeUnits,
      ),
    )
    ..addFile(ArchiveFile(opfPath, opf.length, opf.codeUnits))
    ..addFile(ArchiveFile(htmlPath, html.length, html.codeUnits));
  final bytes = ZipEncoder().encode(archive, level: Deflate.NO_COMPRESSION);
  final file = File('${tempDir.path}/test.epub');
  file.writeAsBytesSync(bytes ?? <int>[]);
  return file;
}

LibraryEntry _makeEntry(String id, String path) {
  return LibraryEntry(
    id: id,
    title: 'Test',
    author: 'Author',
    localPath: path,
    coverPath: null,
    addedAt: DateTime.now(),
    fingerprint: id,
    sourcePath: path,
    readingPosition: const ReadingPosition(
      chapterHref: null,
      anchor: null,
      offset: null,
      updatedAt: null,
    ),
    progress: const ReadingProgress(
      percent: null,
      chapterIndex: null,
      totalChapters: null,
      updatedAt: null,
    ),
    lastOpenedAt: null,
    notes: const <Note>[],
    highlights: const <Highlight>[],
    bookmarks: const <Bookmark>[],
    tocOfficial: const [],
    tocGenerated: const [],
    tocMode: TocMode.official,
  );
}

void main() {
  testWidgets('ReaderScreen initialAnchor jumps down the chapter', (
    tester,
  ) async {
    final paragraphs = List<String>.generate(
      80,
      (i) => 'Paragraph $i TOKEN_$i ${'x' * 200}',
    );
    final epub = _writeTestEpub(title: 'Big Chapter', paragraphs: paragraphs);
    final store = _FakeLibraryStore(_makeEntry('book-1', epub.path));

    final controller = ReaderController(store: store, perfLogsEnabled: false);
    await tester.runAsync(() => controller.load('book-1'));
    final chapter = controller.chapters.first;
    final chapterHref = chapter.href ?? 'index:0';
    final endOffset =
        chapter.title.length +
        chapter.paragraphs.fold<int>(0, (sum, p) => sum + p.length);
    final anchor = Anchor(
      chapterHref: chapterHref,
      offset: endOffset,
    ).toString();

    Future<void> waitForReaderLoad() async {
      for (var i = 0; i < 80; i += 1) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }

    final early = find.textContaining('TOKEN_0', findRichText: true);
    final target = find.textContaining('TOKEN_79', findRichText: true);

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          bookId: 'book-1',
          store: store,
          persistReadingPosition: false,
          initialAnchor: anchor,
        ),
      ),
    );
    await waitForReaderLoad();
    expect(find.text('Повторить'), findsNothing);
    expect(early, findsOneWidget);
    expect(target, findsOneWidget);
  });

  testWidgets('ReaderScreen initialSearchQuery highlights match', (
    tester,
  ) async {
    final paragraphs = List<String>.generate(
      80,
      (i) => 'Paragraph $i TOKEN_$i ${'x' * 200}',
    );
    final epub = _writeTestEpub(title: 'Big Chapter', paragraphs: paragraphs);
    final store = _FakeLibraryStore(_makeEntry('book-1', epub.path));

    final controller = ReaderController(store: store, perfLogsEnabled: false);
    await tester.runAsync(() => controller.load('book-1'));
    final chapter = controller.chapters.first;
    const targetIndex = 79;
    final offset =
        chapter.title.length +
        chapter.paragraphs
            .take(targetIndex)
            .fold<int>(0, (sum, p) => sum + p.length);
    final anchor = Anchor(chapterHref: 'index:0', offset: offset).toString();

    Future<void> waitForReaderLoad() async {
      for (var i = 0; i < 80; i += 1) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }

    bool hasHighlightedToken(String token) {
      const expected = Color(0x8CFFF59D);
      bool spanHasHighlight(InlineSpan span) {
        if (span is TextSpan) {
          final style = span.style;
          final text = span.text ?? '';
          if (style?.backgroundColor == expected && text.contains(token)) {
            return true;
          }
          final children = span.children;
          if (children != null) {
            for (final child in children) {
              if (spanHasHighlight(child)) {
                return true;
              }
            }
          }
        }
        return false;
      }

      for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
        final plain = widget.text.toPlainText();
        if (!plain.contains(token)) {
          continue;
        }
        if (spanHasHighlight(widget.text)) {
          return true;
        }
      }
      return false;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          bookId: 'book-1',
          store: store,
          persistReadingPosition: false,
          initialAnchor: anchor,
          initialSearchQuery: 'TOKEN_79',
        ),
      ),
    );
    await waitForReaderLoad();
    expect(find.text('Повторить'), findsNothing);
    var highlighted = hasHighlightedToken('TOKEN_79');
    for (var i = 0; i < 40 && !highlighted; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      highlighted = hasHighlightedToken('TOKEN_79');
    }
    expect(highlighted, isTrue);
  });
}
