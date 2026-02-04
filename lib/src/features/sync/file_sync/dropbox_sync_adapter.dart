import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/sync/file_sync/dropbox_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';

class DropboxSyncAdapter implements SyncAdapter {
  DropboxSyncAdapter({
    required DropboxApiClient apiClient,
    String basePath = '',
    String? legacyBasePath,
  }) : _apiClient = apiClient,
       _basePath = basePath,
       _legacyBasePath =
           legacyBasePath ?? (basePath.isEmpty ? '/cogniread' : null);

  final DropboxApiClient _apiClient;
  final String _basePath;
  final String? _legacyBasePath;

  @override
  Future<List<SyncFileRef>> listFiles() async {
    final all = <SyncFileRef>[];
    all.addAll(await _listFilesAtBase(_basePath, allowCreate: true));
    final legacy = _legacyBasePath;
    if (legacy != null && legacy.isNotEmpty && legacy != _basePath) {
      all.addAll(await _listFilesAtBase(legacy, allowCreate: false));
    }
    final merged = <String, SyncFileRef>{};
    for (final ref in all) {
      final existing = merged[ref.path];
      if (existing == null ||
          (ref.updatedAt != null &&
              (existing.updatedAt == null ||
                  ref.updatedAt!.isAfter(existing.updatedAt!)))) {
        merged[ref.path] = ref;
      }
    }
    return merged.values.toList();
  }

  @override
  Future<SyncFile?> getFile(String path) async {
    final primary = await _getFileAtBase(
      path,
      basePath: _basePath,
      allowCreate: true,
    );
    if (primary != null) {
      return primary;
    }
    final legacy = _legacyBasePath;
    if (legacy != null && legacy.isNotEmpty && legacy != _basePath) {
      return _getFileAtBase(path, basePath: legacy, allowCreate: false);
    }
    return null;
  }

  @override
  Future<void> putFile(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    final fullPath = _fullPath(path, basePath: _basePath);
    await _ensureFolderForPath(fullPath);
    _log('putFile: $path -> $fullPath bytes=${bytes.length}');
    await _ensureBaseFolder();
    try {
      await _apiClient.upload(path: fullPath, bytes: bytes, overwrite: true);
    } on SyncAdapterException catch (error) {
      _log('putFile error: ${error.code} ${error.message}');
      if (_isPathNotFound(error)) {
        await _ensureBaseFolder();
        await _apiClient.upload(path: fullPath, bytes: bytes, overwrite: true);
        return;
      }
      if (_isFolderConflict(error)) {
        // На пути файла лежит папка — удаляем её и пробуем снова.
        await _deletePath(fullPath);
        await _apiClient.upload(path: fullPath, bytes: bytes, overwrite: true);
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    final fullPath = _fullPath(path, basePath: _basePath);
    _log('deleteFile: $path -> $fullPath');
    await _ensureBaseFolder();
    await _withBaseRetry<void>(
      () => _apiClient.delete(fullPath),
      swallowNotFound: true,
      swallowFolderConflict: true,
    );
    final legacy = _legacyBasePath;
    if (legacy != null && legacy.isNotEmpty && legacy != _basePath) {
      final legacyFullPath = _fullPath(path, basePath: legacy);
      await _withBaseRetry<void>(
        () => _apiClient.delete(legacyFullPath),
        swallowNotFound: true,
        swallowFolderConflict: true,
      );
    }
  }

  Future<void> _ensureBaseFolder() async {
    if (_basePath.isEmpty) {
      return;
    }
    _log('ensureBaseFolder: $_basePath');
    await _ensureFolders(_basePath);
  }

  Future<void> _ensureFolderForPath(String fullPath) async {
    final dir = _dirName(fullPath);
    if (dir.isEmpty || dir == '/') {
      return;
    }
    await _ensureFolders(dir);
  }

  Future<T> _withBaseRetry<T>(
    Future<T> Function() action, {
    bool swallowNotFound = false,
    bool swallowFolderConflict = false,
    T? notFoundValue,
  }) async {
    try {
      return await action();
    } on SyncAdapterException catch (error) {
      if (_isPathNotFound(error)) {
        await _ensureBaseFolder();
        if (swallowNotFound) {
          return notFoundValue as T;
        }
        return await action();
      }
      if (_isFolderConflict(error)) {
        if (swallowFolderConflict || swallowNotFound) {
          return notFoundValue as T;
        }
        rethrow;
      }
      rethrow;
    }
  }

  bool _isPathNotFound(SyncAdapterException error) {
    final code = error.code ?? '';
    final message = error.message;
    const markers = <String>['path/not_found', 'path_lookup/not_found'];
    bool containsMarker(String value) => markers.any(value.contains);
    return code.contains('path_not_found') ||
        (code.startsWith('dropbox_409') && containsMarker(message)) ||
        containsMarker(error.toString());
  }

  bool _isFolderConflict(SyncAdapterException error) {
    final message = error.message;
    final code = error.code ?? '';
    return (code.startsWith('dropbox_409') || code.contains('path_conflict')) &&
        (message.contains('path/conflict') ||
            message.contains('path/not_folder') ||
            error.toString().contains('path/conflict'));
  }

  Future<void> _repairBaseFolder() async {
    _log('repairBaseFolder: $_basePath');
    await _deletePath(_basePath);
    await _ensureBaseFolder();
  }

  Future<void> _deletePath(String path) async {
    _log('deletePath: $path');
    try {
      await _apiClient.delete(path);
    } on SyncAdapterException catch (error) {
      _log('deletePath error: ${error.code} ${error.message}');
      if (_isPathNotFound(error) || _isFolderConflict(error)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _ensureFolders(String absolutePath) async {
    final segments = absolutePath
        .split('/')
        .where((segment) => segment.isNotEmpty);
    var current = '';
    for (final segment in segments) {
      current = '$current/$segment';
      _log('ensureFolders: creating $current');
      await _ensureSingleFolder(current);
    }
  }

  Future<void> _ensureSingleFolder(String path) async {
    try {
      await _apiClient.createFolder(path);
      return;
    } on SyncAdapterException catch (error) {
      _log(
        'ensureSingleFolder error for $path: ${error.code} ${error.message}',
      );
      if (_isFolderConflict(error) ||
          _isNotFolder(error) ||
          _isPathNotFound(error)) {
        _log('ensureSingleFolder: deleting/retrying $path');
        await _deletePath(path);
        // Retry once after delete; if it fails again, let it bubble up.
        await _apiClient.createFolder(path);
        return;
      }
      if (_isPathNotFound(error)) {
        // parent missing: continue; loop will recreate parents as we progress.
        return;
      }
      rethrow;
    }
  }

  bool _isNotFolder(SyncAdapterException error) {
    final message = error.message;
    return message.contains('path/not_folder') ||
        error.toString().contains('path/not_folder');
  }

  String _fullPath(String name, {required String basePath}) {
    final normalized = name.startsWith('/') ? name : '/$name';
    if (basePath.isEmpty || basePath == '/') {
      return normalized;
    }
    final base = basePath.startsWith('/') ? basePath : '/$basePath';
    return '$base$normalized';
  }

  String _stripBaseAt(String path, {required String basePath}) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    if (basePath.isEmpty) {
      return normalized;
    }
    final base = basePath.startsWith('/') ? basePath.substring(1) : basePath;
    final prefix = base.endsWith('/') ? base : '$base/';
    if (normalized.startsWith(prefix)) {
      return normalized.substring(prefix.length);
    }
    return normalized;
  }

  String _dirName(String fullPath) {
    final index = fullPath.lastIndexOf('/');
    if (index <= 0) {
      return '';
    }
    return fullPath.substring(0, index);
  }

  void _log(String message) {
    Log.d('[DropboxSyncAdapter] $message');
  }

  Future<List<SyncFileRef>> _listFilesAtBase(
    String basePath, {
    required bool allowCreate,
  }) async {
    if (basePath.isNotEmpty && allowCreate) {
      _log('listFiles: ensuring base folder $basePath');
      await _ensureBaseFolder();
    }

    if (basePath.isNotEmpty && !allowCreate) {
      try {
        final exists = await _apiClient.getMetadata(basePath);
        if (exists == null) {
          return const <SyncFileRef>[];
        }
      } on SyncAdapterException catch (error) {
        if (_isPathNotFound(error)) {
          return const <SyncFileRef>[];
        }
        rethrow;
      }
    }

    List<DropboxApiFile> files;
    try {
      _log('listFiles: requesting list for $basePath');
      files = await _apiClient.listFolder(basePath);
    } on SyncAdapterException catch (error) {
      _log('listFiles error: ${error.code} ${error.message}');
      if (allowCreate && _isPathNotFound(error)) {
        await _ensureBaseFolder();
        _log('listFiles retry after create');
        files = await _apiClient.listFolder(basePath);
      } else if (allowCreate && _isFolderConflict(error)) {
        _log('listFiles repair base folder');
        await _repairBaseFolder();
        files = await _apiClient.listFolder(basePath);
      } else if (!allowCreate && _isPathNotFound(error)) {
        return const <SyncFileRef>[];
      } else {
        rethrow;
      }
    }

    return files
        .map(
          (file) => SyncFileRef(
            path: _stripBaseAt(file.path, basePath: basePath),
            updatedAt: file.modifiedTime,
            size: file.size,
          ),
        )
        .toList();
  }

  Future<SyncFile?> _getFileAtBase(
    String path, {
    required String basePath,
    required bool allowCreate,
  }) async {
    final fullPath = _fullPath(path, basePath: basePath);
    _log('getFile: $path -> $fullPath');
    DropboxApiFile? metadata;
    if (allowCreate) {
      await _ensureBaseFolder();
    }
    try {
      metadata = await _apiClient.getMetadata(fullPath);
    } on SyncAdapterException catch (error) {
      _log('getFile metadata error: ${error.code} ${error.message}');
      if (_isPathNotFound(error)) {
        if (allowCreate) {
          await _ensureBaseFolder();
        }
        return null;
      }
      if (_isFolderConflict(error)) {
        await _deletePath(fullPath);
        return null;
      }
      rethrow;
    }
    if (metadata == null) {
      _log('getFile: no metadata for $fullPath');
      return null;
    }
    List<int> bytes;
    try {
      _log('getFile: downloading $fullPath');
      bytes = await _apiClient.download(fullPath);
    } on SyncAdapterException catch (error) {
      _log('getFile download error: ${error.code} ${error.message}');
      if (_isPathNotFound(error)) {
        return null;
      }
      if (_isFolderConflict(error)) {
        await _deletePath(fullPath);
        return null;
      }
      rethrow;
    }
    return SyncFile(
      ref: SyncFileRef(
        path: path,
        updatedAt: metadata.modifiedTime,
        size: bytes.length,
      ),
      bytes: bytes,
    );
  }
}
