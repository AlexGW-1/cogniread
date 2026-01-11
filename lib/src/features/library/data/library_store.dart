import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/sync/data/event_log_store.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.localPath,
    required this.coverPath,
    required this.addedAt,
    required this.fingerprint,
    required this.sourcePath,
    required this.readingPosition,
    required this.progress,
    required this.lastOpenedAt,
    required this.notes,
    required this.highlights,
    required this.bookmarks,
    this.tocOfficial = const <TocNode>[],
    this.tocGenerated = const <TocNode>[],
    this.tocMode = TocMode.official,
  });

  final String id;
  final String title;
  final String? author;
  final String localPath;
  final String? coverPath;
  final DateTime addedAt;
  final String fingerprint;
  final String sourcePath;
  final ReadingPosition readingPosition;
  final ReadingProgress progress;
  final DateTime? lastOpenedAt;
  final List<Note> notes;
  final List<Highlight> highlights;
  final List<Bookmark> bookmarks;
  final List<TocNode> tocOfficial;
  final List<TocNode> tocGenerated;
  final TocMode tocMode;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'title': title,
        'author': author,
        'localPath': localPath,
        'coverPath': coverPath,
        'addedAt': addedAt.toIso8601String(),
        'fingerprint': fingerprint,
        'sourcePath': sourcePath,
        'readingPosition': readingPosition.toMap(),
        'progress': progress.toMap(),
        'lastOpenedAt': lastOpenedAt?.toIso8601String(),
        'notes': notes.map((note) => note.toMap()).toList(),
        'highlights': highlights.map((highlight) => highlight.toMap()).toList(),
        'bookmarks': bookmarks.map((bookmark) => bookmark.toMap()).toList(),
        'tocOfficial': tocOfficial.map((node) => node.toMap()).toList(),
        'tocGenerated': tocGenerated.map((node) => node.toMap()).toList(),
        'tocMode': tocMode.name,
      };

  static LibraryEntry fromMap(Map<String, Object?> map) {
    return LibraryEntry(
      id: map['id'] as String,
      title: map['title'] as String,
      author: map['author'] as String?,
      localPath: map['localPath'] as String,
      coverPath: map['coverPath'] as String?,
      addedAt: DateTime.parse(map['addedAt'] as String),
      fingerprint: map['fingerprint'] as String,
      sourcePath: map['sourcePath'] as String,
      readingPosition: ReadingPosition.fromMap(
        Map<String, Object?>.from(
          (map['readingPosition'] as Map?) ?? const <String, Object?>{},
        ),
      ),
      progress: ReadingProgress.fromMap(
        Map<String, Object?>.from(
          (map['progress'] as Map?) ?? const <String, Object?>{},
        ),
      ),
      lastOpenedAt: map['lastOpenedAt'] == null
          ? null
          : DateTime.parse(map['lastOpenedAt'] as String),
      notes: _readList(map['notes'])
          .map((item) => Note.fromMap(item))
          .toList(),
      highlights: _readList(map['highlights'])
          .map((item) => Highlight.fromMap(item))
          .toList(),
      bookmarks: _readList(map['bookmarks'])
          .map((item) => Bookmark.fromMap(item))
          .toList(),
      tocOfficial: _readTocList(map['tocOfficial']),
      tocGenerated: _readTocList(map['tocGenerated']),
      tocMode: _parseTocMode(map['tocMode']),
    );
  }
}

class ReadingPosition {
  const ReadingPosition({
    required this.chapterHref,
    required this.anchor,
    required this.offset,
    required this.updatedAt,
  });

  final String? chapterHref;
  final String? anchor;
  final int? offset;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'chapterHref': chapterHref,
        'anchor': anchor,
        'offset': offset,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static ReadingPosition fromMap(Map<String, Object?> map) {
    return ReadingPosition(
      chapterHref: map['chapterHref'] as String?,
      anchor: map['anchor'] as String?,
      offset: map['offset'] as int?,
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt'] as String),
    );
  }
}

class ReadingProgress {
  const ReadingProgress({
    required this.percent,
    required this.chapterIndex,
    required this.totalChapters,
    required this.updatedAt,
  });

  final double? percent;
  final int? chapterIndex;
  final int? totalChapters;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'percent': percent,
        'chapterIndex': chapterIndex,
        'totalChapters': totalChapters,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static ReadingProgress fromMap(Map<String, Object?> map) {
    return ReadingProgress(
      percent: (map['percent'] as num?)?.toDouble(),
      chapterIndex: map['chapterIndex'] as int?,
      totalChapters: map['totalChapters'] as int?,
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt'] as String),
    );
  }
}

class Note {
  const Note({
    required this.id,
    required this.bookId,
    required this.anchor,
    required this.endOffset,
    required this.excerpt,
    required this.noteText,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  final String? anchor;
  final int? endOffset;
  final String excerpt;
  final String noteText;
  final String color;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'bookId': bookId,
        'anchor': anchor,
        'endOffset': endOffset,
        'excerpt': excerpt,
        'noteText': noteText,
        'color': color,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Note fromMap(Map<String, Object?> map) {
    final createdAt = _parseDate(map['createdAt']);
    final updatedAt = _parseDate(map['updatedAt'], fallback: createdAt);
    return Note(
      id: map['id'] as String,
      bookId: map['bookId'] as String,
      anchor: map['anchor'] as String?,
      endOffset: (map['endOffset'] as num?)?.toInt(),
      excerpt: map['excerpt'] as String? ?? '',
      noteText: map['noteText'] as String? ?? '',
      color: map['color'] as String? ?? 'yellow',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class Highlight {
  const Highlight({
    required this.id,
    required this.bookId,
    required this.anchor,
    required this.endOffset,
    required this.excerpt,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  final String? anchor;
  final int? endOffset;
  final String excerpt;
  final String color;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'bookId': bookId,
        'anchor': anchor,
        'endOffset': endOffset,
        'excerpt': excerpt,
        'color': color,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Highlight fromMap(Map<String, Object?> map) {
    final createdAt = _parseDate(map['createdAt']);
    final updatedAt = _parseDate(map['updatedAt'], fallback: createdAt);
    return Highlight(
      id: map['id'] as String,
      bookId: map['bookId'] as String,
      anchor: map['anchor'] as String?,
      endOffset: (map['endOffset'] as num?)?.toInt(),
      excerpt: map['excerpt'] as String? ?? '',
      color: map['color'] as String? ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.anchor,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  final String? anchor;
  final String label;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'bookId': bookId,
        'anchor': anchor,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static Bookmark fromMap(Map<String, Object?> map) {
    return Bookmark(
      id: map['id'] as String,
      bookId: map['bookId'] as String,
      anchor: map['anchor'] as String?,
      label: map['label'] as String? ?? '',
      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDateOrNull(map['updatedAt']),
    );
  }
}

List<Map<String, Object?>> _readList(Object? value) {
  if (value is List) {
    return value.map(_coerceMap).toList();
  }
  return const <Map<String, Object?>>[];
}

List<TocNode> _readTocList(Object? value) {
  if (value is List) {
    return value
        .map(_coerceMap)
        .map((item) => TocNode.fromMap(item))
        .toList();
  }
  return const <TocNode>[];
}

TocMode _parseTocMode(Object? value) {
  if (value is String) {
    return TocMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => TocMode.official,
    );
  }
  return TocMode.official;
}

Map<String, Object?> _coerceMap(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return const <String, Object?>{};
}

DateTime _parseDate(Object? value, {DateTime? fallback}) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {}
  }
  return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _parseDateOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {}
  }
  return null;
}

class LibraryStore {
  static const String _boxName = 'library_books';
  static bool _initialized = false;
  static const Duration _positionEventDebounce = Duration(seconds: 5);
  static const int _positionOffsetDelta = 120;
  Box<dynamic>? _box;
  final EventLogStore _eventStore = EventLogStore();
  final Map<String, DateTime> _lastPositionEventAt = <String, DateTime>{};
  final Map<String, ReadingPosition> _lastPositionEventPosition =
      <String, ReadingPosition>{};

  Future<void> init() async {
    if (!_initialized) {
      await Hive.initFlutter();
      _initialized = true;
    }
    _box = await Hive.openBox<dynamic>(_boxName);
    await _eventStore.init();
  }

  Box<dynamic> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('LibraryStore not initialized');
    }
    return box;
  }

  Future<List<LibraryEntry>> loadAll() async {
    final box = _requireBox;
    return box.values
        .whereType<Map<Object?, Object?>>()
        .map((value) => LibraryEntry.fromMap(_coerceMap(value)))
        .toList();
  }

  Future<void> upsert(LibraryEntry entry) async {
    await _requireBox.put(entry.id, entry.toMap());
  }

  Future<void> remove(String id) async {
    await _requireBox.delete(id);
  }

  Future<void> clear() async {
    await _requireBox.clear();
  }

  Future<bool> existsByFingerprint(String fingerprint) async {
    return _requireBox.values.whereType<Map<Object?, Object?>>().any((value) {
      final map = _coerceMap(value);
      return map['fingerprint'] == fingerprint;
    });
  }

  Future<LibraryEntry?> getById(String id) async {
    final value = _requireBox.get(id);
    if (value == null) {
      return null;
    }
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    return LibraryEntry.fromMap(_coerceMap(value));
  }

  Future<void> updateReadingPosition(
    String id,
    ReadingPosition position,
  ) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    final previousPosition = entry.readingPosition;
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: position,
        progress: entry.progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: entry.notes,
        highlights: entry.highlights,
        bookmarks: entry.bookmarks,
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
    await _maybeLogReadingPosition(entry.id, position, previousPosition);
  }

  Future<void> updateProgress(
    String id,
    ReadingProgress progress,
  ) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: entry.notes,
        highlights: entry.highlights,
        bookmarks: entry.bookmarks,
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
  }

  Future<void> updateLastOpenedAt(String id, DateTime timestamp) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: entry.progress,
        lastOpenedAt: timestamp,
        notes: entry.notes,
        highlights: entry.highlights,
        bookmarks: entry.bookmarks,
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
  }

  Future<void> addNote(String id, Note note) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: entry.progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: [...entry.notes, note],
        highlights: entry.highlights,
        bookmarks: entry.bookmarks,
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
    await _logEvent(
      entityType: 'note',
      entityId: note.id,
      op: 'add',
      payload: note.toMap(),
    );
  }

  Future<void> removeNote(String id, String noteId) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    final updatedNotes =
        entry.notes.where((item) => item.id != noteId).toList();
    if (updatedNotes.length == entry.notes.length) {
      return;
    }
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: entry.progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: updatedNotes,
        highlights: entry.highlights,
        bookmarks: entry.bookmarks,
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
    await _logEvent(
      entityType: 'note',
      entityId: noteId,
      op: 'delete',
      payload: <String, Object?>{
        'id': noteId,
        'bookId': entry.id,
      },
    );
  }

  Future<void> updateNote(
    String id,
    String noteId,
    String noteText,
    DateTime updatedAt,
  ) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    var changed = false;
    Note? updatedNote;
    final updatedNotes = entry.notes.map((note) {
      if (note.id != noteId) {
        return note;
      }
      if (note.noteText == noteText && note.updatedAt == updatedAt) {
        return note;
      }
      changed = true;
      final next = Note(
        id: note.id,
        bookId: note.bookId,
        anchor: note.anchor,
        endOffset: note.endOffset,
        excerpt: note.excerpt,
        noteText: noteText,
        color: note.color,
        createdAt: note.createdAt,
        updatedAt: updatedAt,
      );
      updatedNote = next;
      return next;
    }).toList();
    if (!changed) {
      return;
    }
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: entry.progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: updatedNotes,
        highlights: entry.highlights,
        bookmarks: entry.bookmarks,
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
    final payload = updatedNote?.toMap() ??
        <String, Object?>{
          'id': noteId,
          'bookId': entry.id,
          'noteText': noteText,
          'updatedAt': updatedAt.toIso8601String(),
        };
    await _logEvent(
      entityType: 'note',
      entityId: noteId,
      op: 'update',
      payload: payload,
    );
  }

  Future<void> addHighlight(String id, Highlight highlight) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: entry.progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: entry.notes,
        highlights: [...entry.highlights, highlight],
        bookmarks: entry.bookmarks,
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
    await _logEvent(
      entityType: 'highlight',
      entityId: highlight.id,
      op: 'add',
      payload: highlight.toMap(),
    );
  }

  Future<void> removeHighlight(String id, String highlightId) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    final updatedHighlights =
        entry.highlights.where((item) => item.id != highlightId).toList();
    if (updatedHighlights.length == entry.highlights.length) {
      return;
    }
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: entry.progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: entry.notes,
        highlights: updatedHighlights,
        bookmarks: entry.bookmarks,
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
    await _logEvent(
      entityType: 'highlight',
      entityId: highlightId,
      op: 'delete',
      payload: <String, Object?>{
        'id': highlightId,
        'bookId': entry.id,
      },
    );
  }

  Future<void> addBookmark(String id, Bookmark bookmark) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: entry.progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: entry.notes,
        highlights: entry.highlights,
        bookmarks: [...entry.bookmarks, bookmark],
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
    await _logEvent(
      entityType: 'bookmark',
      entityId: bookmark.id,
      op: 'add',
      payload: bookmark.toMap(),
    );
  }

  Future<void> removeBookmark(String id, String bookmarkId) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    final updated =
        entry.bookmarks.where((item) => item.id != bookmarkId).toList();
    if (updated.length == entry.bookmarks.length) {
      return;
    }
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: entry.progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: entry.notes,
        highlights: entry.highlights,
        bookmarks: updated,
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
    await _logEvent(
      entityType: 'bookmark',
      entityId: bookmarkId,
      op: 'delete',
      payload: <String, Object?>{
        'id': bookmarkId,
        'bookId': entry.id,
      },
    );
  }

  Future<void> setBookmark(String id, Bookmark bookmark) async {
    final entry = await getById(id);
    if (entry == null) {
      return;
    }
    await upsert(
      LibraryEntry(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        localPath: entry.localPath,
        coverPath: entry.coverPath,
        addedAt: entry.addedAt,
        fingerprint: entry.fingerprint,
        sourcePath: entry.sourcePath,
        readingPosition: entry.readingPosition,
        progress: entry.progress,
        lastOpenedAt: entry.lastOpenedAt,
        notes: entry.notes,
        highlights: entry.highlights,
        bookmarks: <Bookmark>[bookmark],
        tocOfficial: entry.tocOfficial,
        tocGenerated: entry.tocGenerated,
        tocMode: entry.tocMode,
      ),
    );
    await _logEvent(
      entityType: 'bookmark',
      entityId: bookmark.id,
      op: 'add',
      payload: bookmark.toMap(),
    );
  }

  Future<void> _logEvent({
    required String entityType,
    required String entityId,
    required String op,
    required Map<String, Object?> payload,
  }) async {
    try {
      await _eventStore.addEvent(
        EventLogEntry(
          id: _makeEventId(),
          entityType: entityType,
          entityId: entityId,
          op: op,
          payload: payload,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      Log.d('Event log write failed: $e');
    }
  }

  Future<void> _maybeLogReadingPosition(
    String bookId,
    ReadingPosition position,
    ReadingPosition previousPosition,
  ) async {
    final chapterHref = position.chapterHref;
    final offset = position.offset;
    if (chapterHref == null || offset == null) {
      return;
    }
    final previousHref = previousPosition.chapterHref;
    final previousOffset = previousPosition.offset;
    if (previousHref == chapterHref &&
        previousOffset != null &&
        (offset - previousOffset).abs() < _positionOffsetDelta) {
      return;
    }
    final now = DateTime.now();
    final lastAt = _lastPositionEventAt[bookId];
    if (lastAt != null &&
        now.difference(lastAt) < _positionEventDebounce) {
      return;
    }
    final lastPosition = _lastPositionEventPosition[bookId];
    if (lastPosition != null &&
        lastPosition.chapterHref == chapterHref &&
        lastPosition.offset != null &&
        (offset - lastPosition.offset!).abs() < _positionOffsetDelta) {
      return;
    }
    _lastPositionEventAt[bookId] = now;
    _lastPositionEventPosition[bookId] = position;
    await _logEvent(
      entityType: 'reading_position',
      entityId: bookId,
      op: 'update',
      payload: <String, Object?>{
        'bookId': bookId,
        'chapterHref': chapterHref,
        'anchor': position.anchor,
        'offset': offset,
        'updatedAt': position.updatedAt?.toIso8601String(),
      },
    );
  }
}

String _makeEventId() {
  return 'evt-${DateTime.now().microsecondsSinceEpoch}';
}
