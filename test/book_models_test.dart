import 'package:cogniread/src/features/reader/data/models/book_dto.dart';
import 'package:cogniread/src/features/reader/data/models/book_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BookDto fromMap validates required fields', () {
    final map = <String, Object?>{
      'id': 'book-1',
      'title': 'Test Book',
      'sourcePath': '/tmp/book.epub',
      'author': 'Author',
    };

    final dto = BookDto.fromMap(map);
    expect(dto.id, 'book-1');
    expect(dto.title, 'Test Book');
    expect(dto.sourcePath, '/tmp/book.epub');
    expect(dto.author, 'Author');
  });

  test('BookDto fromMap rejects missing title', () {
    final map = <String, Object?>{
      'id': 'book-1',
      'sourcePath': '/tmp/book.epub',
    };

    expect(() => BookDto.fromMap(map), throwsA(isA<FormatException>()));
  });

  test('BookRecord fromMap rejects empty id', () {
    final map = <String, Object?>{
      'id': '',
      'title': 'Test Book',
      'sourcePath': '/tmp/book.epub',
    };

    expect(() => BookRecord.fromMap(map), throwsA(isA<FormatException>()));
  });

  test('BookRecord fromMap rejects non-string author', () {
    final map = <String, Object?>{
      'id': 'book-1',
      'title': 'Test Book',
      'sourcePath': '/tmp/book.epub',
      'author': 123,
    };

    expect(() => BookRecord.fromMap(map), throwsA(isA<FormatException>()));
  });
}
