import 'package:cogniread/src/features/sync/file_sync/yandex_disk_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_sync_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeYandexDiskApiClient implements YandexDiskApiClient {
  final Map<String, _FakeFile> _files = <String, _FakeFile>{};

  @override
  Future<List<YandexDiskApiFile>> listFolder(String path) async {
    return _files.values
        .where((file) => file.path.startsWith(path))
        .map(
          (file) => YandexDiskApiFile(
            path: file.path,
            name: file.name,
            modifiedTime: file.modifiedTime,
            size: file.bytes.length,
          ),
        )
        .toList();
  }

  @override
  Future<YandexDiskApiFile?> getMetadata(String path) async {
    final file = _files[path];
    if (file == null) {
      return null;
    }
    return YandexDiskApiFile(
      path: file.path,
      name: file.name,
      modifiedTime: file.modifiedTime,
      size: file.bytes.length,
    );
  }

  @override
  Future<List<int>> download(String path) async {
    final file = _files[path];
    if (file == null) {
      return <int>[];
    }
    return List<int>.from(file.bytes);
  }

  @override
  Future<void> upload({
    required String path,
    required List<int> bytes,
    bool overwrite = true,
  }) async {
    final name = path.split('/').last;
    _files[path] = _FakeFile(
      path: path,
      name: name,
      bytes: List<int>.from(bytes),
      modifiedTime: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
  }
}

class _FakeFile {
  _FakeFile({
    required this.path,
    required this.name,
    required this.bytes,
    required this.modifiedTime,
  });

  final String path;
  final String name;
  final List<int> bytes;
  final DateTime modifiedTime;
}

void main() {
  test('YandexDiskSyncAdapter uploads and downloads files', () async {
    final apiClient = _FakeYandexDiskApiClient();
    final adapter = YandexDiskSyncAdapter(apiClient: apiClient);

    await adapter.putFile('event_log.json', <int>[3, 2, 1]);
    await adapter.putFile('event_log.json', <int>[5, 4]);

    final file = await adapter.getFile('event_log.json');

    expect(file, isNotNull);
    expect(file!.bytes, [5, 4]);
  });
}
