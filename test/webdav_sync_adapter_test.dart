import 'package:cogniread/src/features/sync/file_sync/webdav_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_sync_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWebDavApiClient implements WebDavApiClient {
  final Map<String, List<int>> _files = <String, List<int>>{};

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
  }

  @override
  Future<List<int>> download(String path) async {
    return _files[path] ?? <int>[];
  }

  @override
  Future<List<WebDavItem>> listFolder(String path) async {
    return _files.entries
        .where((entry) => entry.key.startsWith(path))
        .map(
          (entry) => WebDavItem(
            path: entry.key,
            name: entry.key.split('/').last,
            isDirectory: false,
            modifiedTime: DateTime.now().toUtc(),
            size: entry.value.length,
          ),
        )
        .toList();
  }

  @override
  Future<void> upload({
    required String path,
    required List<int> bytes,
    String? contentType,
  }) async {
    _files[path] = List<int>.from(bytes);
  }
}

void main() {
  test('WebDavSyncAdapter uploads and downloads files', () async {
    final apiClient = _FakeWebDavApiClient();
    final adapter = WebDavSyncAdapter(apiClient: apiClient);

    await adapter.putFile('event_log.json', <int>[1, 1, 1]);
    await adapter.putFile('event_log.json', <int>[2, 2]);

    final file = await adapter.getFile('event_log.json');

    expect(file, isNotNull);
    expect(file!.bytes, [2, 2]);
  });
}
