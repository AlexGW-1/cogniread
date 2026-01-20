import 'dart:io';

import 'package:cogniread/src/features/search/search_index_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SearchIndexService exportSnapshot writes sqlite file', () async {
    final originalPlatform = PathProviderPlatform.instance;
    final supportDir = await Directory.systemTemp.createTemp(
      'cogniread_search_snapshot_',
    );
    PathProviderPlatform.instance = _TestPathProviderPlatform(supportDir.path);
    try {
      final db = sqlite3.openInMemory();
      final service = SearchIndexService(database: db);
      await service.status();

      final snapshot = await service.exportSnapshot(
        fileName: 'search_index_snapshot_test.sqlite',
      );

      expect(snapshot, isNotNull);
      expect(await snapshot!.exists(), isTrue);
      final header = await snapshot.openRead(0, 16).first;
      expect(String.fromCharCodes(header), startsWith('SQLite format 3'));
    } finally {
      PathProviderPlatform.instance = originalPlatform;
      await supportDir.delete(recursive: true);
    }
  });
}

