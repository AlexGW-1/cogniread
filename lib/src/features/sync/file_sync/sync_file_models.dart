import 'dart:convert';

import 'package:cogniread/src/features/sync/data/event_log_store.dart';

class SyncEventLogFile {
  const SyncEventLogFile({
    required this.schemaVersion,
    required this.deviceId,
    required this.generatedAt,
    required this.events,
    this.cursor,
  });

  final int schemaVersion;
  final String deviceId;
  final DateTime generatedAt;
  final List<EventLogEntry> events;
  final String? cursor;

  Map<String, Object?> toMap() => {
        'schemaVersion': schemaVersion,
        'deviceId': deviceId,
        'generatedAt': generatedAt.toIso8601String(),
        'cursor': cursor,
        'events': events.map((event) => event.toMap()).toList(),
      };

  List<int> toJsonBytes() => utf8.encode(jsonEncode(toMap()));

  static SyncEventLogFile fromMap(Map<String, Object?> map) {
    final eventsRaw = map['events'];
    final events = eventsRaw is List
        ? eventsRaw
            .whereType<Map<Object?, Object?>>()
            .map((item) => EventLogEntry.fromMap(_coerceMap(item)))
            .toList()
        : <EventLogEntry>[];
    return SyncEventLogFile(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      deviceId: map['deviceId'] as String? ?? 'unknown',
      generatedAt: DateTime.parse(
        map['generatedAt'] as String? ?? DateTime.now().toIso8601String(),
      ),
      cursor: map['cursor'] as String?,
      events: events,
    );
  }
}

class SyncStateFile {
  const SyncStateFile({
    required this.schemaVersion,
    required this.generatedAt,
    required this.readingPositions,
    this.cursor,
  });

  final int schemaVersion;
  final DateTime generatedAt;
  final List<SyncReadingPosition> readingPositions;
  final String? cursor;

  Map<String, Object?> toMap() => {
        'schemaVersion': schemaVersion,
        'generatedAt': generatedAt.toIso8601String(),
        'cursor': cursor,
        'readingPositions': readingPositions.map((pos) => pos.toMap()).toList(),
      };

  List<int> toJsonBytes() => utf8.encode(jsonEncode(toMap()));

  static SyncStateFile fromMap(Map<String, Object?> map) {
    final positionsRaw = map['readingPositions'];
    final positions = positionsRaw is List
        ? positionsRaw
            .whereType<Map<Object?, Object?>>()
            .map((item) => SyncReadingPosition.fromMap(_coerceMap(item)))
            .toList()
        : <SyncReadingPosition>[];
    return SyncStateFile(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      generatedAt: DateTime.parse(
        map['generatedAt'] as String? ?? DateTime.now().toIso8601String(),
      ),
      cursor: map['cursor'] as String?,
      readingPositions: positions,
    );
  }
}

class SyncReadingPosition {
  const SyncReadingPosition({
    required this.bookId,
    required this.chapterHref,
    required this.anchor,
    required this.offset,
    required this.updatedAt,
  });

  final String bookId;
  final String? chapterHref;
  final String? anchor;
  final int? offset;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'bookId': bookId,
        'chapterHref': chapterHref,
        'anchor': anchor,
        'offset': offset,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static SyncReadingPosition fromMap(Map<String, Object?> map) {
    return SyncReadingPosition(
      bookId: map['bookId'] as String? ?? '',
      chapterHref: map['chapterHref'] as String?,
      anchor: map['anchor'] as String?,
      offset: (map['offset'] as num?)?.toInt(),
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt'] as String),
    );
  }
}

Map<String, Object?> _coerceMap(Map<Object?, Object?> source) {
  return source.map(
    (key, value) => MapEntry(key?.toString() ?? '', value),
  );
}

class SyncMetaFile {
  const SyncMetaFile({
    required this.schemaVersion,
    required this.deviceId,
    required this.lastUploadAt,
    required this.lastDownloadAt,
    required this.eventCount,
  });

  final int schemaVersion;
  final String deviceId;
  final DateTime? lastUploadAt;
  final DateTime? lastDownloadAt;
  final int eventCount;

  Map<String, Object?> toMap() => {
        'schemaVersion': schemaVersion,
        'deviceId': deviceId,
        'lastUploadAt': lastUploadAt?.toIso8601String(),
        'lastDownloadAt': lastDownloadAt?.toIso8601String(),
        'eventCount': eventCount,
      };

  List<int> toJsonBytes() => utf8.encode(jsonEncode(toMap()));

  static SyncMetaFile fromMap(Map<String, Object?> map) {
    return SyncMetaFile(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      deviceId: map['deviceId'] as String? ?? 'unknown',
      lastUploadAt: map['lastUploadAt'] == null
          ? null
          : DateTime.parse(map['lastUploadAt'] as String),
      lastDownloadAt: map['lastDownloadAt'] == null
          ? null
          : DateTime.parse(map['lastDownloadAt'] as String),
      eventCount: (map['eventCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SyncBookDescriptor {
  const SyncBookDescriptor({
    required this.id,
    required this.title,
    required this.fingerprint,
    required this.size,
    required this.updatedAt,
    required this.extension,
    this.author,
    this.path,
    this.deleted = false,
  });

  final String id;
  final String title;
  final String? author;
  final String fingerprint;
  final int size;
  final DateTime updatedAt;
  final String extension;
  final String? path;
  final bool deleted;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'title': title,
        'author': author,
        'fingerprint': fingerprint,
        'size': size,
        'updatedAt': updatedAt.toIso8601String(),
        'extension': extension,
        'path': path,
        'deleted': deleted,
      };

  static SyncBookDescriptor fromMap(Map<String, Object?> map) {
    final updated = map['updatedAt'];
    final path = map['path'] as String?;
    return SyncBookDescriptor(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      author: map['author'] as String?,
      fingerprint: map['fingerprint'] as String? ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
      updatedAt: updated is String
          ? DateTime.tryParse(updated) ?? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0),
      extension: map['extension'] as String? ?? '',
      path: path?.isEmpty == true ? null : path,
      deleted: map['deleted'] as bool? ?? false,
    );
  }
}

class SyncBooksIndexFile {
  const SyncBooksIndexFile({
    required this.schemaVersion,
    required this.generatedAt,
    required this.books,
  });

  final int schemaVersion;
  final DateTime generatedAt;
  final List<SyncBookDescriptor> books;

  Map<String, Object?> toMap() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'generatedAt': generatedAt.toIso8601String(),
        'books': books.map((book) => book.toMap()).toList(),
      };

  List<int> toJsonBytes() => utf8.encode(jsonEncode(toMap()));

  static SyncBooksIndexFile fromMap(Map<String, Object?> map) {
    final booksRaw = map['books'];
    final books = booksRaw is List
        ? booksRaw
            .whereType<Map<Object?, Object?>>()
            .map((raw) => SyncBookDescriptor.fromMap(_coerceMap(raw)))
            .toList()
        : <SyncBookDescriptor>[];
    return SyncBooksIndexFile(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      generatedAt: DateTime.tryParse(map['generatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      books: books,
    );
  }
}
