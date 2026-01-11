import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/sync/data/dto.dart';
import 'package:cogniread/src/features/sync/data/event_log_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('note dto roundtrip', () {
    final note = Note(
      id: 'note-1',
      bookId: 'book-1',
      anchor: 'chapter|10',
      endOffset: 42,
      excerpt: 'Excerpt text',
      noteText: 'Note text',
      color: 'pink',
      createdAt: DateTime(2026, 1, 12, 10),
      updatedAt: DateTime(2026, 1, 12, 10, 5),
    );
    final dto = NoteDto.fromDomain(note);
    final mapped = NoteDto.fromMap(dto.toMap()).toDomain();

    expect(mapped.id, note.id);
    expect(mapped.bookId, note.bookId);
    expect(mapped.anchor, note.anchor);
    expect(mapped.endOffset, note.endOffset);
    expect(mapped.excerpt, note.excerpt);
    expect(mapped.noteText, note.noteText);
    expect(mapped.color, note.color);
    expect(mapped.createdAt, note.createdAt);
    expect(mapped.updatedAt, note.updatedAt);
  });

  test('highlight dto roundtrip', () {
    final highlight = Highlight(
      id: 'hl-1',
      bookId: 'book-1',
      anchor: 'chapter|11',
      endOffset: 99,
      excerpt: 'Highlight',
      color: 'yellow',
      createdAt: DateTime(2026, 1, 12, 11),
      updatedAt: DateTime(2026, 1, 12, 11, 2),
    );
    final dto = HighlightDto.fromDomain(highlight);
    final mapped = HighlightDto.fromMap(dto.toMap()).toDomain();

    expect(mapped.id, highlight.id);
    expect(mapped.bookId, highlight.bookId);
    expect(mapped.anchor, highlight.anchor);
    expect(mapped.endOffset, highlight.endOffset);
    expect(mapped.excerpt, highlight.excerpt);
    expect(mapped.color, highlight.color);
    expect(mapped.createdAt, highlight.createdAt);
    expect(mapped.updatedAt, highlight.updatedAt);
  });

  test('bookmark dto roundtrip', () {
    final bookmark = Bookmark(
      id: 'bm-1',
      bookId: 'book-1',
      anchor: 'chapter|5',
      label: 'Закладка',
      createdAt: DateTime(2026, 1, 12, 12),
      updatedAt: DateTime(2026, 1, 12, 12, 1),
    );
    final dto = BookmarkDto.fromDomain(bookmark);
    final mapped = BookmarkDto.fromMap(dto.toMap()).toDomain();

    expect(mapped.id, bookmark.id);
    expect(mapped.bookId, bookmark.bookId);
    expect(mapped.anchor, bookmark.anchor);
    expect(mapped.label, bookmark.label);
    expect(mapped.createdAt, bookmark.createdAt);
    expect(mapped.updatedAt, bookmark.updatedAt);
  });

  test('reading position dto roundtrip', () {
    final position = ReadingPosition(
      chapterHref: 'chapter-1',
      anchor: 'anchor',
      offset: 100,
      updatedAt: DateTime(2026, 1, 12, 13),
    );
    final dto = ReadingPositionDto.fromDomain(position);
    final mapped = ReadingPositionDto.fromMap(dto.toMap()).toDomain();

    expect(mapped.chapterHref, position.chapterHref);
    expect(mapped.anchor, position.anchor);
    expect(mapped.offset, position.offset);
    expect(mapped.updatedAt, position.updatedAt);
  });

  test('event log dto roundtrip', () {
    final entry = EventLogEntry(
      id: 'evt-1',
      entityType: 'note',
      entityId: 'note-1',
      op: 'add',
      payload: const <String, Object?>{'value': 'text'},
      createdAt: DateTime(2026, 1, 12, 14),
    );
    final dto = EventLogEntryDto.fromDomain(entry);
    final mapped = EventLogEntryDto.fromMap(dto.toMap()).toDomain();

    expect(mapped.id, entry.id);
    expect(mapped.entityType, entry.entityType);
    expect(mapped.entityId, entry.entityId);
    expect(mapped.op, entry.op);
    expect(mapped.payload, entry.payload);
    expect(mapped.createdAt, entry.createdAt);
  });
}
