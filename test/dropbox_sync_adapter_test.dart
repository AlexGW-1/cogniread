import 'package:cogniread/src/features/sync/file_sync/dropbox_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/dropbox_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDropboxApiClient implements DropboxApiClient {
  final Map<String, _FakeFile> _files = <String, _FakeFile>{};

  @override
  Future<List<DropboxApiFile>> listFolder(String path) async {
    return _files.values
        .where((file) => file.path.startsWith(path))
        .map(
          (file) => DropboxApiFile(
            path: file.path,
            name: file.name,
            modifiedTime: file.modifiedTime,
            size: file.bytes.length,
          ),
        )
        .toList();
  }

  @override
  Future<DropboxApiFile?> getMetadata(String path) async {
    final file = _files[path];
    if (file == null) {
      return null;
    }
    return DropboxApiFile(
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
  Future<DropboxApiFile> upload({
    required String path,
    required List<int> bytes,
    bool overwrite = true,
  }) async {
    final name = path.split('/').last;
    final file = _FakeFile(
      path: path,
      name: name,
      bytes: List<int>.from(bytes),
      modifiedTime: DateTime.now().toUtc(),
    );
    _files[path] = file;
    return DropboxApiFile(
      path: file.path,
      name: file.name,
      modifiedTime: file.modifiedTime,
      size: file.bytes.length,
    );
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
  }

  @override
  Future<void> createFolder(String path) async {
    // No-op for the in-memory fake; folders are implied by the file paths.
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
  test('DropboxSyncAdapter uploads and downloads files', () async {
    final apiClient = _FakeDropboxApiClient();
    final adapter = DropboxSyncAdapter(apiClient: apiClient, basePath: '/cogniread');

    await adapter.putFile('state.json', <int>[1, 2, 3]);
    await adapter.putFile('state.json', <int>[9, 8]);

    final file = await adapter.getFile('state.json');

    expect(file, isNotNull);
    expect(file!.bytes, [9, 8]);
  });

  test('DropboxSyncAdapter создаёт базовую папку при path/not_found', () async {
    final apiClient = _FolderAwareDropboxApiClient();
    final adapter = DropboxSyncAdapter(apiClient: apiClient, basePath: '/testbase');

    await adapter.putFile('state.json', <int>[1, 2, 3]);
    final file = await adapter.getFile('state.json');

    expect(file, isNotNull);
    expect(file!.bytes, [1, 2, 3]);
  });

  test('DropboxSyncAdapter удаляет конфликтующую папку и перезаписывает файл', () async {
    final apiClient = _ConflictingDropboxApiClient(conflictPaths: <String>{
      '/testbase/state.json',
    });
    final adapter = DropboxSyncAdapter(apiClient: apiClient, basePath: '/testbase');

    await adapter.putFile('state.json', <int>[4, 5, 6]);
    final file = await adapter.getFile('state.json');

    expect(file, isNotNull);
    expect(file!.bytes, [4, 5, 6]);
  });

  test('DropboxSyncAdapter чинит базовую папку при конфликте', () async {
    final apiClient = _ConflictingDropboxApiClient(conflictPaths: <String>{
      '/testbase',
    });
    apiClient.baseIsConflict = true; // базовая папка "сломана" (конфликт).
    final adapter = DropboxSyncAdapter(apiClient: apiClient, basePath: '/testbase');

    final files = await adapter.listFiles();
    expect(files, isEmpty);
  });
}

class _FolderAwareDropboxApiClient implements DropboxApiClient {
  final Map<String, _FakeFile> _files = <String, _FakeFile>{};
  bool _folderExists = false;

  @override
  Future<List<DropboxApiFile>> listFolder(String path) async {
    _ensureFolderOrThrow();
    return _files.values
        .where((file) => file.path.startsWith(path))
        .map(
          (file) => DropboxApiFile(
            path: file.path,
            name: file.name,
            modifiedTime: file.modifiedTime,
            size: file.bytes.length,
          ),
        )
        .toList();
  }

  @override
  Future<DropboxApiFile?> getMetadata(String path) async {
    _ensureFolderOrThrow();
    final file = _files[path];
    if (file == null) {
      return null;
    }
    return DropboxApiFile(
      path: file.path,
      name: file.name,
      modifiedTime: file.modifiedTime,
      size: file.bytes.length,
    );
  }

  @override
  Future<List<int>> download(String path) async {
    _ensureFolderOrThrow();
    final file = _files[path];
    if (file == null) {
      return <int>[];
    }
    return List<int>.from(file.bytes);
  }

  @override
  Future<DropboxApiFile> upload({
    required String path,
    required List<int> bytes,
    bool overwrite = true,
  }) async {
    _ensureFolderOrThrow();
    final name = path.split('/').last;
    final file = _FakeFile(
      path: path,
      name: name,
      bytes: List<int>.from(bytes),
      modifiedTime: DateTime.now().toUtc(),
    );
    _files[path] = file;
    return DropboxApiFile(
      path: file.path,
      name: file.name,
      modifiedTime: file.modifiedTime,
      size: file.bytes.length,
    );
  }

  @override
  Future<void> delete(String path) async {
    _ensureFolderOrThrow();
    _files.remove(path);
  }

  @override
  Future<void> createFolder(String path) async {
    _folderExists = true;
  }

  void _ensureFolderOrThrow() {
    if (!_folderExists) {
      throw SyncAdapterException(
        'path/not_found',
        code: 'dropbox_409_path_not_found',
      );
    }
  }
}

class _ConflictingDropboxApiClient implements DropboxApiClient {
  _ConflictingDropboxApiClient({Set<String>? conflictPaths})
      : _conflictPaths = conflictPaths ?? <String>{} {
    _folders.add('/testbase'); // базовая папка существует логически.
  }

  final Map<String, _FakeFile> _files = <String, _FakeFile>{};
  final Set<String> _folders = <String>{};
  final Set<String> _conflictPaths;
  bool baseIsConflict = false;

  @override
  Future<List<DropboxApiFile>> listFolder(String path) async {
    _ensureFolder(path);
    if (_conflictPaths.contains(path) || (baseIsConflict && path == '/testbase')) {
      throw SyncAdapterException(
        'path/conflict/folder',
        code: 'dropbox_409',
      );
    }
    return _files.values
        .where((file) => file.path.startsWith(path))
        .map(
          (file) => DropboxApiFile(
            path: file.path,
            name: file.name,
            modifiedTime: file.modifiedTime,
            size: file.bytes.length,
          ),
        )
        .toList();
  }

  @override
  Future<DropboxApiFile?> getMetadata(String path) async {
    _ensureFolder(path);
    final file = _files[path];
    if (file == null) {
      return null;
    }
    return DropboxApiFile(
      path: file.path,
      name: file.name,
      modifiedTime: file.modifiedTime,
      size: file.bytes.length,
    );
  }

  @override
  Future<List<int>> download(String path) async {
    _ensureFolder(path);
    final file = _files[path];
    if (file == null) {
      return <int>[];
    }
    return List<int>.from(file.bytes);
  }

  @override
  Future<DropboxApiFile> upload({
    required String path,
    required List<int> bytes,
    bool overwrite = true,
  }) async {
    _ensureFolder(path);
    if (_conflictPaths.contains(path)) {
      throw SyncAdapterException(
        'path/conflict/folder',
        code: 'dropbox_409',
      );
    }
    final name = path.split('/').last;
    final file = _FakeFile(
      path: path,
      name: name,
      bytes: List<int>.from(bytes),
      modifiedTime: DateTime.now().toUtc(),
    );
    _files[path] = file;
    return DropboxApiFile(
      path: file.path,
      name: file.name,
      modifiedTime: file.modifiedTime,
      size: file.bytes.length,
    );
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
    _folders.remove(path);
    _conflictPaths.remove(path);
    if (path == '/testbase') {
      baseIsConflict = false;
    }
  }

  @override
  Future<void> createFolder(String path) async {
    _folders.add(path);
  }

  void _ensureFolder(String path) {
    // Проверяем только базовую папку /testbase для эмуляции дерева.
    if (!_folders.contains('/testbase')) {
      throw SyncAdapterException(
        'path/not_found',
        code: 'dropbox_409_path_not_found',
      );
    }
  }
}
