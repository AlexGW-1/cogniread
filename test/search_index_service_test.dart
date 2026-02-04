import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/search/book_text_extractor.dart';
import 'package:cogniread/src/features/search/search_index_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

class _FakeLibraryStore extends LibraryStore {
  _FakeLibraryStore(this._entries)
      : _byId = <String, LibraryEntry>{for (final entry in _entries) entry.id: entry};

  final List<LibraryEntry> _entries;
  final Map<String, LibraryEntry> _byId;

  @override
  Future<void> init() async {}

  @override
  Future<List<LibraryEntry>> loadAll() async => _entries;

  @override
  Future<LibraryEntry?> getById(String id) async => _byId[id];
}

class _FakeBookTextExtractor implements BookTextExtractor {
  _FakeBookTextExtractor(this._chapters);

  final List<ExtractedChapter> _chapters;

  @override
  Future<List<ExtractedChapter>> extract(LibraryEntry entry) async => _chapters;
}

class _FakeBookTextExtractorByBookId implements BookTextExtractor {
  _FakeBookTextExtractorByBookId(this._byBookId);

  final Map<String, List<ExtractedChapter>> _byBookId;

  @override
  Future<List<ExtractedChapter>> extract(LibraryEntry entry) async {
    return _byBookId[entry.id] ?? const <ExtractedChapter>[];
  }
}

LibraryEntry _entryWithMarks({
  required String bookId,
  required Note note,
  required Highlight highlight,
}) {
  return LibraryEntry(
    id: bookId,
    title: 'Book',
    author: 'Author',
    localPath: '/tmp/book.epub',
    coverPath: null,
    addedAt: DateTime(2026, 1, 1),
    fingerprint: 'fp',
    sourcePath: '/tmp/source.epub',
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
    notes: <Note>[note],
    highlights: <Highlight>[highlight],
    bookmarks: const <Bookmark>[],
  );
}

void main() {
  test('SearchIndexService init creates schema and status', () async {
    final db = sqlite3.openInMemory();
    final service = SearchIndexService(database: db);

    final status = await service.status();

    expect(status.schemaVersion, equals(SearchIndexService.schemaVersion));
    expect(status.lastError, isNull);
  });

  test('SearchIndexService rebuildMarksIndex indexes notes and highlights', () async {
    final note = Note(
      id: 'n1',
      bookId: 'b1',
      anchor: 'index:0|0',
      endOffset: 10,
      excerpt: 'excerpt',
      noteText: 'hello world',
      color: 'yellow',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final highlight = Highlight(
      id: 'h1',
      bookId: 'b1',
      anchor: 'index:0|5',
      endOffset: 20,
      excerpt: 'highlighted world',
      color: 'yellow',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final store = _FakeLibraryStore(
      <LibraryEntry>[
        _entryWithMarks(bookId: 'b1', note: note, highlight: highlight),
      ],
    );
    final db = sqlite3.openInMemory();
    final service = SearchIndexService(store: store, database: db);

    await service.rebuildMarksIndex();
    final results = await service.search('world');

    expect(results.length, equals(2));
    expect(results.map((hit) => hit.bookId).toSet(), equals(<String>{'b1'}));
    expect(results.map((hit) => hit.markId).toSet(), containsAll(<String>{'n1', 'h1'}));
  });

  test('SearchIndexService rebuildBooksIndex writes fts_books rows', () async {
    final entry = _entryWithMarks(
      bookId: 'b1',
      note: Note(
        id: 'n1',
        bookId: 'b1',
        anchor: 'index:0|0',
        endOffset: 10,
        excerpt: 'excerpt',
        noteText: 'hello world',
        color: 'yellow',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      highlight: Highlight(
        id: 'h1',
        bookId: 'b1',
        anchor: 'index:0|5',
        endOffset: 20,
        excerpt: 'highlighted world',
        color: 'yellow',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    final store = _FakeLibraryStore(<LibraryEntry>[entry]);
    final extractor = _FakeBookTextExtractor(
      const <ExtractedChapter>[
        ExtractedChapter(
          title: 'Ch1',
          href: 'index:0',
          paragraphs: <String>['Hello ', 'world'],
        ),
      ],
    );
    final db = sqlite3.openInMemory();
    final service = SearchIndexService(
      store: store,
      database: db,
      bookTextExtractor: extractor,
    );

    await service.rebuildBooksIndex();

    final rows = db.select('SELECT book_id, chapter_href, content FROM fts_books');
    expect(rows.length, equals(2));
    expect(rows.map((r) => r['book_id']).toSet(), equals(<String>{'b1'}));
    expect(rows.map((r) => r['chapter_href']).toSet(), equals(<String>{'index:0'}));
  });

  test('SearchIndexService rebuildBooksIndex keeps anchor offsets consistent with skipped whitespace', () async {
    final entry = LibraryEntry(
      id: 'b1',
      title: 'Book',
      author: 'Author',
      localPath: '/tmp/book.epub',
      coverPath: null,
      addedAt: DateTime(2026, 1, 1),
      fingerprint: 'fp',
      sourcePath: '/tmp/source.epub',
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
    );
    final store = _FakeLibraryStore(<LibraryEntry>[entry]);
    final extractor = _FakeBookTextExtractor(
      const <ExtractedChapter>[
        ExtractedChapter(
          title: 'T',
          href: 'index:0',
          paragraphs: <String>['A', '   ', 'B'],
        ),
      ],
    );
    final db = sqlite3.openInMemory();
    final service = SearchIndexService(
      store: store,
      database: db,
      bookTextExtractor: extractor,
    );

    await service.rebuildBooksIndex();

    final rows = db.select(
      'SELECT content, anchor FROM fts_books WHERE book_id = ? ORDER BY paragraph_index ASC',
      <Object?>['b1'],
    );
    expect(rows.length, equals(2));
    expect(rows.first['content'], equals('A'));
    expect(rows.first['anchor'], equals('index:0|1'));
    expect(rows.last['content'], equals('B'));
    expect(rows.last['anchor'], equals('index:0|5'));
  });

  test('SearchIndexService indexBook writes book, marks and state rows', () async {
    final entry = _entryWithMarks(
      bookId: 'b1',
      note: Note(
        id: 'n1',
        bookId: 'b1',
        anchor: 'index:0|0',
        endOffset: 10,
        excerpt: 'excerpt',
        noteText: 'hello world',
        color: 'yellow',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      highlight: Highlight(
        id: 'h1',
        bookId: 'b1',
        anchor: 'index:0|5',
        endOffset: 20,
        excerpt: 'highlighted world',
        color: 'yellow',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    final store = _FakeLibraryStore(<LibraryEntry>[entry]);
    final extractor = _FakeBookTextExtractor(
      const <ExtractedChapter>[
        ExtractedChapter(
          title: 'Ch1',
          href: 'index:0',
          paragraphs: <String>['Hello ', 'world'],
        ),
      ],
    );
    final db = sqlite3.openInMemory();
    final service = SearchIndexService(
      store: store,
      database: db,
      bookTextExtractor: extractor,
    );

    await service.indexBook('b1');

    expect(db.select('SELECT * FROM fts_books').length, equals(2));
    expect(db.select('SELECT * FROM fts_marks').length, equals(2));
    final state = db.select('SELECT fingerprint FROM search_books_state WHERE book_id = ?', <Object?>['b1']);
    expect(state, isNotEmpty);
    expect(state.first['fingerprint'], equals('fp'));
  });

  test('SearchIndexService deleteBook removes book, marks and state rows', () async {
    final entry = _entryWithMarks(
      bookId: 'b1',
      note: Note(
        id: 'n1',
        bookId: 'b1',
        anchor: 'index:0|0',
        endOffset: 10,
        excerpt: 'excerpt',
        noteText: 'hello world',
        color: 'yellow',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      highlight: Highlight(
        id: 'h1',
        bookId: 'b1',
        anchor: 'index:0|5',
        endOffset: 20,
        excerpt: 'highlighted world',
        color: 'yellow',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    final store = _FakeLibraryStore(<LibraryEntry>[entry]);
    final extractor = _FakeBookTextExtractor(
      const <ExtractedChapter>[
        ExtractedChapter(
          title: 'Ch1',
          href: 'index:0',
          paragraphs: <String>['Hello ', 'world'],
        ),
      ],
    );
    final db = sqlite3.openInMemory();
    final service = SearchIndexService(
      store: store,
      database: db,
      bookTextExtractor: extractor,
    );
    await service.indexBook('b1');

    await service.deleteBook('b1');

    expect(db.select('SELECT * FROM fts_books').length, equals(0));
    expect(db.select('SELECT * FROM fts_marks').length, equals(0));
    expect(
      db.select('SELECT * FROM search_books_state WHERE book_id = ?', <Object?>['b1']),
      isEmpty,
    );
  });

  test('SearchIndexService searchBooksText ranks title matches above content', () async {
    final entryContentMatch = LibraryEntry(
      id: 'b1',
      title: 'Other',
      author: 'Author',
      localPath: '/tmp/book.epub',
      coverPath: null,
      addedAt: DateTime(2026, 1, 1),
      fingerprint: 'fp1',
      sourcePath: '/tmp/source.epub',
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
    );
    final entryTitleMatch = LibraryEntry(
      id: 'b2',
      title: 'Special',
      author: 'Author',
      localPath: '/tmp/book.epub',
      coverPath: null,
      addedAt: DateTime(2026, 1, 1),
      fingerprint: 'fp2',
      sourcePath: '/tmp/source.epub',
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
    );
    final store = _FakeLibraryStore(<LibraryEntry>[
      entryContentMatch,
      entryTitleMatch,
    ]);
    final extractor = _FakeBookTextExtractorByBookId({
      'b1': const <ExtractedChapter>[
        ExtractedChapter(
          title: 'Ch',
          href: 'index:0',
          paragraphs: <String>['special is in content'],
        ),
      ],
      'b2': const <ExtractedChapter>[
        ExtractedChapter(
          title: 'Ch',
          href: 'index:0',
          paragraphs: <String>['content without keyword'],
        ),
      ],
    });
    final db = sqlite3.openInMemory();
    final service = SearchIndexService(
      store: store,
      database: db,
      bookTextExtractor: extractor,
    );

    await service.rebuildBooksIndex();
    final hits = await service.searchBooksText('special', limit: 10);

    expect(hits, isNotEmpty);
    expect(hits.first.bookId, equals('b2'));
  });

  test('SearchIndexService reconcileWithLibrary deletes missing and reindexes changed', () async {
    final entry = _entryWithMarks(
      bookId: 'b1',
      note: Note(
        id: 'n1',
        bookId: 'b1',
        anchor: 'index:0|0',
        endOffset: 10,
        excerpt: 'excerpt',
        noteText: 'hello world',
        color: 'yellow',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      highlight: Highlight(
        id: 'h1',
        bookId: 'b1',
        anchor: 'index:0|5',
        endOffset: 20,
        excerpt: 'highlighted world',
        color: 'yellow',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    final store = _FakeLibraryStore(<LibraryEntry>[entry]);
    final extractor = _FakeBookTextExtractor(
      const <ExtractedChapter>[
        ExtractedChapter(
          title: 'Ch1',
          href: 'index:0',
          paragraphs: <String>['Hello ', 'world'],
        ),
      ],
    );
    final db = sqlite3.openInMemory();
    final service = SearchIndexService(
      store: store,
      database: db,
      bookTextExtractor: extractor,
    );
    await service.status();

    db.execute(
      'INSERT OR REPLACE INTO search_books_state(book_id, fingerprint, indexed_at) '
      'VALUES (?, ?, ?)',
      <Object?>['b1', 'old', '2026-01-01T00:00:00Z'],
    );
    db.execute(
      'INSERT OR REPLACE INTO search_books_state(book_id, fingerprint, indexed_at) '
      'VALUES (?, ?, ?)',
      <Object?>['ghost', 'fp', '2026-01-01T00:00:00Z'],
    );
    db.execute(
      'INSERT INTO fts_books(book_id, book_title, book_author, chapter_title, content, anchor, chapter_href, chapter_index, paragraph_index) '
      "VALUES ('ghost', 'x', 'x', 'x', 'x', 'index:0|0', 'index:0', 0, 0)",
    );

    await service.reconcileWithLibrary(reindexMarks: true);

    expect(
      db.select('SELECT * FROM search_books_state WHERE book_id = ?', <Object?>['ghost']),
      isEmpty,
    );
    final state = db.select('SELECT fingerprint FROM search_books_state WHERE book_id = ?', <Object?>['b1']);
    expect(state, isNotEmpty);
    expect(state.first['fingerprint'], equals('fp'));
    expect(db.select('SELECT * FROM fts_books WHERE book_id = ?', <Object?>['b1']).length, equals(2));
    expect(db.select('SELECT * FROM fts_marks WHERE book_id = ?', <Object?>['b1']).length, equals(2));
  });

  test('SearchIndexService upgrades schema when schemaVersion changes', () async {
    final db = sqlite3.openInMemory();
    db.execute(
      'CREATE TABLE search_meta ('
      '  id INTEGER PRIMARY KEY CHECK (id = 1),'
      '  schema_version INTEGER NOT NULL,'
      '  last_rebuild_at TEXT NULL,'
      '  last_error TEXT NULL'
      ')',
    );
    db.execute('INSERT INTO search_meta(id, schema_version) VALUES (1, 0)');
    db.execute(
      'CREATE VIRTUAL TABLE IF NOT EXISTS fts_marks USING fts5('
      '  book_id UNINDEXED,'
      '  mark_id UNINDEXED,'
      '  mark_type UNINDEXED,'
      '  anchor UNINDEXED,'
      '  content'
      ')',
    );

    final service = SearchIndexService(database: db);
    final status = await service.status();

    expect(status.schemaVersion, equals(SearchIndexService.schemaVersion));
    final table = db.select(
      "SELECT name FROM sqlite_master WHERE type IN ('table','view') AND name = 'fts_marks'",
    );
    expect(table, isNotEmpty);
  });
}
