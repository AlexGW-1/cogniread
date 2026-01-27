import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cogniread/src/core/services/hive_bootstrap.dart';
import 'package:cogniread/src/core/types/anchor.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/ai/ai_models.dart';
import 'package:cogniread/src/features/ai/data/ai_service.dart';
import 'package:cogniread/src/features/library/data/free_notes_store.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/search/indexing/search_index_books_text_extractor.dart';
import 'package:cogniread/src/features/search/search_index_service.dart';
import 'package:cogniread/src/features/search/search_models.dart';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SemanticSearchStatus {
  const SemanticSearchStatus({
    required this.schemaVersion,
    this.lastRebuildAt,
    this.lastRebuildMs,
    this.itemsCount,
    this.lastError,
    this.model,
    this.baseUrl,
  });

  final int schemaVersion;
  final DateTime? lastRebuildAt;
  final int? lastRebuildMs;
  final int? itemsCount;
  final String? lastError;
  final String? model;
  final String? baseUrl;
}

class SemanticSearchRebuildProgress {
  const SemanticSearchRebuildProgress({
    required this.processedItems,
    required this.totalItems,
    required this.stage,
    required this.elapsedMs,
    this.currentTitle,
    this.message,
  });

  final int processedItems;
  final int totalItems;
  final String stage;
  final int elapsedMs;
  final String? currentTitle;
  final String? message;

  double? get fraction {
    if (totalItems <= 0) {
      return null;
    }
    if (processedItems <= 0) {
      return 0;
    }
    return processedItems / totalItems;
  }
}

class SemanticSearchRebuildHandle {
  const SemanticSearchRebuildHandle({
    required this.progress,
    required this.done,
    required this.cancel,
  });

  final Stream<SemanticSearchRebuildProgress> progress;
  final Future<void> done;
  final Future<void> Function() cancel;
}

enum SemanticSourceType { book, note, highlight, freeNote }

class SemanticSearchService {
  SemanticSearchService({
    LibraryStore? store,
    FreeNotesStore? freeNotesStore,
  }) : _store = store ?? LibraryStore(),
       _freeNotesStore = freeNotesStore ?? FreeNotesStore();

  static const int schemaVersion = 1;
  static const int _maxChunkChars = 1200;
  static const int _maxEmbeddingChars = 2000;

  final LibraryStore _store;
  final FreeNotesStore _freeNotesStore;
  final _SemanticEmbeddingStore _embeddingStore = _SemanticEmbeddingStore();

  Future<void> init() async {
    await _embeddingStore.init();
  }

  Future<SemanticSearchStatus> status() async {
    await init();
    return _embeddingStore.status();
  }

  bool isCompatibleWith(AiConfig config, SemanticSearchStatus status) {
    final model = _resolveEmbeddingModel(config);
    final baseUrl = config.baseUrl?.trim();
    if (model != null &&
        status.model != null &&
        status.model!.trim().isNotEmpty &&
        status.model != model) {
      return false;
    }
    if (baseUrl != null &&
        status.baseUrl != null &&
        status.baseUrl!.trim().isNotEmpty &&
        status.baseUrl != baseUrl) {
      return false;
    }
    return true;
  }

  Future<SemanticSearchRebuildHandle> rebuildIndex(AiConfig config) async {
    await init();
    final progress =
        StreamController<SemanticSearchRebuildProgress>.broadcast();
    final done = Completer<void>();
    var canceled = false;
    final watch = Stopwatch()..start();

    void report({
      required int processedItems,
      required int totalItems,
      required String stage,
      String? currentTitle,
      String? message,
    }) {
      progress.add(
        SemanticSearchRebuildProgress(
          processedItems: processedItems,
          totalItems: totalItems,
          stage: stage,
          elapsedMs: watch.elapsedMilliseconds,
          currentTitle: currentTitle,
          message: message,
        ),
      );
    }

    Future<void> run() async {
      final model = _resolveEmbeddingModel(config);
      if (!_isConfigReady(config, model: model)) {
        throw const AiServiceException(
          'AI не настроен. Укажите endpoint и модель эмбеддингов.',
        );
      }
      final service = _buildAiService(config);
      if (service == null) {
        throw const AiServiceException('AI сервис недоступен.');
      }
      final cache = <String, List<double>>{};
      var processed = 0;
      try {
        await _embeddingStore.clear();
        await _store.init();
        final entries = await _store.loadAll();
        final totalBooks = entries.length;
        report(
          processedItems: processed,
          totalItems: 0,
          stage: 'books',
          message: 'Книги: $totalBooks',
        );

        for (var bookIndex = 0; bookIndex < entries.length; bookIndex += 1) {
          if (canceled) {
            throw const _SemanticCanceled();
          }
          final entry = entries[bookIndex];
          List<SearchIndexExtractedChapter> chapters;
          try {
            chapters = SearchIndexBookTextExtractor.extractFromFile(
              entry.localPath,
              tocMode: entry.tocMode.name,
              hasStoredToc:
                  entry.tocOfficial.isNotEmpty || entry.tocGenerated.isNotEmpty,
            );
          } catch (error) {
            report(
              processedItems: processed,
              totalItems: 0,
              stage: 'book-error',
              currentTitle: entry.title,
              message: 'Пропустили книгу: ${error.toString()}',
            );
            Log.d('Semantic search skipped book ${entry.id}: $error');
            continue;
          }
          report(
            processedItems: processed,
            totalItems: 0,
            stage: 'books',
            currentTitle: entry.title,
            message: 'Книга ${bookIndex + 1}/$totalBooks',
          );
          for (var chapterIndex = 0;
              chapterIndex < chapters.length;
              chapterIndex += 1) {
            if (canceled) {
              throw const _SemanticCanceled();
            }
            final chapter = chapters[chapterIndex];
            final chunks = _chunkChapter(
              chapter,
              chapterIndex: chapterIndex,
              maxChars: _maxChunkChars,
            );
            for (final chunk in chunks) {
              if (canceled) {
                throw const _SemanticCanceled();
              }
              if (chunk.text.trim().isEmpty) {
                continue;
              }
              final text = _prepareEmbeddingText(
                bookTitle: entry.title,
                chapterTitle: chapter.title,
                content: chunk.text,
              );
              final vector = await _embedCached(
                service,
                text,
                model: model,
                cache: cache,
              );
              final record = _SemanticEmbeddingRecord(
                id:
                    'book:${entry.id}:${chunk.chapterIndex}:${chunk.paragraphIndex}:${chunk.chunkIndex}',
                sourceType: SemanticSourceType.book,
                bookId: entry.id,
                markId: null,
                anchor: chunk.anchor,
                content: chunk.text,
                chapterTitle: chapter.title,
                chapterHref: chunk.chapterHref,
                chapterIndex: chunk.chapterIndex,
                paragraphIndex: chunk.paragraphIndex,
                embedding: vector,
                updatedAt: DateTime.now(),
              );
              await _embeddingStore.upsert(record);
              processed += 1;
              if (processed % 10 == 0) {
                report(
                  processedItems: processed,
                  totalItems: 0,
                  stage: 'books',
                  currentTitle: entry.title,
                );
              }
            }
          }
        }

        report(
          processedItems: processed,
          totalItems: 0,
          stage: 'marks',
          message: 'Заметки и цитаты',
        );

        for (final entry in entries) {
          if (canceled) {
            throw const _SemanticCanceled();
          }
          for (final note in entry.notes) {
            if (canceled) {
              throw const _SemanticCanceled();
            }
            final noteText = _noteEmbeddingText(note);
            if (noteText.trim().isEmpty) {
              continue;
            }
            final text = _prepareEmbeddingText(
              bookTitle: entry.title,
              content: noteText,
            );
            final vector = await _embedCached(
              service,
              text,
              model: model,
              cache: cache,
            );
            final record = _SemanticEmbeddingRecord(
              id: 'note:${entry.id}:${note.id}',
              sourceType: SemanticSourceType.note,
              bookId: entry.id,
              markId: note.id,
              anchor: note.anchor ?? '',
              content: _noteSnippet(note),
              chapterTitle: null,
              chapterHref: null,
              chapterIndex: null,
              paragraphIndex: null,
              embedding: vector,
              updatedAt: DateTime.now(),
            );
            await _embeddingStore.upsert(record);
            processed += 1;
          }
          for (final highlight in entry.highlights) {
            if (canceled) {
              throw const _SemanticCanceled();
            }
            if (highlight.excerpt.trim().isEmpty) {
              continue;
            }
            final text = _prepareEmbeddingText(
              bookTitle: entry.title,
              content: highlight.excerpt,
            );
            final vector = await _embedCached(
              service,
              text,
              model: model,
              cache: cache,
            );
            final record = _SemanticEmbeddingRecord(
              id: 'highlight:${entry.id}:${highlight.id}',
              sourceType: SemanticSourceType.highlight,
              bookId: entry.id,
              markId: highlight.id,
              anchor: highlight.anchor ?? '',
              content: highlight.excerpt,
              chapterTitle: null,
              chapterHref: null,
              chapterIndex: null,
              paragraphIndex: null,
              embedding: vector,
              updatedAt: DateTime.now(),
            );
            await _embeddingStore.upsert(record);
            processed += 1;
          }
        }

        final freeNotes = await _loadFreeNotes();
        for (final note in freeNotes) {
          if (canceled) {
            throw const _SemanticCanceled();
          }
          if (note.text.trim().isEmpty) {
            continue;
          }
          final text = _prepareEmbeddingText(content: note.text);
          final vector = await _embedCached(
            service,
            text,
            model: model,
            cache: cache,
          );
          final record = _SemanticEmbeddingRecord(
            id: 'free-note:${note.id}',
            sourceType: SemanticSourceType.freeNote,
            bookId: SearchIndexService.freeNotesBookId,
            markId: note.id,
            anchor: '',
            content: note.text,
            chapterTitle: null,
            chapterHref: null,
            chapterIndex: null,
            paragraphIndex: null,
            embedding: vector,
            updatedAt: DateTime.now(),
          );
          await _embeddingStore.upsert(record);
          processed += 1;
        }

        await _embeddingStore.saveStatus(
          SemanticSearchStatus(
            schemaVersion: schemaVersion,
            lastRebuildAt: DateTime.now().toUtc(),
            lastRebuildMs: watch.elapsedMilliseconds,
            itemsCount: processed,
            lastError: null,
            model: model,
            baseUrl: config.baseUrl?.trim(),
          ),
        );
        if (!done.isCompleted) {
          done.complete();
        }
      } catch (error) {
        if (error is _SemanticCanceled) {
          if (!done.isCompleted) {
            done.complete();
          }
          return;
        }
        Log.d('Semantic search rebuild failed: $error');
        final errorMessage = _semanticErrorMessage(error);
        await _embeddingStore.saveStatus(
          SemanticSearchStatus(
            schemaVersion: schemaVersion,
            lastRebuildAt: DateTime.now().toUtc(),
            lastRebuildMs: watch.elapsedMilliseconds,
            itemsCount: processed,
            lastError: errorMessage,
            model: model,
            baseUrl: config.baseUrl?.trim(),
          ),
        );
        if (!done.isCompleted) {
          done.complete();
        }
      } finally {
        await progress.close();
      }
    }

    unawaited(run());

    Future<void> cancel() async {
      canceled = true;
    }

    return SemanticSearchRebuildHandle(
      progress: progress.stream,
      done: done.future,
      cancel: cancel,
    );
  }

  Future<List<BookTextHit>> searchBooks(
    String query, {
    int limit = 50,
    required AiConfig config,
  }) async {
    final result = await _semanticSearch(
      query,
      sourceType: SemanticSourceType.book,
      limit: limit,
      config: config,
    );
    await _store.init();
    final entries = await _store.loadAll();
    final meta = <String, ({String title, String author})>{
      for (final entry in entries)
        entry.id: (title: entry.title, author: entry.author ?? ''),
    };
    return result
        .map(
          (item) => BookTextHit(
            bookId: item.bookId,
            bookTitle: meta[item.bookId]?.title ?? '',
            bookAuthor: meta[item.bookId]?.author ?? '',
            chapterTitle: item.chapterTitle ?? '',
            snippet: _snippet(item.content),
            anchor: item.anchor,
            chapterHref: item.chapterHref ?? '',
            chapterIndex: item.chapterIndex ?? 0,
            paragraphIndex: item.paragraphIndex ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<SearchHit>> searchMarks(
    String query, {
    int limit = 50,
    SearchHitType? onlyType,
    required AiConfig config,
  }) async {
    final types = <SemanticSourceType>{
      SemanticSourceType.note,
      SemanticSourceType.highlight,
      SemanticSourceType.freeNote,
    };
    if (onlyType == SearchHitType.note) {
      types
        ..clear()
        ..add(SemanticSourceType.note)
        ..add(SemanticSourceType.freeNote);
    }
    if (onlyType == SearchHitType.highlight) {
      types
        ..clear()
        ..add(SemanticSourceType.highlight);
    }
    final results = <SearchHit>[];
    final queryVector = await _prepareQueryVector(query, config: config);
    if (queryVector.isEmpty) {
      return const <SearchHit>[];
    }
    final collected = <_SemanticEmbeddingRecord>[];
    for (final type in types) {
      final records = await _embeddingStore.loadByType(type);
      collected.addAll(_scoreRecords(queryVector, records));
    }
    collected.sort((a, b) => b.score.compareTo(a.score));
    final limited = collected.take(limit).toList(growable: false);
    for (final item in limited) {
      final type = item.sourceType == SemanticSourceType.highlight
          ? SearchHitType.highlight
          : SearchHitType.note;
      results.add(
        SearchHit(
          type: type,
          bookId: item.bookId,
          markId: item.markId ?? '',
          anchor: item.anchor,
          snippet: _snippet(item.content),
          isFreeNote: item.sourceType == SemanticSourceType.freeNote,
        ),
      );
    }
    return results;
  }

  Future<List<_SemanticEmbeddingRecord>> _semanticSearch(
    String query, {
    required SemanticSourceType sourceType,
    required int limit,
    required AiConfig config,
  }) async {
    final queryVector = await _prepareQueryVector(query, config: config);
    final records = await _embeddingStore.loadByType(sourceType);
    final scored = _scoreRecords(queryVector, records);
    scored.sort((a, b) => b.score.compareTo(a.score));
    if (scored.length <= limit) {
      return scored;
    }
    return scored.sublist(0, limit);
  }

  Future<List<double>> _prepareQueryVector(
    String query, {
    required AiConfig config,
  }) async {
    await init();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <double>[];
    }
    final model = _resolveEmbeddingModel(config);
    if (!_isConfigReady(config, model: model)) {
      throw const AiServiceException(
        'AI не настроен. Укажите endpoint и модель эмбеддингов.',
      );
    }
    final status = await _embeddingStore.status();
    if ((status.itemsCount ?? 0) <= 0) {
      throw StateError('Семантический индекс пуст.');
    }
    if (!isCompatibleWith(config, status)) {
      throw StateError('Семантический индекс устарел. Перестройте индекс.');
    }
    final service = _buildAiService(config);
    if (service == null) {
      throw const AiServiceException('AI сервис недоступен.');
    }
    try {
      return await _embedCached(
        service,
        trimmed,
        model: model,
        cache: <String, List<double>>{},
      );
    } catch (error) {
      throw StateError(_semanticErrorMessage(error));
    }
  }

  List<_SemanticEmbeddingRecord> _scoreRecords(
    List<double> queryVector,
    List<_SemanticEmbeddingRecord> records,
  ) {
    final scored = <_SemanticEmbeddingRecord>[];
    if (queryVector.isEmpty) {
      return scored;
    }
    for (final record in records) {
      final score = _dot(queryVector, record.embedding);
      scored.add(record.copyWith(score: score));
    }
    return scored;
  }

  AiHttpService? _buildAiService(AiConfig config) {
    if (!config.isConfigured) {
      return null;
    }
    final base = Uri.tryParse(config.baseUrl!.trim());
    if (base == null) {
      return null;
    }
    return AiHttpService(baseUri: base, apiKey: config.apiKey);
  }

  String? _resolveEmbeddingModel(AiConfig config) {
    final explicit = config.embeddingModel?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final fallback = config.model?.trim();
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return null;
  }

  bool _isConfigReady(AiConfig config, {required String? model}) {
    if (!config.isConfigured) {
      return false;
    }
    if (model == null || model.trim().isEmpty) {
      return false;
    }
    return true;
  }

  Future<List<double>> _embedCached(
    AiHttpService service,
    String input, {
    required String? model,
    required Map<String, List<double>> cache,
  }) async {
    final trimmed = _trimForEmbedding(input);
    final key = sha1.convert(utf8.encode(trimmed)).toString();
    final cached = cache[key];
    if (cached != null) {
      return cached;
    }
    final result = await service.embed(input: trimmed, model: model);
    final normalized = _normalize(result.embedding);
    cache[key] = normalized;
    return normalized;
  }

  String _trimForEmbedding(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= _maxEmbeddingChars) {
      return trimmed;
    }
    return trimmed.substring(0, _maxEmbeddingChars);
  }

  List<_SemanticChunk> _chunkChapter(
    SearchIndexExtractedChapter chapter, {
    required int chapterIndex,
    required int maxChars,
  }) {
    final chunks = <_SemanticChunk>[];
    var buffer = StringBuffer();
    var bufferLength = 0;
    var chunkIndex = 0;
    var paragraphStartIndex = 0;
    var paragraphOffset = chapter.title.length;
    var paragraphOffsetSnapshot = paragraphOffset;
    for (var i = 0; i < chapter.paragraphs.length; i += 1) {
      final paragraph = chapter.paragraphs[i];
      if (bufferLength == 0) {
        paragraphStartIndex = i;
        paragraphOffsetSnapshot = paragraphOffset;
      }
      if (paragraph.trim().isNotEmpty) {
        buffer.writeln(paragraph.trim());
        bufferLength += paragraph.length;
      }
      paragraphOffset += paragraph.length;
      if (bufferLength >= maxChars) {
        final text = buffer.toString().trim();
        if (text.isNotEmpty) {
          final anchor = Anchor(
            chapterHref: chapter.href,
            offset: paragraphOffsetSnapshot,
          ).toString();
          chunks.add(
            _SemanticChunk(
              text: text,
              anchor: anchor,
              chapterHref: chapter.href,
              chapterIndex: chapterIndex,
              paragraphIndex: paragraphStartIndex,
              chunkIndex: chunkIndex,
            ),
          );
          chunkIndex += 1;
        }
        buffer = StringBuffer();
        bufferLength = 0;
      }
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) {
      final anchor = Anchor(
        chapterHref: chapter.href,
        offset: paragraphOffsetSnapshot,
      ).toString();
      chunks.add(
        _SemanticChunk(
          text: tail,
          anchor: anchor,
          chapterHref: chapter.href,
          chapterIndex: chapterIndex,
          paragraphIndex: paragraphStartIndex,
          chunkIndex: chunkIndex,
        ),
      );
    }
    return chunks;
  }

  Future<List<FreeNote>> _loadFreeNotes() async {
    try {
      await _freeNotesStore.init();
      return await _freeNotesStore.loadAll();
    } catch (error) {
      Log.d('Semantic search free notes load failed: $error');
      return const <FreeNote>[];
    }
  }

  String _prepareEmbeddingText({
    String? bookTitle,
    String? chapterTitle,
    required String content,
  }) {
    final header = <String>[
      if (bookTitle != null && bookTitle.trim().isNotEmpty) bookTitle.trim(),
      if (chapterTitle != null && chapterTitle.trim().isNotEmpty)
        chapterTitle.trim(),
    ];
    if (header.isEmpty) {
      return content;
    }
    return '${header.join(' — ')}\n$content';
  }
}

class _SemanticEmbeddingRecord {
  const _SemanticEmbeddingRecord({
    required this.id,
    required this.sourceType,
    required this.bookId,
    required this.markId,
    required this.anchor,
    required this.content,
    required this.chapterTitle,
    required this.chapterHref,
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.embedding,
    required this.updatedAt,
    this.score = 0,
  });

  final String id;
  final SemanticSourceType sourceType;
  final String bookId;
  final String? markId;
  final String anchor;
  final String content;
  final String? chapterTitle;
  final String? chapterHref;
  final int? chapterIndex;
  final int? paragraphIndex;
  final List<double> embedding;
  final DateTime updatedAt;
  final double score;

  _SemanticEmbeddingRecord copyWith({double? score}) {
    return _SemanticEmbeddingRecord(
      id: id,
      sourceType: sourceType,
      bookId: bookId,
      markId: markId,
      anchor: anchor,
      content: content,
      chapterTitle: chapterTitle,
      chapterHref: chapterHref,
      chapterIndex: chapterIndex,
      paragraphIndex: paragraphIndex,
      embedding: embedding,
      updatedAt: updatedAt,
      score: score ?? this.score,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'type': sourceType.name,
      'bookId': bookId,
      'markId': markId,
      'anchor': anchor,
      'content': content,
      'chapterTitle': chapterTitle,
      'chapterHref': chapterHref,
      'chapterIndex': chapterIndex,
      'paragraphIndex': paragraphIndex,
      'embedding': embedding,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static _SemanticEmbeddingRecord fromMap(Map<String, Object?> map) {
    final embedding = (map['embedding'] is List)
        ? _coerceEmbeddingList(map['embedding'] as List)
        : const <double>[];
    return _SemanticEmbeddingRecord(
      id: map['id'] as String? ?? '',
      sourceType: _parseSourceType(map['type']) ?? SemanticSourceType.book,
      bookId: map['bookId'] as String? ?? '',
      markId: map['markId'] as String?,
      anchor: map['anchor'] as String? ?? '',
      content: map['content'] as String? ?? '',
      chapterTitle: map['chapterTitle'] as String?,
      chapterHref: map['chapterHref'] as String?,
      chapterIndex: (map['chapterIndex'] as num?)?.toInt(),
      paragraphIndex: (map['paragraphIndex'] as num?)?.toInt(),
      embedding: embedding,
      updatedAt: _parseDate(map['updatedAt']),
    );
  }
}

class _SemanticChunk {
  const _SemanticChunk({
    required this.text,
    required this.anchor,
    required this.chapterHref,
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.chunkIndex,
  });

  final String text;
  final String anchor;
  final String chapterHref;
  final int chapterIndex;
  final int paragraphIndex;
  final int chunkIndex;
}

class _SemanticEmbeddingStore {
  static const String _boxName = 'semantic_embeddings';
  static const String _metaBoxName = 'semantic_index_meta';
  static const String _metaKey = 'meta';

  Box<dynamic>? _box;
  Box<dynamic>? _metaBox;

  Future<void> init() async {
    _box = await HiveBootstrap.openBoxSafe<dynamic>(_boxName);
    _metaBox = await HiveBootstrap.openBoxSafe<dynamic>(_metaBoxName);
  }

  Box<dynamic> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('SemanticEmbeddingStore not initialized');
    }
    return box;
  }

  Box<dynamic> get _requireMetaBox {
    final box = _metaBox;
    if (box == null) {
      throw StateError('SemanticEmbeddingStore meta not initialized');
    }
    return box;
  }

  Future<void> clear() async {
    await _requireBox.clear();
  }

  Future<void> upsert(_SemanticEmbeddingRecord record) async {
    await _requireBox.put(record.id, record.toMap());
  }

  Future<List<_SemanticEmbeddingRecord>> loadAll() async {
    return _requireBox.values
        .whereType<Map<Object?, Object?>>()
        .map((value) => _SemanticEmbeddingRecord.fromMap(_coerceMap(value)))
        .toList();
  }

  Future<List<_SemanticEmbeddingRecord>> loadByType(
    SemanticSourceType type,
  ) async {
    final items = await loadAll();
    return items.where((item) => item.sourceType == type).toList();
  }

  Future<SemanticSearchStatus> status() async {
    final meta = _requireMetaBox.get(_metaKey);
    if (meta is Map) {
      final map = meta.map((key, value) => MapEntry(key.toString(), value));
      return _statusFromMap(map);
    }
    final count = _requireBox.length;
    return SemanticSearchStatus(
      schemaVersion: SemanticSearchService.schemaVersion,
      itemsCount: count == 0 ? null : count,
    );
  }

  Future<void> saveStatus(SemanticSearchStatus status) async {
    await _requireMetaBox.put(_metaKey, _statusToMap(status));
  }

  SemanticSearchStatus _statusFromMap(Map<String, Object?> map) {
    return SemanticSearchStatus(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ??
          SemanticSearchService.schemaVersion,
      lastRebuildAt: _parseDate(map['lastRebuildAt']),
      lastRebuildMs: (map['lastRebuildMs'] as num?)?.toInt(),
      itemsCount: (map['itemsCount'] as num?)?.toInt(),
      lastError: map['lastError'] as String?,
      model: map['model'] as String?,
      baseUrl: map['baseUrl'] as String?,
    );
  }

  Map<String, Object?> _statusToMap(SemanticSearchStatus status) {
    return <String, Object?>{
      'schemaVersion': status.schemaVersion,
      'lastRebuildAt': status.lastRebuildAt?.toIso8601String(),
      'lastRebuildMs': status.lastRebuildMs,
      'itemsCount': status.itemsCount,
      'lastError': status.lastError,
      'model': status.model,
      'baseUrl': status.baseUrl,
    };
  }
}

class _SemanticCanceled implements Exception {
  const _SemanticCanceled();
}

double _dot(List<double> left, List<double> right) {
  final len = min(left.length, right.length);
  var sum = 0.0;
  for (var i = 0; i < len; i += 1) {
    sum += left[i] * right[i];
  }
  return sum;
}

List<double> _normalize(List<double> vector) {
  var sum = 0.0;
  for (final value in vector) {
    sum += value * value;
  }
  final norm = sqrt(sum);
  if (norm <= 0) {
    return vector;
  }
  return vector.map((value) => value / norm).toList(growable: false);
}

List<double> _coerceEmbeddingList(List<dynamic> values) {
  return values
      .map((value) => value is num ? value.toDouble() : double.nan)
      .where((value) => value.isFinite)
      .toList(growable: false);
}

SemanticSourceType? _parseSourceType(Object? value) {
  if (value is String) {
    return SemanticSourceType.values.cast<SemanticSourceType?>().firstWhere(
      (item) => item?.name == value,
      orElse: () => null,
    );
  }
  return null;
}

String _noteEmbeddingText(Note note) {
  final buffer = StringBuffer();
  if (note.noteText.trim().isNotEmpty) {
    buffer.writeln(note.noteText.trim());
  }
  if (note.excerpt.trim().isNotEmpty) {
    if (buffer.length > 0) {
      buffer.writeln();
    }
    buffer.writeln(note.excerpt.trim());
  }
  return buffer.toString().trim();
}

String _noteSnippet(Note note) {
  if (note.noteText.trim().isNotEmpty) {
    return note.noteText.trim();
  }
  return note.excerpt.trim();
}

String _snippet(String text) {
  final trimmed = text.trim();
  if (trimmed.length <= 240) {
    return trimmed;
  }
  return '${trimmed.substring(0, 240)}…';
}

DateTime _parseDate(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

Map<String, Object?> _coerceMap(Map<Object?, Object?> source) {
  return source.map((key, value) => MapEntry(key?.toString() ?? '', value));
}

String _semanticErrorMessage(Object error) {
  if (error is AiServiceException) {
    final raw = error.toString();
    if (raw.contains('does not support embeddings') ||
        raw.contains('support embeddings')) {
      return 'Модель не поддерживает эмбеддинги. Укажите подходящую модель.';
    }
    return raw;
  }
  return error.toString();
}
