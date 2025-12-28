import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/features/reader/domain/entities/book.dart';
import 'package:path/path.dart' as p;

/// Stub datasource.
///
/// Next step:
/// - copy selected file into app-managed directory (Application Support/Docs)
/// - extract metadata (title/author) from EPUB
/// - return a Book model
class EpubLocalDatasource {
  EpubLocalDatasource(this._storage);

  final StorageService _storage;

  Future<Book> importFromPath(String path) async {
    final storedPath = await _storage.copyToAppStorage(path);
    final title = p.basenameWithoutExtension(storedPath);
    return Book(
      id: storedPath,
      title: title,
      sourcePath: storedPath,
    );
  }
}
