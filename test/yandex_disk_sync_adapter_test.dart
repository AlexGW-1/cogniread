import 'package:cogniread/src/features/sync/file_sync/yandex_disk_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_sync_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeYandexDiskApiClient implements YandexDiskApiClient {
  _FakeYandexDiskApiClient({this.throwMetadata404 = false});

  final Map<String, _FakeFile> _files = <String, _FakeFile>{};
  final Set<String> _folders = <String>{'app:/'};
  final bool throwMetadata404;

  @override
  Future<List<YandexDiskApiFile>> listFolder(String path) async {
    if (!_folders.contains(_normalizeFolder(path))) {
      throw SyncAdapterException('Not found', code: 'yandex_404');
    }
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
      if (throwMetadata404) {
        throw SyncAdapterException('Not found', code: 'yandex_404');
      }
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
  Future<void> createFolder(String path) async {
    final normalized = _normalizeFolder(path);
    if (_folders.contains(normalized)) {
      throw SyncAdapterException(
        'Yandex Disk API error 409: DiskPathPointsToExistentDirectoryError',
        code: 'yandex_409',
      );
    }
    _folders.add(normalized);
  }

  @override
  Future<void> upload({
    required String path,
    required List<int> bytes,
    bool overwrite = true,
  }) async {
    final parent = _parent(path);
    if (parent != null && !_folders.contains(_normalizeFolder(parent))) {
      throw SyncAdapterException('Missing parent folder', code: 'yandex_409');
    }
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

  String? _parent(String path) {
    final index = path.lastIndexOf('/');
    if (index <= 0) {
      return null;
    }
    return path.substring(0, index);
  }

  String _normalizeFolder(String path) {
    final normalized = path.endsWith('/') ? path : '$path/';
    if (normalized.startsWith('app:/')) {
      return normalized;
    }
    if (normalized == 'app:') {
      return 'app:/';
    }
    return normalized;
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
    await adapter.putFile('books/abc.epub', <int>[9, 9, 9]);
    await adapter.putFile('books/xyz.epub', <int>[1, 2, 3]);

    final file = await adapter.getFile('event_log.json');

    expect(file, isNotNull);
    expect(file!.bytes, [5, 4]);
  });

  test('YandexDiskSyncAdapter treats 404 metadata as missing file', () async {
    final apiClient = _FakeYandexDiskApiClient(throwMetadata404: true);
    final adapter = YandexDiskSyncAdapter(apiClient: apiClient);

    final file = await adapter.getFile('event_log.json');

    expect(file, isNull);
  });
}
