import 'package:cogniread/src/core/types/result.dart';
import 'package:cogniread/src/features/reader/data/datasources/epub_local_datasource.dart';
import 'package:cogniread/src/features/reader/domain/entities/book.dart';
import 'package:cogniread/src/features/reader/domain/repositories/book_repository.dart';

class BookRepositoryImpl implements BookRepository {
  BookRepositoryImpl(this._ds);
  final EpubLocalDatasource _ds;

  @override
  Future<Result<Book>> importEpubFromPath(String path) async {
    try {
      final book = await _ds.importFromPath(path);
      return Ok(book);
    } catch (e) {
      return Err('Failed to import EPUB: $e');
    }
  }
}
