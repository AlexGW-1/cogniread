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
    await tester.pumpAndSettle();

    expect(find.textContaining('Imported book (stub)'), findsOneWidget);
    await tester.tap(find.textContaining('Imported book (stub)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Imported book (stub)'), findsOneWidget);
    expect(find.textContaining('Reader UI stub'), findsOneWidget);
  });
}
