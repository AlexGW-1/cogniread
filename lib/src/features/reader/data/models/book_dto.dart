import 'package:cogniread/src/features/reader/domain/entities/book.dart';

class BookDto {
  const BookDto({
    required this.id,
    required this.title,
    required this.sourcePath,
    required this.fingerprint,
    this.author,
  });

  final String id;
  final String title;
  final String sourcePath;
  final String fingerprint;
  final String? author;

  factory BookDto.fromEntity(Book book) {
    return BookDto(
      id: book.id,
      title: book.title,
      sourcePath: book.sourcePath,
      fingerprint: book.fingerprint,
      author: book.author,
    );
  }

  Book toEntity() => Book(
        id: id,
        title: title,
        sourcePath: sourcePath,
        fingerprint: fingerprint,
        author: author,
      );

  factory BookDto.fromMap(Map<String, Object?> map) {
    _validateMap(map);
    return BookDto(
      id: _requireString(map, 'id'),
      title: _requireString(map, 'title'),
      sourcePath: _requireString(map, 'sourcePath'),
      fingerprint: _requireString(map, 'fingerprint'),
      author: _optionalString(map, 'author'),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'title': title,
        'sourcePath': sourcePath,
        'fingerprint': fingerprint,
        'author': author,
      };

  static void _validateMap(Map<String, Object?> map) {
    _requireString(map, 'id');
    _requireString(map, 'title');
    _requireString(map, 'sourcePath');
    _requireString(map, 'fingerprint');
    _optionalString(map, 'author');
  }

  static String _requireString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('BookDto.$key is required');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException('BookDto.$key must be a string');
    }
    return value;
  }
}
