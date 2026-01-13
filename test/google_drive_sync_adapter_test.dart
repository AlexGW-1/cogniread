import 'package:cogniread/src/features/sync/file_sync/google_drive_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/google_drive_sync_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGoogleDriveApiClient implements GoogleDriveApiClient {
  final Map<String, _FakeFile> _filesById = <String, _FakeFile>{};
  int _counter = 0;

  @override
  Future<List<GoogleDriveApiFile>> listFiles({
    String? query,
    String spaces = 'appDataFolder',
  }) async {
    return _filesById.values
        .map(
          (file) => GoogleDriveApiFile(
            id: file.id,
            name: file.name,
            modifiedTime: file.modifiedTime,
            size: file.bytes.length,
          ),
        )
        .toList();
  }

  @override
  Future<GoogleDriveApiFile?> getFileByName(
    String name, {
    String spaces = 'appDataFolder',
  }) async {
    final match = _filesById.values
        .where((file) => file.name == name)
        .toList(growable: false);
    if (match.isEmpty) {
      return null;
    }
    final file = match.first;
    return GoogleDriveApiFile(
      id: file.id,
      name: file.name,
      modifiedTime: file.modifiedTime,
      size: file.bytes.length,
    );
  }

  @override
  Future<List<int>> downloadFile(String fileId) async {
    final file = _filesById[fileId];
    if (file == null) {
      return <int>[];
    }
    return List<int>.from(file.bytes);
  }

  @override
  Future<GoogleDriveApiFile> createFile({
    required String name,
    required List<int> bytes,
    String parent = 'appDataFolder',
    String? contentType,
  }) async {
    final id = 'file-${++_counter}';
    final file = _FakeFile(
      id: id,
      name: name,
      bytes: List<int>.from(bytes),
      modifiedTime: DateTime.now().toUtc(),
    );
    _filesById[id] = file;
    return GoogleDriveApiFile(
      id: id,
      name: name,
      modifiedTime: file.modifiedTime,
      size: bytes.length,
    );
  }

  @override
  Future<GoogleDriveApiFile> updateFile({
    required String fileId,
    required List<int> bytes,
    String? contentType,
  }) async {
    final existing = _filesById[fileId];
    if (existing != null) {
      existing
        ..bytes = List<int>.from(bytes)
        ..modifiedTime = DateTime.now().toUtc();
    }
    return GoogleDriveApiFile(
      id: fileId,
      name: existing?.name ?? 'unknown',
      modifiedTime: existing?.modifiedTime,
      size: bytes.length,
    );
  }

  @override
  Future<void> deleteFile(String fileId) async {
    _filesById.remove(fileId);
  }
}

class _FakeFile {
  _FakeFile({
    required this.id,
    required this.name,
    required this.bytes,
    required this.modifiedTime,
  });

  final String id;
  final String name;
  List<int> bytes;
  DateTime modifiedTime;
}

void main() {
  test('GoogleDriveSyncAdapter uploads and downloads files', () async {
    final apiClient = _FakeGoogleDriveApiClient();
    final adapter = GoogleDriveSyncAdapter(apiClient: apiClient);

    await adapter.putFile('event_log.json', <int>[1, 2, 3]);
    await adapter.putFile('event_log.json', <int>[4, 5]);

    final file = await adapter.getFile('event_log.json');

    expect(file, isNotNull);
    expect(file!.bytes, [4, 5]);
  });
}
