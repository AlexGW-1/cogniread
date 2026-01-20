import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/core/types/anchor.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/search/book_text_extractor.dart';
import 'package:cogniread/src/features/search/indexing/search_index_books_rebuild_isolate.dart';
import 'package:cogniread/src/features/search/search_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class SearchIndexBooksRebuildProgress {
  const SearchIndexBooksRebuildProgress({
    required this.processedBooks,
    required this.totalBooks,
    required this.stage,
    required this.insertedRows,
    required this.elapsedMs,
    this.currentTitle,
  });

  final int processedBooks;
  final int totalBooks;
  final String stage;
  final int insertedRows;
  final int elapsedMs;
  final String? currentTitle;

  double? get fraction {
    if (totalBooks <= 0) {
      return null;
    }
    if (processedBooks <= 0) {
      return 0;
    }
    return processedBooks / totalBooks;
  }
}

class SearchIndexBooksRebuildHandle {
  const SearchIndexBooksRebuildHandle({
    required this.progress,
    required this.done,
    required this.cancel,
  });

  final Stream<SearchIndexBooksRebuildProgress> progress;
  final Future<void> done;
  final Future<void> Function() cancel;
}

class SearchIndexService {
  factory SearchIndexService({
    LibraryStore? store,
    String fileName = 'search_index.sqlite',
    Database? database,
    BookTextExtractor? bookTextExtractor,
  }) {
    final effectiveStore = store ?? LibraryStore();
    return SearchIndexService._(
      store: effectiveStore,
      bookTextExtractor:
          bookTextExtractor ?? ReaderBookTextExtractor(store: effectiveStore),
      fileName: fileName,
      database: database,
    );
  }

  SearchIndexService._({
    required LibraryStore store,
    required BookTextExtractor bookTextExtractor,
    required String fileName,
    required Database? database,
  })  : _store = store,
        _bookTextExtractor = bookTextExtractor,
        _fileName = fileName,
        _database = database;

  static const int schemaVersion = 1;
  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

  final LibraryStore _store;
  final BookTextExtractor _bookTextExtractor;
  final String _fileName;
  String? _dbPath;
  Database? _database;

  Database get _db {
    final db = _database;
    if (db == null) {
      throw StateError('SearchIndexService not initialized');
    }
    return db;
  }

  Future<void> init() async {
    if (_database != null) {
      _configureDatabase(_db);
      await _ensureSchema();
      return;
    }
    if (_isFlutterTest) {
      _database = sqlite3.openInMemory();
      _configureDatabase(_db);
      await _ensureSchema();
      return;
    }
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, _fileName);
    await Directory(dir.path).create(recursive: true);
    _dbPath = path;
    await _openOrRecreate(path);
  }

  void close() {
    final db = _database;
    if (db == null) {
      return;
    }
    db.dispose();
    _database = null;
  }

  Future<File?> exportSnapshot({String? fileName}) async {
    await init();
    final targetName = (fileName == null || fileName.trim().isEmpty)
        ? 'search_index_snapshot.sqlite'
        : fileName.trim();
    final dir =
        _dbPath == null
            ? await getApplicationSupportDirectory()
            : Directory(p.dirname(_dbPath!));
    await dir.create(recursive: true);
    final path = p.join(dir.path, targetName);

    try {
      final escaped = path.replaceAll("'", "''");
      _db.execute("VACUUM INTO '$escaped'");
      final file = File(path);
      return await file.exists() ? file : null;
    } catch (error) {
      Log.d('Search index snapshot export failed: $error');
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    return null;
  }

  Future<SearchIndexStatus> status() async {
    await init();
    late final Row row;
    try {
      row =
          _db.select(
            'SELECT schema_version, last_rebuild_at, last_rebuild_ms, marks_rows, books_rows, last_error '
            'FROM search_meta WHERE id = 1',
          ).first;
    } catch (error) {
      Log.d('Search index status read failed: $error');
      await _recreateIndexFile();
      row =
          _db.select(
            'SELECT schema_version, last_rebuild_at, last_rebuild_ms, marks_rows, books_rows, last_error '
            'FROM search_meta WHERE id = 1',
          ).first;
    }
    final version = row['schema_version'] as int;
    final rebuildRaw = row['last_rebuild_at'] as String?;
    final lastRebuildMs = row['last_rebuild_ms'] as int?;
    final marksRows = row['marks_rows'] as int?;
    final booksRows = row['books_rows'] as int?;
    final lastError = row['last_error'] as String?;
    return SearchIndexStatus(
      schemaVersion: version,
      lastRebuildAt: rebuildRaw == null ? null : DateTime.tryParse(rebuildRaw),
      lastRebuildMs: lastRebuildMs,
      marksRows: marksRows,
      booksRows: booksRows,
      lastError: lastError == null || lastError.trim().isEmpty
          ? null
          : lastError.trim(),
      dbPath: _dbPath,
    );
  }

  Future<void> rebuildMarksIndex() async {
    await init();
    final watch = Stopwatch()..start();
    final now = DateTime.now().toUtc();
    try {
      await _store.init();
      final entries = await _store.loadAll();
      var inserted = 0;
      _db.execute('BEGIN');
      try {
        _db.execute('DELETE FROM fts_marks');
        final stmt = _db.prepare(
          'INSERT INTO fts_marks(book_id, mark_id, mark_type, anchor, content) '
          'VALUES (?, ?, ?, ?, ?)',
        );
        try {
          for (final entry in entries) {
            for (final note in entry.notes) {
              final content = _noteContent(note);
              if (content.isEmpty) {
                continue;
              }
              inserted += 1;
              stmt.execute(<Object?>[
                entry.id,
                note.id,
                'note',
                note.anchor,
                content,
              ]);
            }
            for (final highlight in entry.highlights) {
              final content = highlight.excerpt.trim();
              if (content.isEmpty) {
                continue;
              }
              inserted += 1;
              stmt.execute(<Object?>[
                entry.id,
                highlight.id,
                'highlight',
                highlight.anchor,
                content,
              ]);
            }
          }
        } finally {
          stmt.dispose();
        }
        watch.stop();
        _db.execute(
          'UPDATE search_meta '
          'SET last_rebuild_at = ?, last_rebuild_ms = ?, marks_rows = ?, last_error = NULL '
          'WHERE id = 1',
          <Object?>[
            now.toIso8601String(),
            watch.elapsedMilliseconds,
            inserted,
          ],
        );
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    } catch (error) {
      Log.d('Search index rebuild failed: $error');
      _db.execute(
        'UPDATE search_meta '
        'SET last_error = ? '
        'WHERE id = 1',
        <Object?>[error.toString()],
      );
      rethrow;
    }
  }

  Future<void> rebuildBooksIndex({
    int maxBooks = 0,
    int maxParagraphsPerBook = 0,
  }) async {
    await init();
    final watch = Stopwatch()..start();
    final now = DateTime.now().toUtc();
    try {
      await _store.init();
      final entries = await _store.loadAll();
      var inserted = 0;
      var processed = 0;
      _db.execute('BEGIN');
      try {
        _db.execute('DELETE FROM fts_books');
        final stmt = _db.prepare(
          'INSERT INTO fts_books('
          '  book_id, book_title, book_author, chapter_title, '
          '  content, anchor, chapter_href, chapter_index, paragraph_index'
          ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        );
        try {
          for (final entry in entries) {
            if (maxBooks > 0 && processed >= maxBooks) {
              break;
            }
            processed += 1;
            final chapters = await _bookTextExtractor.extract(entry);
            var bookParagraphs = 0;
            for (var chapterIndex = 0;
                chapterIndex < chapters.length;
                chapterIndex += 1) {
              final chapter = chapters[chapterIndex];
              final chapterTitle = chapter.title;
              final paragraphs = chapter.paragraphs;
              var offset = chapterTitle.length;
              for (var paragraphIndex = 0;
                  paragraphIndex < paragraphs.length;
                  paragraphIndex += 1) {
                if (maxParagraphsPerBook > 0 &&
                    bookParagraphs >= maxParagraphsPerBook) {
                  break;
                }
                final paragraph = paragraphs[paragraphIndex];
                if (paragraph.trim().isEmpty) {
                  offset += paragraph.length;
                  continue;
                }
                final anchor = Anchor(
                  chapterHref: chapter.href,
                  offset: offset,
                ).toString();
                stmt.execute(<Object?>[
                  entry.id,
                  entry.title,
                  entry.author ?? '',
                  chapterTitle,
                  paragraph,
                  anchor,
                  chapter.href,
                  chapterIndex,
                  paragraphIndex,
                ]);
                inserted += 1;
                bookParagraphs += 1;
                offset += paragraph.length;
              }
            }
          }
        } finally {
          stmt.dispose();
        }
        watch.stop();
        _db.execute(
          'UPDATE search_meta '
          'SET last_rebuild_at = ?, last_rebuild_ms = ?, books_rows = ?, last_error = NULL '
          'WHERE id = 1',
          <Object?>[
            now.toIso8601String(),
            watch.elapsedMilliseconds,
            inserted,
          ],
        );
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    } catch (error) {
      Log.d('Search index books rebuild failed: $error');
      _db.execute(
        'UPDATE search_meta '
        'SET last_error = ? '
        'WHERE id = 1',
        <Object?>[error.toString()],
      );
      rethrow;
    }
  }

  Future<int> libraryBooksCount() async {
    await _store.init();
    final entries = await _store.loadAll();
    return entries.length;
  }

  Future<SearchIndexBooksRebuildHandle> startBooksRebuildInIsolate() async {
    await init();
    final dbPath = _dbPath;
    if (dbPath == null || dbPath.trim().isEmpty) {
      throw StateError('Search index file path is not available');
    }

    await _store.init();
    final entries = await _store.loadAll();
    final books = entries
        .map(
          (entry) => <String, Object?>{
            'id': entry.id,
            'title': entry.title,
            'author': entry.author ?? '',
            'localPath': entry.localPath,
            'tocMode': entry.tocMode.name,
            'hasStoredToc':
                entry.tocOfficial.isNotEmpty || entry.tocGenerated.isNotEmpty,
          },
        )
        .toList(growable: false);

    final receive = ReceivePort();
    SendPort? controlPort;
    var cancelRequested = false;
    final progress = StreamController<SearchIndexBooksRebuildProgress>.broadcast();
    final done = Completer<void>();
    Isolate? isolate;

    final buildingPath = '$dbPath.building';
    try {
      final building = File(buildingPath);
      if (await building.exists()) {
        await building.delete();
      }
    } catch (_) {}

    Future<void> finalizeSwap() async {
      progress.add(
        SearchIndexBooksRebuildProgress(
          processedBooks: books.length,
          totalBooks: books.length,
          stage: 'swap',
          insertedRows: 0,
          elapsedMs: 0,
        ),
      );
      await _swapIndexFile(buildingPath);
    }

    void completeWithError(Object error, [StackTrace? stackTrace]) {
      if (!done.isCompleted) {
        done.completeError(error, stackTrace);
      }
      progress.close();
      receive.close();
      try {
        isolate?.kill(priority: Isolate.immediate);
      } catch (_) {}
    }

    receive.listen((message) async {
      final map = message is Map ? Map<String, Object?>.from(message) : null;
      if (map == null) {
        return;
      }
      final type = map['type'] as String?;
      switch (type) {
        case 'ready':
          controlPort = map['controlPort'] as SendPort?;
          if (cancelRequested) {
            controlPort?.send('cancel');
          }
          break;
        case 'progress':
          progress.add(
            SearchIndexBooksRebuildProgress(
              processedBooks: (map['processedBooks'] as int?) ?? 0,
              totalBooks: (map['totalBooks'] as int?) ?? 0,
              stage: (map['stage'] as String?) ?? 'book',
              insertedRows: (map['insertedRows'] as int?) ?? 0,
              elapsedMs: (map['elapsedMs'] as int?) ?? 0,
              currentTitle: map['currentTitle'] as String?,
            ),
          );
          break;
        case 'done':
          try {
            await finalizeSwap();
            if (!done.isCompleted) {
              done.complete();
            }
            await progress.close();
            receive.close();
          } catch (error, stackTrace) {
            completeWithError(error, stackTrace);
          } finally {
            try {
              isolate?.kill(priority: Isolate.immediate);
            } catch (_) {}
          }
          break;
        case 'canceled':
          try {
            if (!done.isCompleted) {
              done.completeError(StateError('Rebuild canceled'));
            }
            await progress.close();
            receive.close();
          } finally {
            try {
              isolate?.kill(priority: Isolate.immediate);
            } catch (_) {}
          }
          break;
        case 'error':
          completeWithError(StateError(map['error']?.toString() ?? 'Rebuild failed'));
          break;
      }
    });

    isolate = await Isolate.spawn<Map<String, Object?>>(
      rebuildSearchBooksIndexIsolate,
      <String, Object?>{
        'sendPort': receive.sendPort,
        'outputPath': buildingPath,
        'schemaVersion': schemaVersion,
        'books': books,
      },
      errorsAreFatal: true,
    );

    Future<void> cancel() async {
      cancelRequested = true;
      controlPort?.send('cancel');
    }

    return SearchIndexBooksRebuildHandle(
      progress: progress.stream,
      done: done.future,
      cancel: cancel,
    );
  }

  Future<void> _swapIndexFile(String buildingPath) async {
    final dbPath = _dbPath;
    if (dbPath == null || dbPath.trim().isEmpty) {
      throw StateError('Search index file path is not available');
    }
    final building = File(buildingPath);
    if (!await building.exists()) {
      throw StateError('Rebuild output file missing: $buildingPath');
    }

    await init();
    try {
      _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    close();

    final original = File(dbPath);
    final backup = File('$dbPath.bak');
    final wal = File('$dbPath-wal');
    final shm = File('$dbPath-shm');

    Future<void> cleanupSidecars() async {
      try {
        if (await wal.exists()) {
          await wal.delete();
        }
      } catch (_) {}
      try {
        if (await shm.exists()) {
          await shm.delete();
        }
      } catch (_) {}
    }

    await cleanupSidecars();

    if (await backup.exists()) {
      try {
        await backup.delete();
      } catch (_) {}
    }

    final attempts = 5;
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      try {
        if (await original.exists()) {
          await original.rename(backup.path);
        }
        await building.rename(original.path);
        await cleanupSidecars();
        try {
          if (await backup.exists()) {
            await backup.delete();
          }
        } catch (_) {}
        await init();
        return;
      } catch (error) {
        if (attempt == attempts - 1) {
          try {
            if (await building.exists()) {
              await building.delete();
            }
          } catch (_) {}
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 80 * (attempt + 1)));
      }
    }
  }

  Future<void> indexBook(String bookId) async {
    await init();
    try {
      await _store.init();
      final entry = await _store.getById(bookId);
      if (entry == null) {
        return;
      }
      await _indexBookEntry(entry, reindexText: true, reindexMarks: true);
    } catch (error) {
      Log.d('Search index indexBook failed: $error');
      _setLastError(error);
    }
  }

  Future<void> indexMarksForBook(String bookId) async {
    await init();
    try {
      await _store.init();
      final entry = await _store.getById(bookId);
      if (entry == null) {
        return;
      }
      await _indexBookEntry(entry, reindexText: false, reindexMarks: true);
    } catch (error) {
      Log.d('Search index indexMarksForBook failed: $error');
      _setLastError(error);
    }
  }

  Future<void> deleteBook(String bookId) async {
    await init();
    try {
      _db.execute('BEGIN');
      try {
        _db.execute('DELETE FROM fts_books WHERE book_id = ?', <Object?>[bookId]);
        _db.execute('DELETE FROM fts_marks WHERE book_id = ?', <Object?>[bookId]);
        _db.execute(
          'DELETE FROM search_books_state WHERE book_id = ?',
          <Object?>[bookId],
        );
        _refreshRowCounts();
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    } catch (error) {
      Log.d('Search index deleteBook failed: $error');
      _setLastError(error);
    }
  }

  Future<void> reconcileWithLibrary({bool reindexMarks = true}) async {
    await init();
    try {
      await _store.init();
      final entries = await _store.loadAll();
      final current = <String, LibraryEntry>{
        for (final entry in entries) entry.id: entry,
      };

      final indexed = <String, String>{};
      final rows = _db.select('SELECT book_id, fingerprint FROM search_books_state');
      for (final row in rows) {
        indexed[row['book_id'] as String] = row['fingerprint'] as String;
      }

      final toDelete = indexed.keys.where((id) => !current.containsKey(id)).toList();
      for (final id in toDelete) {
        await deleteBook(id);
      }

      for (final entry in entries) {
        final existingFingerprint = indexed[entry.id];
        final changed = existingFingerprint == null ||
            existingFingerprint != entry.fingerprint;
        await _indexBookEntry(
          entry,
          reindexText: changed,
          reindexMarks: reindexMarks,
        );
      }
    } catch (error) {
      Log.d('Search index reconcile failed: $error');
      _setLastError(error);
    }
  }

  Future<void> resetIndexForTesting() async {
    await _recreateIndexFile();
  }

  Future<List<SearchHit>> search(String query, {int limit = 50}) async {
    return searchMarks(query, limit: limit);
  }

  Future<List<SearchHit>> searchMarks(
    String query, {
    int limit = 50,
    SearchHitType? onlyType,
  }) async {
    await init();
    final parsed = SearchIndexQuery.parse(query);
    if (parsed.isEmpty) {
      return const <SearchHit>[];
    }
    final matchExpr = parsed.toFtsMatchExpression();
    if (matchExpr.isEmpty) {
      return const <SearchHit>[];
    }
    try {
      late final ResultSet rows;
      final where =
          onlyType == null
              ? 'fts_marks MATCH ?'
              : "fts_marks MATCH ? AND mark_type = '${_markTypeToDb(onlyType)}'";
      const orderBy =
          'ORDER BY rank ASC, mark_type ASC, book_id ASC, mark_id ASC';
      try {
        rows = _db.select(
          'SELECT '
          '  book_id, mark_id, mark_type, anchor, '
          "  snippet(fts_marks, 4, '[', ']', '…', 10) AS snippet, "
          '  bm25(fts_marks, 0.0, 0.0, 0.0, 0.0, 1.0) AS rank '
          'FROM fts_marks '
          'WHERE $where '
          '$orderBy '
          'LIMIT ?',
          <Object?>[matchExpr, limit],
        );
      } on SqliteException catch (error) {
        final message = error.message.toLowerCase();
        if (!message.contains('no such function: snippet') &&
            !message.contains('no such function: bm25')) {
          rethrow;
        }
        try {
          rows = _db.select(
            'SELECT '
            '  book_id, mark_id, mark_type, anchor, content, '
            '  bm25(fts_marks, 0.0, 0.0, 0.0, 0.0, 1.0) AS rank '
            'FROM fts_marks '
            'WHERE $where '
            '$orderBy '
            'LIMIT ?',
            <Object?>[matchExpr, limit],
          );
        } on SqliteException catch (error) {
          final message = error.message.toLowerCase();
          if (!message.contains('no such function: bm25')) {
            rethrow;
          }
          rows = _db.select(
            'SELECT book_id, mark_id, mark_type, anchor, content '
            'FROM fts_marks '
            'WHERE $where '
            'ORDER BY mark_type ASC, book_id ASC, mark_id ASC '
            'LIMIT ?',
            <Object?>[matchExpr, limit],
          );
        }
      }
      return rows
          .map((row) {
            final typeRaw = (row['mark_type'] as String?) ?? '';
            final type = typeRaw == 'note'
                ? SearchHitType.note
                : SearchHitType.highlight;
            final rawSnippet = (row['snippet'] as String?) ??
                (row['content'] as String?) ??
                '';
            final snippet = rawSnippet.trim().isEmpty
                ? _fallbackSnippet(rawSnippet)
                : rawSnippet;
            return SearchHit(
              type: type,
              bookId: row['book_id'] as String,
              markId: row['mark_id'] as String,
              anchor: row['anchor'] as String?,
              snippet: snippet,
            );
          })
          .toList(growable: false);
    } catch (error) {
      Log.d('Search index query failed: $error');
      _db.execute(
        'UPDATE search_meta '
        'SET last_error = ? '
        'WHERE id = 1',
        <Object?>[error.toString()],
      );
      rethrow;
    }
  }

  Future<List<BookTextHit>> searchBooksText(String query, {int limit = 50}) async {
    await init();
    final parsed = SearchIndexQuery.parse(query);
    if (parsed.isEmpty) {
      return const <BookTextHit>[];
    }
    final matchExpr = parsed.toFtsMatchExpression();
    if (matchExpr.isEmpty) {
      return const <BookTextHit>[];
    }
    try {
      late final ResultSet rows;
      try {
        rows = _db.select(
          'SELECT '
          '  book_id, book_title, book_author, chapter_title, '
          "  snippet(fts_books, 4, '[', ']', '…', 10) AS snippet, "
          '  bm25('
          '    fts_books, '
          '    0.0, 10.0, 3.0, 5.0, 1.0, 0.0, 0.0, 0.0, 0.0'
          '  ) AS rank, '
          '  anchor, chapter_href, chapter_index, paragraph_index '
          'FROM fts_books '
          'WHERE fts_books MATCH ? '
          'ORDER BY rank ASC, book_id ASC, chapter_index ASC, paragraph_index ASC '
          'LIMIT ?',
          <Object?>[matchExpr, limit],
        );
      } on SqliteException catch (error) {
        final message = error.message.toLowerCase();
        if (!message.contains('no such function: snippet') &&
            !message.contains('no such function: bm25')) {
          rethrow;
        }
        try {
          rows = _db.select(
            'SELECT '
            '  book_id, book_title, book_author, chapter_title, '
            '  content, '
            '  bm25('
            '    fts_books, '
            '    0.0, 10.0, 3.0, 5.0, 1.0, 0.0, 0.0, 0.0, 0.0'
            '  ) AS rank, '
            '  anchor, chapter_href, chapter_index, paragraph_index '
            'FROM fts_books '
            'WHERE fts_books MATCH ? '
            'ORDER BY rank ASC, book_id ASC, chapter_index ASC, paragraph_index ASC '
            'LIMIT ?',
            <Object?>[matchExpr, limit],
          );
        } on SqliteException catch (error) {
          final message = error.message.toLowerCase();
          if (!message.contains('no such function: bm25')) {
            rethrow;
          }
          rows = _db.select(
            'SELECT '
            '  book_id, book_title, book_author, chapter_title, '
            "  snippet(fts_books, 4, '[', ']', '…', 10) AS snippet, "
            '  anchor, chapter_href, chapter_index, paragraph_index '
            'FROM fts_books '
            'WHERE fts_books MATCH ? '
            'ORDER BY book_id ASC, chapter_index ASC, paragraph_index ASC '
            'LIMIT ?',
            <Object?>[matchExpr, limit],
          );
        }
      }
      return rows
          .map((row) {
            final rawSnippet = (row['snippet'] as String?) ??
                (row['content'] as String?) ??
                '';
            final snippet = rawSnippet.trim().isEmpty
                ? _fallbackSnippet(rawSnippet)
                : rawSnippet;
            return BookTextHit(
              bookId: row['book_id'] as String,
              bookTitle: (row['book_title'] as String?) ?? '',
              bookAuthor: (row['book_author'] as String?) ?? '',
              chapterTitle: (row['chapter_title'] as String?) ?? '',
              snippet: snippet,
              anchor: row['anchor'] as String,
              chapterHref: row['chapter_href'] as String,
              chapterIndex: row['chapter_index'] as int,
              paragraphIndex: row['paragraph_index'] as int,
            );
          })
          .toList(growable: false);
    } catch (error) {
      Log.d('Search index books query failed: $error');
      _setLastError(error);
      rethrow;
    }
  }

  static String _markTypeToDb(SearchHitType type) {
    switch (type) {
      case SearchHitType.note:
        return 'note';
      case SearchHitType.highlight:
        return 'highlight';
    }
  }

  String _noteContent(Note note) {
    final parts = <String>[
      note.noteText.trim(),
      note.excerpt.trim(),
    ].where((value) => value.isNotEmpty).toList();
    return parts.join('\n');
  }

  static String _fallbackSnippet(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final normalized = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 117)}…';
  }

  Future<void> _ensureSchema() async {
    _db.execute(
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
    _db.execute(
      'INSERT OR IGNORE INTO search_meta(id, schema_version) VALUES (1, ?)',
      <Object?>[schemaVersion],
    );
    _ensureMetaColumn('last_rebuild_ms', 'INTEGER');
    _ensureMetaColumn('marks_rows', 'INTEGER');
    _ensureMetaColumn('books_rows', 'INTEGER');
    final current = _db.select(
      'SELECT schema_version FROM search_meta WHERE id = 1',
    );
    if (current.isEmpty) {
      return;
    }
    final stored = current.first['schema_version'] as int;
    if (stored != schemaVersion) {
      Log.d('Search index schema mismatch: $stored != $schemaVersion');
      _db.execute('DROP TABLE IF EXISTS fts_marks');
      _db.execute('DROP TABLE IF EXISTS fts_books');
      _db.execute('DROP TABLE IF EXISTS search_books_state');
      _db.execute('DELETE FROM search_meta WHERE id = 1');
      _db.execute(
        'INSERT OR IGNORE INTO search_meta(id, schema_version) VALUES (1, ?)',
        <Object?>[schemaVersion],
      );
    }
    _db.execute(
      'CREATE VIRTUAL TABLE IF NOT EXISTS fts_marks USING fts5('
      '  book_id UNINDEXED,'
      '  mark_id UNINDEXED,'
      '  mark_type UNINDEXED,'
      '  anchor UNINDEXED,'
      '  content'
      ')',
    );
    _db.execute(
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

    _db.execute(
      'CREATE TABLE IF NOT EXISTS search_books_state ('
      '  book_id TEXT PRIMARY KEY,'
      '  fingerprint TEXT NOT NULL,'
      '  indexed_at TEXT NULL'
      ')',
    );
  }

  void _ensureMetaColumn(String name, String type) {
    if (_metaHasColumn(name)) {
      return;
    }
    try {
      _db.execute('ALTER TABLE search_meta ADD COLUMN $name $type NULL');
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('duplicate column') || message.contains('already exists')) {
        return;
      }
      rethrow;
    }
  }

  bool _metaHasColumn(String name) {
    try {
      final rows = _db.select('PRAGMA table_info(search_meta)');
      for (final row in rows) {
        if (row['name'] == name) {
          return true;
        }
      }
    } catch (_) {
      // Best-effort: if PRAGMA fails, fall back to attempting ALTER TABLE.
    }
    return false;
  }

  Future<void> _openOrRecreate(String path) async {
    try {
      _database = sqlite3.open(path);
      _configureDatabase(_db);
      await _ensureSchema();
      return;
    } catch (error) {
      Log.d('Search index open failed, recreating: $error');
    }
    await _recreateIndexFile();
  }

  Future<void> _recreateIndexFile() async {
    final existing = _database;
    if (existing != null) {
      existing.dispose();
      _database = null;
    }

    final path = _dbPath;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (error) {
        Log.d('Search index file delete failed: $error');
      }
    }

    final nextPath = _dbPath;
    if (nextPath == null) {
      _database = sqlite3.openInMemory();
      _configureDatabase(_db);
      await _ensureSchema();
      return;
    }
    _database = sqlite3.open(nextPath);
    _configureDatabase(_db);
    await _ensureSchema();
  }

  void _configureDatabase(Database db) {
    try {
      db.execute('PRAGMA busy_timeout = 3000');
    } catch (_) {}
    try {
      db.execute('PRAGMA journal_mode = WAL');
    } catch (_) {}
    try {
      db.execute('PRAGMA synchronous = NORMAL');
    } catch (_) {}
    try {
      db.execute('PRAGMA temp_store = MEMORY');
    } catch (_) {}
  }

  Future<void> _indexBookEntry(
    LibraryEntry entry, {
    required bool reindexText,
    required bool reindexMarks,
  }) async {
    if (!reindexText && !reindexMarks) {
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute('BEGIN');
    try {
      if (reindexText) {
        _db.execute(
          'DELETE FROM fts_books WHERE book_id = ?',
          <Object?>[entry.id],
        );
        final chapters = await _bookTextExtractor.extract(entry);
        final stmt = _db.prepare(
          'INSERT INTO fts_books('
          '  book_id, book_title, book_author, chapter_title, '
          '  content, anchor, chapter_href, chapter_index, paragraph_index'
          ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        );
        try {
          for (var chapterIndex = 0;
              chapterIndex < chapters.length;
              chapterIndex += 1) {
            final chapter = chapters[chapterIndex];
            final chapterTitle = chapter.title;
            final paragraphs = chapter.paragraphs;
            var offset = chapterTitle.length;
            for (var paragraphIndex = 0;
                paragraphIndex < paragraphs.length;
                paragraphIndex += 1) {
              final paragraph = paragraphs[paragraphIndex];
              if (paragraph.trim().isEmpty) {
                offset += paragraph.length;
                continue;
              }
              final anchor = Anchor(
                chapterHref: chapter.href,
                offset: offset,
              ).toString();
              stmt.execute(<Object?>[
                entry.id,
                entry.title,
                entry.author ?? '',
                chapterTitle,
                paragraph,
                anchor,
                chapter.href,
                chapterIndex,
                paragraphIndex,
              ]);
              offset += paragraph.length;
            }
          }
        } finally {
          stmt.dispose();
        }
        _db.execute(
          'INSERT OR REPLACE INTO search_books_state(book_id, fingerprint, indexed_at) '
          'VALUES (?, ?, ?)',
          <Object?>[entry.id, entry.fingerprint, now],
        );
      }

      if (reindexMarks) {
        _db.execute(
          'DELETE FROM fts_marks WHERE book_id = ?',
          <Object?>[entry.id],
        );
        final stmt = _db.prepare(
          'INSERT INTO fts_marks(book_id, mark_id, mark_type, anchor, content) '
          'VALUES (?, ?, ?, ?, ?)',
        );
        try {
          for (final note in entry.notes) {
            final content = _noteContent(note);
            if (content.trim().isEmpty) {
              continue;
            }
            stmt.execute(<Object?>[
              entry.id,
              note.id,
              'note',
              note.anchor,
              content,
            ]);
          }
          for (final highlight in entry.highlights) {
            final content = highlight.excerpt;
            if (content.trim().isEmpty) {
              continue;
            }
            stmt.execute(<Object?>[
              entry.id,
              highlight.id,
              'highlight',
              highlight.anchor,
              content,
            ]);
          }
        } finally {
          stmt.dispose();
        }
      }

      _refreshRowCounts();
      _db.execute('UPDATE search_meta SET last_error = NULL WHERE id = 1');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _refreshRowCounts() {
    final marks = _db.select('SELECT COUNT(*) AS c FROM fts_marks').first['c'] as int;
    final books = _db.select('SELECT COUNT(*) AS c FROM fts_books').first['c'] as int;
    _db.execute(
      'UPDATE search_meta SET marks_rows = ?, books_rows = ? WHERE id = 1',
      <Object?>[marks, books],
    );
  }

  void _setLastError(Object error) {
    try {
      _db.execute(
        'UPDATE search_meta SET last_error = ? WHERE id = 1',
        <Object?>[error.toString()],
      );
    } catch (_) {}
  }
}
