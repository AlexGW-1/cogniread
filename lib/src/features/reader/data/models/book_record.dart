import 'package:cogniread/src/features/reader/data/models/book_dto.dart';

class BookRecord {
  const BookRecord({
    required this.id,
    required this.title,
    required this.sourcePath,
    this.author,
  });

  final String id;
  final String title;
  final String sourcePath;
  final String? author;

  factory BookRecord.fromDto(BookDto dto) {
    return BookRecord(
      id: dto.id,
      title: dto.title,
      sourcePath: dto.sourcePath,
      author: dto.author,
    );
  }

  BookDto toDto() => BookDto(
        id: id,
        title: title,
        sourcePath: sourcePath,
        author: author,
      );

  factory BookRecord.fromMap(Map<String, Object?> map) {
    _validateMap(map);
    return BookRecord(
      id: _requireString(map, 'id'),
      title: _requireString(map, 'title'),
      sourcePath: _requireString(map, 'sourcePath'),
      author: _optionalString(map, 'author'),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'title': title,
        'sourcePath': sourcePath,
        'author': author,
      };

  static void _validateMap(Map<String, Object?> map) {
    _requireString(map, 'id');
    _requireString(map, 'title');
    _requireString(map, 'sourcePath');
    _optionalString(map, 'author');
  }

  static String _requireString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('BookRecord.$key is required');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException('BookRecord.$key must be a string');
    }
    return value;
  }
}
