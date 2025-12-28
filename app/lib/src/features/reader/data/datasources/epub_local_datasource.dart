import 'package:cogniread_app/src/core/error/exceptions.dart';
import 'package:cogniread_app/src/features/reader/domain/entities/book.dart';

/// Stub datasource.
///
/// Next step:
/// - copy selected file into app-managed directory (Application Support/Docs)
/// - extract metadata (title/author) from EPUB
/// - return a Book model
class EpubLocalDatasource {
  Future<Book> importFromPath(String path) async {
    throw NotImplementedYetException(
      'EPUB import is not implemented yet. Path: $path',
    );
  }
}
