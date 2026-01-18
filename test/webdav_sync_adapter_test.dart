import 'package:cogniread/src/features/sync/file_sync/webdav_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWebDavApiClient implements WebDavApiClient {
  _FakeWebDavApiClient({
    this.missingFolderCode = 'webdav_404',
    this.legacyDeleteNotAllowed = false,
  });

  final Map<String, List<int>> _files = <String, List<int>>{};
  final Set<String> _folders = <String>{'/'};
  final String missingFolderCode;
  final bool legacyDeleteNotAllowed;

  @override
  Future<void> delete(String path) async {
    if (legacyDeleteNotAllowed && path.startsWith('/cogniread/')) {
      throw SyncAdapterException('Not allowed', code: 'webdav_405');
    }
    _files.remove(path);
  }

  @override
  Future<List<int>?> download(String path, {bool allowNotFound = false}) async {
    final bytes = _files[path];
    if (bytes == null) {
      if (allowNotFound) {
        return null;
      }
      throw SyncAdapterException('Not found', code: 'webdav_404');
    }
    return bytes;
  }

  @override
  Future<List<WebDavItem>> listFolder(String path) async {
    final folder = _normalizeFolderPath(path);
    if (!_folders.contains(folder)) {
      throw SyncAdapterException('Not found', code: missingFolderCode);
    }
    final prefix = folder == '/' ? '/' : '$folder/';
    return _files.entries
        .where((entry) => entry.key.startsWith(prefix))
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
  Future<WebDavOptionsResult> options(String path) async {
    return const WebDavOptionsResult(
      hasDav: true,
      allowsPropfind: true,
      allowsMkcol: true,
    );
  }

  @override
  Future<void> createFolder(String path) async {
    _folders.add(_normalizeFolderPath(path));
  }

  @override
  Future<void> upload({
    required String path,
    required List<int> bytes,
    String? contentType,
  }) async {
    _files[path] = List<int>.from(bytes);
  }

  String _normalizeFolderPath(String path) {
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final rooted = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return rooted.isEmpty ? '/' : rooted;
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

  test('WebDavSyncAdapter creates base folder on 405', () async {
    final apiClient = _FakeWebDavApiClient(missingFolderCode: 'webdav_405');
    final adapter = WebDavSyncAdapter(apiClient: apiClient);

    final files = await adapter.listFiles();

    expect(files, isEmpty);
  });

  test('WebDavSyncAdapter falls back to legacy basePath', () async {
    final apiClient = _FakeWebDavApiClient();
    // Pretend old builds used /cogniread/ while current uses /home/cogniread/.
    await apiClient.upload(
      path: '/cogniread/event_log.json',
      bytes: <int>[9],
      contentType: 'application/json',
    );
    final adapter = WebDavSyncAdapter(
      apiClient: apiClient,
      basePath: '/home/cogniread/',
    );

    final file = await adapter.getFile('event_log.json');

    expect(file, isNotNull);
    expect(file!.bytes, [9]);
  });

  test('WebDavSyncAdapter ignores legacy delete 405', () async {
    final apiClient = _FakeWebDavApiClient(legacyDeleteNotAllowed: true);
    await apiClient.upload(
      path: '/home/cogniread/event_log.json',
      bytes: <int>[1],
      contentType: 'application/json',
    );
    final adapter = WebDavSyncAdapter(
      apiClient: apiClient,
      basePath: '/home/cogniread/',
    );

    await adapter.deleteFile('event_log.json');
  });
}
