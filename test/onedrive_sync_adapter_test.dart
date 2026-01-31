import 'package:cogniread/src/features/sync/file_sync/onedrive_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/onedrive_sync_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOneDriveApiClient implements OneDriveApiClient {
  final Map<String, _FakeFile> _files = <String, _FakeFile>{};

  @override
  Future<List<OneDriveApiFile>> listChildren(String path) async {
    return _files.values
        .where((file) => file.path.startsWith(path))
        .map(
          (file) => OneDriveApiFile(
            id: file.id,
            name: file.name,
            path: file.path,
            modifiedTime: file.modifiedTime,
            size: file.bytes.length,
          ),
        )
        .toList();
  }

  @override
  Future<OneDriveApiFile?> getMetadata(String path) async {
    final file = _files[path];
    if (file == null) {
      return null;
    }
    return OneDriveApiFile(
      id: file.id,
      name: file.name,
      path: file.path,
      modifiedTime: file.modifiedTime,
      size: file.bytes.length,
    );
  }

  @override
  Future<void> createFolder(String path) async {
    final name = path.split('/').last;
    _files[path] = _FakeFile(
      id: 'id-$name',
      name: name,
      path: path,
      bytes: const <int>[],
      modifiedTime: DateTime.now().toUtc(),
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
  Future<OneDriveApiFile> upload({
    required String path,
    required List<int> bytes,
    String? contentType,
  }) async {
    final name = path.split('/').last;
    final file = _FakeFile(
      id: 'id-$name',
      name: name,
      path: path,
      bytes: List<int>.from(bytes),
      modifiedTime: DateTime.now().toUtc(),
    );
    _files[path] = file;
    return OneDriveApiFile(
      id: file.id,
      name: file.name,
      path: file.path,
      modifiedTime: file.modifiedTime,
      size: file.bytes.length,
    );
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
  }
}

class _FakeFile {
  _FakeFile({
    required this.id,
    required this.name,
    required this.path,
    required this.bytes,
    required this.modifiedTime,
  });

  final String id;
  final String name;
  final String path;
  final List<int> bytes;
  final DateTime modifiedTime;
}

void main() {
  test('OneDriveSyncAdapter uploads and downloads files', () async {
    final apiClient = _FakeOneDriveApiClient();
    final adapter = OneDriveSyncAdapter(apiClient: apiClient);

    await adapter.putFile('meta.json', <int>[1, 2, 3]);
    await adapter.putFile('meta.json', <int>[7, 8]);

    final file = await adapter.getFile('meta.json');

    expect(file, isNotNull);
    expect(file!.bytes, [7, 8]);
  });
}
