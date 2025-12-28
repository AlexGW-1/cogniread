import 'package:cogniread/src/core/types/result.dart';
import 'package:cogniread/src/features/reader/domain/entities/book.dart';

abstract class BookRepository {
  /// Import an EPUB from a local path.
  /// Implementation will be macOS-safe (permissions, sandboxed paths, temp copies).
  Future<Result<Book>> importEpubFromPath(String path);
}
