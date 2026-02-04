import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/search/book_text_extractor.dart';
import 'package:cogniread/src/features/search/presentation/global_search_sheet.dart';
import 'package:cogniread/src/features/search/search_index_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

class _FakeLibraryStore extends LibraryStore {
  _FakeLibraryStore(this._entries)
    : _byId = <String, LibraryEntry>{
        for (final entry in _entries) entry.id: entry,
      };

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

Future<SearchIndexService> _seedIndex() async {
  final note = Note(
    id: 'n1',
    bookId: 'b1',
    anchor: 'index:0|0',
    endOffset: 10,
    excerpt: 'excerpt',
    noteText: 'note about world',
    color: 'yellow',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
  final highlight = Highlight(
    id: 'h1',
    bookId: 'b1',
    anchor: 'index:0|5',
    endOffset: 20,
    excerpt: 'world highlight',
    color: 'yellow',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
  final entry = LibraryEntry(
    id: 'b1',
    title: 'Book Title',
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
  final store = _FakeLibraryStore(<LibraryEntry>[entry]);
  final extractor = _FakeBookTextExtractor(const <ExtractedChapter>[
    ExtractedChapter(
      title: 'Ch1',
      href: 'index:0',
      paragraphs: <String>['hello world'],
    ),
  ]);
  final db = sqlite3.openInMemory();
  final service = SearchIndexService(
    store: store,
    database: db,
    bookTextExtractor: extractor,
  );
  await service.rebuildBooksIndex();
  await service.rebuildMarksIndex();
  return service;
}

class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.searchIndex, required this.onOpen});

  final SearchIndexService searchIndex;
  final void Function(
    String bookId, {
    String? initialNoteId,
    String? initialHighlightId,
    String? initialAnchor,
    String? initialSearchQuery,
  })
  onOpen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const ValueKey('open-global-search-v2'),
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => GlobalSearchSheet(
                    searchIndex: searchIndex,
                    resolveBookTitle: (_) => 'Book Title',
                    resolveBookAuthor: (_) => 'Author',
                    onOpen: onOpen,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Books tab searches and opens book', (tester) async {
    final searchIndex = await _seedIndex();
    String? openedBookId;
    String? openedAnchor;

    await tester.pumpWidget(
      _SheetHost(
        searchIndex: searchIndex,
        onOpen:
            (
              bookId, {
              initialAnchor,
              initialHighlightId,
              initialNoteId,
              initialSearchQuery,
            }) {
              openedBookId = bookId;
              openedAnchor = initialAnchor;
              expect(initialSearchQuery, equals('world'));
            },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-global-search-v2')));
    await tester.pumpAndSettle();

    expect(find.text('Введите запрос для поиска.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('global-search-v2-field')),
      'world',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Book Title'), findsOneWidget);

    await tester.tap(find.text('Book Title'));
    await tester.pumpAndSettle();

    expect(openedBookId, equals('b1'));
    expect(openedAnchor, equals('index:0|3'));
  });

  testWidgets('Notes tab searches and opens note', (tester) async {
    final searchIndex = await _seedIndex();
    String? openedBookId;
    String? openedNoteId;
    String? openedHighlightId;
    String? openedAnchor;

    await tester.pumpWidget(
      _SheetHost(
        searchIndex: searchIndex,
        onOpen:
            (
              bookId, {
              initialAnchor,
              initialHighlightId,
              initialNoteId,
              initialSearchQuery,
            }) {
              openedBookId = bookId;
              openedNoteId = initialNoteId;
              openedHighlightId = initialHighlightId;
              openedAnchor = initialAnchor;
            },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-global-search-v2')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-search-v2-field')),
      'world',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Заметка', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.sticky_note_2_outlined));
    await tester.pumpAndSettle();

    expect(openedBookId, equals('b1'));
    expect(openedNoteId, equals('n1'));
    expect(openedHighlightId, isNull);
    expect(openedAnchor, equals('index:0|0'));
  });

  testWidgets('Quotes tab searches and opens highlight', (tester) async {
    final searchIndex = await _seedIndex();
    String? openedBookId;
    String? openedNoteId;
    String? openedHighlightId;
    String? openedAnchor;

    await tester.pumpWidget(
      _SheetHost(
        searchIndex: searchIndex,
        onOpen:
            (
              bookId, {
              initialAnchor,
              initialHighlightId,
              initialNoteId,
              initialSearchQuery,
            }) {
              openedBookId = bookId;
              openedNoteId = initialNoteId;
              openedHighlightId = initialHighlightId;
              openedAnchor = initialAnchor;
            },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-global-search-v2')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-search-v2-field')),
      'world',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Quotes'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Цитата', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.format_quote_outlined));
    await tester.pumpAndSettle();

    expect(openedBookId, equals('b1'));
    expect(openedNoteId, isNull);
    expect(openedHighlightId, equals('h1'));
    expect(openedAnchor, equals('index:0|5'));
  });
}
