import 'package:cogniread_app/src/core/types/result.dart';
import 'package:cogniread_app/src/features/reader/domain/entities/book.dart';
import 'package:cogniread_app/src/features/reader/domain/repositories/book_repository.dart';

class ImportEpub {
  ImportEpub(this._repo);
  final BookRepository _repo;

  Future<Result<Book>> call(String path) => _repo.importEpubFromPath(path);
}
