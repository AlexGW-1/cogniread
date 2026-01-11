import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/sync/data/event_log_store.dart';

const int kSyncDtoSchemaVersion = 1;

class NoteDto {
  const NoteDto({
    required this.id,
    required this.bookId,
    required this.anchor,
    required this.endOffset,
    required this.excerpt,
    required this.noteText,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    required this.schemaVersion,
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
  final int schemaVersion;

  factory NoteDto.fromDomain(Note note) {
    return NoteDto(
      id: note.id,
      bookId: note.bookId,
      anchor: note.anchor,
      endOffset: note.endOffset,
      excerpt: note.excerpt,
      noteText: note.noteText,
      color: note.color,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      schemaVersion: kSyncDtoSchemaVersion,
    );
  }

  Note toDomain() {
    return Note(
      id: id,
      bookId: bookId,
      anchor: anchor,
      endOffset: endOffset,
      excerpt: excerpt,
      noteText: noteText,
      color: color,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'schemaVersion': schemaVersion,
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

  static NoteDto fromMap(Map<String, Object?> map) {
    return NoteDto(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ??
          kSyncDtoSchemaVersion,
      id: map['id'] as String? ?? '',
      bookId: map['bookId'] as String? ?? '',
      anchor: map['anchor'] as String?,
      endOffset: (map['endOffset'] as num?)?.toInt(),
      excerpt: map['excerpt'] as String? ?? '',
      noteText: map['noteText'] as String? ?? '',
      color: map['color'] as String? ?? 'yellow',
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}

class HighlightDto {
  const HighlightDto({
    required this.id,
    required this.bookId,
    required this.anchor,
    required this.endOffset,
    required this.excerpt,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    required this.schemaVersion,
  });

  final String id;
  final String bookId;
  final String? anchor;
  final int? endOffset;
  final String excerpt;
  final String color;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;

  factory HighlightDto.fromDomain(Highlight highlight) {
    return HighlightDto(
      id: highlight.id,
      bookId: highlight.bookId,
      anchor: highlight.anchor,
      endOffset: highlight.endOffset,
      excerpt: highlight.excerpt,
      color: highlight.color,
      createdAt: highlight.createdAt,
      updatedAt: highlight.updatedAt,
      schemaVersion: kSyncDtoSchemaVersion,
    );
  }

  Highlight toDomain() {
    return Highlight(
      id: id,
      bookId: bookId,
      anchor: anchor,
      endOffset: endOffset,
      excerpt: excerpt,
      color: color,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'id': id,
        'bookId': bookId,
        'anchor': anchor,
        'endOffset': endOffset,
        'excerpt': excerpt,
        'color': color,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static HighlightDto fromMap(Map<String, Object?> map) {
    return HighlightDto(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ??
          kSyncDtoSchemaVersion,
      id: map['id'] as String? ?? '',
      bookId: map['bookId'] as String? ?? '',
      anchor: map['anchor'] as String?,
      endOffset: (map['endOffset'] as num?)?.toInt(),
      excerpt: map['excerpt'] as String? ?? '',
      color: map['color'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}

class BookmarkDto {
  const BookmarkDto({
    required this.id,
    required this.bookId,
    required this.anchor,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
    required this.schemaVersion,
  });

  final String id;
  final String bookId;
  final String? anchor;
  final String label;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int schemaVersion;

  factory BookmarkDto.fromDomain(Bookmark bookmark) {
    return BookmarkDto(
      id: bookmark.id,
      bookId: bookmark.bookId,
      anchor: bookmark.anchor,
      label: bookmark.label,
      createdAt: bookmark.createdAt,
      updatedAt: bookmark.updatedAt,
      schemaVersion: kSyncDtoSchemaVersion,
    );
  }

  Bookmark toDomain() {
    return Bookmark(
      id: id,
      bookId: bookId,
      anchor: anchor,
      label: label,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'id': id,
        'bookId': bookId,
        'anchor': anchor,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static BookmarkDto fromMap(Map<String, Object?> map) {
    return BookmarkDto(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ??
          kSyncDtoSchemaVersion,
      id: map['id'] as String? ?? '',
      bookId: map['bookId'] as String? ?? '',
      anchor: map['anchor'] as String?,
      label: map['label'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt'] as String),
    );
  }
}

class ReadingPositionDto {
  const ReadingPositionDto({
    required this.chapterHref,
    required this.anchor,
    required this.offset,
    required this.updatedAt,
    required this.schemaVersion,
  });

  final String? chapterHref;
  final String? anchor;
  final int? offset;
  final DateTime? updatedAt;
  final int schemaVersion;

  factory ReadingPositionDto.fromDomain(ReadingPosition position) {
    return ReadingPositionDto(
      chapterHref: position.chapterHref,
      anchor: position.anchor,
      offset: position.offset,
      updatedAt: position.updatedAt,
      schemaVersion: kSyncDtoSchemaVersion,
    );
  }

  ReadingPosition toDomain() {
    return ReadingPosition(
      chapterHref: chapterHref,
      anchor: anchor,
      offset: offset,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'chapterHref': chapterHref,
        'anchor': anchor,
        'offset': offset,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static ReadingPositionDto fromMap(Map<String, Object?> map) {
    return ReadingPositionDto(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ??
          kSyncDtoSchemaVersion,
      chapterHref: map['chapterHref'] as String?,
      anchor: map['anchor'] as String?,
      offset: (map['offset'] as num?)?.toInt(),
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt'] as String),
    );
  }
}

class EventLogEntryDto {
  const EventLogEntryDto({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.op,
    required this.payload,
    required this.createdAt,
    required this.schemaVersion,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String op;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final int schemaVersion;

  factory EventLogEntryDto.fromDomain(EventLogEntry entry) {
    return EventLogEntryDto(
      id: entry.id,
      entityType: entry.entityType,
      entityId: entry.entityId,
      op: entry.op,
      payload: entry.payload,
      createdAt: entry.createdAt,
      schemaVersion: kSyncDtoSchemaVersion,
    );
  }

  EventLogEntry toDomain() {
    return EventLogEntry(
      id: id,
      entityType: entityType,
      entityId: entityId,
      op: op,
      payload: payload,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'id': id,
        'entityType': entityType,
        'entityId': entityId,
        'op': op,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
      };

  static EventLogEntryDto fromMap(Map<String, Object?> map) {
    return EventLogEntryDto(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ??
          kSyncDtoSchemaVersion,
      id: map['id'] as String? ?? '',
      entityType: map['entityType'] as String? ?? '',
      entityId: map['entityId'] as String? ?? '',
      op: map['op'] as String? ?? '',
      payload: _coercePayload(map['payload']),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

Map<String, Object?> _coercePayload(Object? payload) {
  if (payload is Map<Object?, Object?>) {
    return payload.map(
      (key, value) => MapEntry(key?.toString() ?? '', value),
    );
  }
  if (payload is Map<String, Object?>) {
    return payload;
  }
  return const <String, Object?>{};
}
