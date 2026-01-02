import 'package:cogniread/src/app.dart';
import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/features/library/presentation/library_screen.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
import 'package:flutter/material.dart';
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
    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('Library to Reader navigation', (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      CogniReadApp(
        pickEpubPath: () async => '/tmp/book.epub',
        storageService: _TestStorageService(),
        stubImport: true,
      ),
    );
    expect(find.byType(LibraryScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-epub-button')));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ReaderScreen), findsOneWidget);
  });
}
