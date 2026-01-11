import 'dart:io';

import 'package:cogniread/src/core/services/storage_service_impl.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform originalPlatform;
  late Directory supportDir;

  setUpAll(() {
    originalPlatform = PathProviderPlatform.instance;
  });

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('cogniread_support_');
    PathProviderPlatform.instance =
        _TestPathProviderPlatform(supportDir.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPlatform;
    await supportDir.delete(recursive: true);
  });

  test('copyToAppStorageWithHash copies file into app storage', () async {
    final service = AppStorageService();
    final sourceDir = await Directory.systemTemp.createTemp('cogniread_src_');
    addTearDown(() => sourceDir.delete(recursive: true));
    final sourcePath = p.join(sourceDir.path, 'My Book.epub');
    final bytes = <int>[1, 2, 3, 4, 5];
    await File(sourcePath).writeAsBytes(bytes);

    final stored = await service.copyToAppStorageWithHash(sourcePath);

    expect(stored.alreadyExists, isFalse);
    expect(stored.hash, sha256.convert(bytes).toString());
    expect(await File(stored.path).exists(), isTrue);
    final expectedDir = p.join(supportDir.path, 'books');
    expect(p.dirname(stored.path), expectedDir);
    expect(p.basename(stored.path), 'My_Book_${stored.hash}.epub');
  });

  test('copyToAppStorageWithHash accepts fb2 and zip extensions', () async {
    final service = AppStorageService();
    final sourceDir = await Directory.systemTemp.createTemp('cogniread_src_');
    addTearDown(() => sourceDir.delete(recursive: true));
    final fb2Path = p.join(sourceDir.path, 'Book.fb2');
    final zipPath = p.join(sourceDir.path, 'Book.fb2.zip');
    await File(fb2Path).writeAsBytes(<int>[1, 2, 3]);
    await File(zipPath).writeAsBytes(<int>[4, 5, 6]);

    final fb2Stored = await service.copyToAppStorageWithHash(fb2Path);
    final zipStored = await service.copyToAppStorageWithHash(zipPath);

    expect(fb2Stored.path, endsWith('.fb2'));
    expect(zipStored.path, endsWith('.zip'));
  });

  test('copyToAppStorageWithHash dedups by fingerprint', () async {
    final service = AppStorageService();
    final sourceDir = await Directory.systemTemp.createTemp('cogniread_src_');
    addTearDown(() => sourceDir.delete(recursive: true));
    final sourcePath = p.join(sourceDir.path, 'dedup.epub');
    await File(sourcePath).writeAsBytes(<int>[9, 9, 9]);

    final first = await service.copyToAppStorageWithHash(sourcePath);
    final second = await service.copyToAppStorageWithHash(sourcePath);

    expect(first.alreadyExists, isFalse);
    expect(second.alreadyExists, isTrue);
    expect(second.path, first.path);
    final storedFiles = Directory(p.join(supportDir.path, 'books'))
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.epub'))
        .toList();
    expect(storedFiles.length, 1);
  });

  test('copyToAppStorageWithHash throws for missing file', () async {
    final service = AppStorageService();
    await expectLater(
      () => service.copyToAppStorageWithHash('/tmp/missing.epub'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('copyToAppStorageWithHash rejects unsupported extension', () async {
    final service = AppStorageService();
    final sourceDir = await Directory.systemTemp.createTemp('cogniread_src_');
    addTearDown(() => sourceDir.delete(recursive: true));
    final sourcePath = p.join(sourceDir.path, 'note.txt');
    await File(sourcePath).writeAsString('nope');

    await expectLater(
      () => service.copyToAppStorageWithHash(sourcePath),
      throwsA(isA<FormatException>()),
    );
  });
}
