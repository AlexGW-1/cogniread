import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/book.dart';

abstract class LibraryRepository {
  Future<List<Book>> listBooks();
}

class InMemoryLibraryRepository implements LibraryRepository {
  @override
  Future<List<Book>> listBooks() async {
    // TODO (1.3): заменить на импорт + локальное хранилище (Drift/Hive)
    return const [
      Book(id: 'demo-1', title: 'Demo Book #1', author: 'CogniRead'),
      Book(id: 'demo-2', title: 'Demo Book #2', author: 'CogniRead'),
    ];
  }
}

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return InMemoryLibraryRepository();
});

final libraryBooksProvider = FutureProvider<List<Book>>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.listBooks();
});
