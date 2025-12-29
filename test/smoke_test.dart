import 'package:cogniread/src/app.dart';
import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestStorageService implements StorageService {
  @override
  Future<String> appStoragePath() async => '/tmp';

  @override
  Future<String> copyToAppStorage(String sourcePath) async {
    return sourcePath;
  }

  @override
  Future<StoredFile> copyToAppStorageWithHash(String sourcePath) async {
    return const StoredFile(
      path: '/tmp/book.epub',
      hash: 'hash',
      alreadyExists: false,
    );
  }
}

void main() {
  testWidgets('App boots', (tester) async {
    await tester.pumpWidget(const CogniReadApp());
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('Library to Reader navigation', (tester) async {
    await tester.pumpWidget(
      CogniReadApp(
        pickEpubPath: () async => '/tmp/book.epub',
        storageService: _TestStorageService(),
        stubImport: true,
      ),
    );
    expect(find.text('Library'), findsOneWidget);

    await tester.tap(find.text('Импортировать EPUB (заглушка)'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Imported book (stub)'), findsOneWidget);
    expect(find.textContaining('Imported book (stub)'), findsOneWidget);
  });
}
