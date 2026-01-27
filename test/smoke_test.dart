import 'dart:io';

import 'package:cogniread/src/app.dart';
import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/features/library/presentation/library_screen.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => supportPath;
}

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform originalPlatform;
  late Directory supportDir;

  setUpAll(() async {
    originalPlatform = PathProviderPlatform.instance;
    supportDir = await Directory.systemTemp.createTemp('cogniread_smoke_');
    PathProviderPlatform.instance =
        _TestPathProviderPlatform(supportDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPlatform;
    await supportDir.delete(recursive: true);
  });

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
    await tester.pump();
    for (var i = 0; i < 20; i += 1) {
      if (find.byKey(const ValueKey('import-epub-button'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LibraryScreen), findsOneWidget);

    Finder? findBookTile() {
      final listTile = find.byKey(const ValueKey('library-book-tile-0'));
      if (listTile.evaluate().isNotEmpty) {
        return listTile;
      }
      final gridTile = find.byKey(const ValueKey('library-book-grid-0'));
      if (gridTile.evaluate().isNotEmpty) {
        return gridTile;
      }
      final cardTile = find.byKey(const ValueKey('library-book-card-0'));
      if (cardTile.evaluate().isNotEmpty) {
        return cardTile;
      }
      return null;
    }

    Future<Finder?> waitForBookTile() async {
      for (var i = 0; i < 30; i += 1) {
        if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
          await tester.pump(const Duration(milliseconds: 100));
          continue;
        }
        final tile = findBookTile();
        if (tile != null) {
          return tile;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      return null;
    }

    Future<void> ensureListView() async {
      final toggleToList = find.byTooltip('Список');
      if (toggleToList.evaluate().isNotEmpty) {
        await tester.tap(toggleToList);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await ensureListView();
    var tappableBook = await waitForBookTile();
    if (tappableBook == null) {
      final importButton = find.byKey(const ValueKey('import-epub-button'));
      if (importButton.evaluate().isNotEmpty) {
        await tester.tap(importButton);
      } else {
        await tester.tap(find.byKey(const ValueKey('import-epub-fab')));
      }
      await tester.pump(const Duration(milliseconds: 100));
      await ensureListView();
      tappableBook = await waitForBookTile();
    }
    if (tappableBook == null) {
      await tester.pump(const Duration(seconds: 2));
      await ensureListView();
      tappableBook = findBookTile();
    }
    expect(tappableBook, isNotNull);
    await tester.tap(tappableBook!);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ReaderScreen), findsOneWidget);
  });
}
