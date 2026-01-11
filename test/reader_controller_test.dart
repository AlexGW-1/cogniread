import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/reader/presentation/reader_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLibraryStore extends LibraryStore {
  _FakeLibraryStore(this._entry);

  LibraryEntry _entry;
  int upsertCount = 0;

  set entry(LibraryEntry value) => _entry = value;

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
    upsertCount += 1;
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

Future<File> _writeTestEpub(String title) async {
  final tempDir = await Directory.systemTemp.createTemp('cogniread-epub');
  final opfPath = 'OEBPS/content.opf';
  final htmlPath = 'OEBPS/ch1.xhtml';
  final containerXml = '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="$opfPath" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';
  final opf = '''
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
  final html = '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>$title</title></head>
  <body>
    <h1>$title</h1>
    <p>Hello reader.</p>
  </body>
</html>
''';
  final archive = Archive()
    ..addFile(ArchiveFile('META-INF/container.xml', containerXml.length,
        containerXml.codeUnits))
    ..addFile(ArchiveFile(opfPath, opf.length, opf.codeUnits))
    ..addFile(ArchiveFile(htmlPath, html.length, html.codeUnits));
  final bytes = ZipEncoder().encode(archive);
  final file = File('${tempDir.path}/test.epub');
  await file.writeAsBytes(bytes ?? <int>[]);
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
  test('ReaderController loads content', () async {
    final epub = await _writeTestEpub('Chapter One');
    final store = _FakeLibraryStore(_makeEntry('book-1', epub.path));
    final controller = ReaderController(store: store, perfLogsEnabled: false);

    await controller.load('book-1');

    expect(controller.loading, isFalse);
    expect(controller.error, isNull);
    expect(controller.chapters, isNotEmpty);
    expect(controller.chapters.first.title, contains('Chapter One'));
  });

  test('ReaderController retry recovers after error', () async {
    final epub = await _writeTestEpub('Chapter Two');
    final missingEntry = _makeEntry('book-2', '${epub.path}.missing');
    final store = _FakeLibraryStore(missingEntry);
    final controller = ReaderController(store: store, perfLogsEnabled: false);

    await controller.load('book-2');

    expect(controller.loading, isFalse);
    expect(controller.error, isNotNull);

    store.entry = _makeEntry('book-2', epub.path);
    await controller.retry();

    expect(controller.loading, isFalse);
    expect(controller.error, isNull);
    expect(controller.chapters, isNotEmpty);
  });

  test('ReaderController searchMatches finds snippet', () async {
    final epub = await _writeTestEpub('Chapter One');
    final store = _FakeLibraryStore(_makeEntry('book-3', epub.path));
    final controller = ReaderController(store: store, perfLogsEnabled: false);

    await controller.load('book-3');

    final results = controller.searchMatches('Hello');

    expect(results, isNotEmpty);
    expect(results.first.snippet.toLowerCase(), contains('hello'));
    expect(results.first.chapterIndex, 0);
    expect(results.first.offset, greaterThanOrEqualTo(0));
  });
}
