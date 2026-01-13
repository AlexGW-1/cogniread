import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/sync/file_sync/dropbox_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';

class DropboxSyncAdapter implements SyncAdapter {
  DropboxSyncAdapter({
    required DropboxApiClient apiClient,
    String basePath = '',
  })  : _apiClient = apiClient,
        _basePath = basePath;

  final DropboxApiClient _apiClient;
  final String _basePath;

  @override
  Future<List<SyncFileRef>> listFiles() async {
    _log('listFiles: ensuring base folder $_basePath');
    await _ensureBaseFolder();
    List<DropboxApiFile> files;
    try {
      _log('listFiles: requesting list for $_basePath');
      files = await _apiClient.listFolder(_basePath);
    } on SyncAdapterException catch (error) {
      _log('listFiles error: ${error.code} ${error.message}');
      if (_isPathNotFound(error)) {
        await _ensureBaseFolder();
        _log('listFiles retry after create');
        files = await _apiClient.listFolder(_basePath);
      } else if (_isFolderConflict(error)) {
        _log('listFiles repair base folder');
        await _repairBaseFolder();
        files = await _apiClient.listFolder(_basePath);
      } else {
        rethrow;
      }
    }
    return files
        .map(
          (file) => SyncFileRef(
            path: _stripBase(file.path),
            updatedAt: file.modifiedTime,
            size: file.size,
          ),
        )
        .toList();
  }

  @override
  Future<SyncFile?> getFile(String path) async {
    final fullPath = _fullPath(path);
    _log('getFile: $path -> $fullPath');
    DropboxApiFile? metadata;
    await _ensureBaseFolder();
    try {
      metadata = await _apiClient.getMetadata(fullPath);
    } on SyncAdapterException catch (error) {
      _log('getFile metadata error: ${error.code} ${error.message}');
      if (_isPathNotFound(error)) {
        await _ensureBaseFolder();
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
        path: _stripBase(metadata.path),
        updatedAt: metadata.modifiedTime,
        size: bytes.length,
      ),
      bytes: bytes,
    );
  }

  @override
  Future<void> putFile(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    final fullPath = _fullPath(path);
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
    final fullPath = _fullPath(path);
    _log('deleteFile: $path -> $fullPath');
    await _ensureBaseFolder();
    await _withBaseRetry<void>(
      () => _apiClient.delete(fullPath),
      swallowNotFound: true,
      swallowFolderConflict: true,
    );
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
    return code.contains('path_not_found') ||
        (code.startsWith('dropbox_409') && message.contains('path/not_found')) ||
        error.toString().contains('path/not_found');
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
    final segments = absolutePath.split('/').where((segment) => segment.isNotEmpty);
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
      _log('ensureSingleFolder error for $path: ${error.code} ${error.message}');
      if (_isFolderConflict(error) || _isNotFolder(error) || _isPathNotFound(error)) {
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
    return message.contains('path/not_folder') || error.toString().contains('path/not_folder');
  }

  String _fullPath(String name) {
    final normalized = name.startsWith('/') ? name : '/$name';
    if (_basePath.isEmpty || _basePath == '/') {
      return normalized;
    }
    final base = _basePath.startsWith('/') ? _basePath : '/$_basePath';
    return '$base$normalized';
  }

  String _stripBase(String path) {
    if (_basePath.isEmpty) {
      return path;
    }
    final base = _basePath.startsWith('/') ? _basePath : '/$_basePath';
    if (path.startsWith(base)) {
      final trimmed = path.substring(base.length);
      return trimmed.isEmpty ? '/' : trimmed;
    }
    return path;
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
}
