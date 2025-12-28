import 'package:cogniread_app/src/core/types/result.dart';
import 'package:cogniread_app/src/features/reader/domain/entities/book.dart';

abstract class BookRepository {
  /// Import an EPUB from a local path.
  /// Implementation will be macOS-safe (permissions, sandboxed paths, temp copies).
  Future<Result<Book>> importEpubFromPath(String path);
}
