import 'dart:io';
import 'dart:isolate';

import 'package:cogniread/src/core/types/anchor.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/search/indexing/search_index_books_text_extractor.dart';
import 'package:sqlite3/sqlite3.dart';

const _typeReady = 'ready';
const _typeProgress = 'progress';
const _typeDone = 'done';
const _typeCanceled = 'canceled';
const _typeError = 'error';
const _typeBookError = 'book_error';

void rebuildSearchBooksIndexIsolate(Map<String, Object?> args) {
  final sendPort = args['sendPort'] as SendPort?;
  if (sendPort == null) {
    return;
  }

  final control = ReceivePort();
  var canceled = false;
  control.listen((message) {
    if (message == 'cancel') {
      canceled = true;
    }
  });
  sendPort.send(<String, Object?>{
    'type': _typeReady,
    'controlPort': control.sendPort,
  });

  final outputPath = args['outputPath'] as String? ?? '';
  final schemaVersion = args['schemaVersion'] as int? ?? 1;
  final booksRaw = (args['books'] as List?) ?? const <Object?>[];
  final books = booksRaw
      .whereType<Map<String, Object?>>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);

  Database? db;
  final watch = Stopwatch()..start();
  var insertedRows = 0;

  void reportProgress({
    required int processedBooks,
    required int totalBooks,
    required String stage,
    String? currentTitle,
    int? currentBookIndex,
  }) {
    sendPort.send(<String, Object?>{
      'type': _typeProgress,
      'processedBooks': processedBooks,
      'totalBooks': totalBooks,
      'stage': stage,
      'currentTitle': currentTitle,
      'currentBookIndex': currentBookIndex,
      'insertedRows': insertedRows,
      'elapsedMs': watch.elapsedMilliseconds,
    });
  }

  void reportBookError({
    required String bookId,
    required String title,
    required int bookIndex,
    required Object error,
  }) {
    final displayTitle = title.trim().isEmpty ? bookId : title;
    final message = 'Пропустили книгу "$displayTitle": ${error.toString()}';
    Log.d('Search index rebuild skipped book $bookId: $error');
    sendPort.send(<String, Object?>{
      'type': _typeBookError,
      'processedBooks': bookIndex,
      'totalBooks': books.length,
      'stage': 'book-error',
      'currentTitle': title,
      'message': message,
      'elapsedMs': watch.elapsedMilliseconds,
      'insertedRows': insertedRows,
    });
  }

  void cleanupTemp() {
    try {
      File(outputPath).deleteSync();
    } catch (_) {}
  }

  try {
    if (outputPath.trim().isEmpty) {
      throw StateError('outputPath is empty');
    }
    try {
      File(outputPath).deleteSync();
    } catch (_) {}
    db = sqlite3.open(outputPath);
    _configureRebuildDatabase(db);
    _ensureSchema(db, schemaVersion: schemaVersion);

    final totalBooks = books.length;
    reportProgress(processedBooks: 0, totalBooks: totalBooks, stage: 'init');

    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM fts_books');
      final stmt = db.prepare(
        'INSERT INTO fts_books('
        '  book_id, book_title, book_author, chapter_title, '
        '  content, anchor, chapter_href, chapter_index, paragraph_index'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      try {
        booksLoop:
        for (var bookIndex = 0; bookIndex < totalBooks; bookIndex += 1) {
          if (canceled) {
            throw const _Canceled();
          }
          final book = books[bookIndex];
          final bookId = book['id'] as String? ?? '';
          final title = book['title'] as String? ?? '';
          final author = book['author'] as String? ?? '';
          final localPath = book['localPath'] as String? ?? '';
          final tocMode = book['tocMode'] as String? ?? 'official';
          final hasStoredToc = book['hasStoredToc'] == true;

          reportProgress(
            processedBooks: bookIndex,
            totalBooks: totalBooks,
            stage: 'book',
            currentTitle: title,
            currentBookIndex: bookIndex,
          );

          var bookInsertedRows = 0;
          try {
            final chapters = SearchIndexBookTextExtractor.extractFromFile(
              localPath,
              tocMode: tocMode,
              hasStoredToc: hasStoredToc,
            );

            for (
              var chapterIndex = 0;
              chapterIndex < chapters.length;
              chapterIndex += 1
            ) {
              if (canceled) {
                throw const _Canceled();
              }
              final chapter = chapters[chapterIndex];
              final chapterTitle = chapter.title;
              final paragraphs = chapter.paragraphs;
              var offset = chapterTitle.length;
              for (
                var paragraphIndex = 0;
                paragraphIndex < paragraphs.length;
                paragraphIndex += 1
              ) {
                if (canceled) {
                  throw const _Canceled();
                }
                final paragraph = paragraphs[paragraphIndex];
                if (paragraph.trim().isEmpty) {
                  offset += paragraph.length;
                  continue;
                }
                final chapterHref = chapter.href;
                final anchor = Anchor(
                  chapterHref: chapterHref,
                  offset: offset,
                ).toString();
                stmt.execute(<Object?>[
                  bookId,
                  title,
                  author,
                  chapterTitle,
                  paragraph,
                  anchor,
                  chapterHref,
                  chapterIndex,
                  paragraphIndex,
                ]);
                bookInsertedRows += 1;
                offset += paragraph.length;
              }
            }
          } catch (error) {
            reportBookError(
              bookId: bookId,
              title: title,
              bookIndex: bookIndex,
              error: error,
            );
            try {
              db.execute('DELETE FROM fts_books WHERE book_id = ?', <Object?>[
                bookId,
              ]);
            } catch (_) {}
            continue booksLoop;
          }

          insertedRows += bookInsertedRows;

          if (bookIndex % 2 == 0) {
            reportProgress(
              processedBooks: bookIndex + 1,
              totalBooks: totalBooks,
              stage: 'book',
              currentTitle: title,
              currentBookIndex: bookIndex,
            );
          }
        }
      } finally {
        stmt.dispose();
      }

      final now = DateTime.now().toUtc();
      db.execute(
        'UPDATE search_meta '
        'SET last_rebuild_at = ?, last_rebuild_ms = ?, books_rows = ?, last_error = NULL '
        'WHERE id = 1',
        <Object?>[
          now.toIso8601String(),
          watch.elapsedMilliseconds,
          insertedRows,
        ],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }

    watch.stop();
    sendPort.send(<String, Object?>{
      'type': _typeDone,
      'insertedRows': insertedRows,
      'elapsedMs': watch.elapsedMilliseconds,
    });
  } on _Canceled {
    cleanupTemp();
    sendPort.send(<String, Object?>{'type': _typeCanceled});
  } catch (error) {
    cleanupTemp();
    sendPort.send(<String, Object?>{
      'type': _typeError,
      'error': error.toString(),
    });
  } finally {
    try {
      db?.dispose();
    } catch (_) {}
    control.close();
  }
}

class _Canceled implements Exception {
  const _Canceled();
}

void _configureRebuildDatabase(Database db) {
  try {
    db.execute('PRAGMA busy_timeout = 3000');
  } catch (_) {}
  try {
    db.execute('PRAGMA journal_mode = DELETE');
  } catch (_) {}
  try {
    db.execute('PRAGMA synchronous = OFF');
  } catch (_) {}
  try {
    db.execute('PRAGMA temp_store = MEMORY');
  } catch (_) {}
}

void _ensureSchema(Database db, {required int schemaVersion}) {
  db.execute(
    'CREATE TABLE IF NOT EXISTS search_meta ('
    '  id INTEGER PRIMARY KEY CHECK (id = 1),'
    '  schema_version INTEGER NOT NULL,'
    '  last_rebuild_at TEXT NULL,'
    '  last_rebuild_ms INTEGER NULL,'
    '  marks_rows INTEGER NULL,'
    '  books_rows INTEGER NULL,'
    '  last_error TEXT NULL'
    ')',
  );
  db.execute(
    'INSERT OR IGNORE INTO search_meta(id, schema_version) VALUES (1, ?)',
    <Object?>[schemaVersion],
  );
  db.execute(
    'CREATE VIRTUAL TABLE IF NOT EXISTS fts_marks USING fts5('
    '  book_id UNINDEXED,'
    '  mark_id UNINDEXED,'
    '  mark_type UNINDEXED,'
    '  anchor UNINDEXED,'
    '  content'
    ')',
  );
  db.execute(
    'CREATE VIRTUAL TABLE IF NOT EXISTS fts_books USING fts5('
    '  book_id UNINDEXED,'
    '  book_title,'
    '  book_author,'
    '  chapter_title,'
    '  content,'
    '  anchor UNINDEXED,'
    '  chapter_href UNINDEXED,'
    '  chapter_index UNINDEXED,'
    '  paragraph_index UNINDEXED'
    ')',
  );
  db.execute(
    'CREATE TABLE IF NOT EXISTS search_books_state ('
    '  book_id TEXT PRIMARY KEY,'
    '  fingerprint TEXT NOT NULL,'
    '  indexed_at TEXT NULL'
    ')',
  );
}
