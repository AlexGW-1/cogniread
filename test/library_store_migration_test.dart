import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LibraryEntry.fromMap handles missing fields', () {
    final createdAt = DateTime(2026, 1, 11, 10);
    final map = <String, Object?>{
      'id': 'book-1',
      'title': 'Title',
      'author': null,
      'localPath': '/tmp/book.epub',
      'addedAt': createdAt.toIso8601String(),
      'fingerprint': 'hash',
      'sourcePath': '/tmp/book.epub',
      'readingPosition': <String, Object?>{},
      'progress': <String, Object?>{},
      'notes': [
        {
          'id': 'note-1',
          'bookId': 'book-1',
          'anchor': null,
          'excerpt': 'Excerpt',
          'noteText': 'Note text',
          'color': 'yellow',
          'createdAt': createdAt.toIso8601String(),
        },
      ],
      'highlights': [
        {
          'id': 'hl-1',
          'bookId': 'book-1',
          'anchor': null,
          'excerpt': 'Excerpt',
          'color': 'yellow',
          'createdAt': createdAt.toIso8601String(),
        },
      ],
      'bookmarks': [
        {
          'id': 'bm-1',
          'bookId': 'book-1',
          'anchor': null,
          'label': 'Bookmark',
          'createdAt': createdAt.toIso8601String(),
        },
      ],
      'tocOfficial': const <Object?>[],
      'tocGenerated': const <Object?>[],
      'tocMode': 'official',
    };

    final entry = LibraryEntry.fromMap(map);

    expect(entry.coverPath, isNull);
    expect(entry.notes.single.updatedAt, entry.notes.single.createdAt);
    expect(entry.highlights.single.updatedAt, entry.highlights.single.createdAt);
    expect(entry.bookmarks.single.updatedAt, isNull);
  });
}
