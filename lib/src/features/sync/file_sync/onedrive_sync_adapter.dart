import 'package:cogniread/src/features/sync/file_sync/onedrive_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';

class OneDriveSyncAdapter implements SyncAdapter {
  OneDriveSyncAdapter({
    required OneDriveApiClient apiClient,
    String basePath = 'cogniread',
  })  : _apiClient = apiClient,
        _basePath = basePath;

  final OneDriveApiClient _apiClient;
  final String _basePath;
  bool _baseFolderReady = false;

  @override
  Future<List<SyncFileRef>> listFiles() async {
    try {
      await _ensureBaseFolder();
      List<OneDriveApiFile> files;
      try {
        files = await _apiClient.listChildren(_basePath);
      } on SyncAdapterException catch (error) {
        if (!_isNotFound(error) || _basePath.trim().isEmpty) {
          rethrow;
        }
        _baseFolderReady = false;
        await _ensureBaseFolder();
        files = await _apiClient.listChildren(_basePath);
      }
      return files
          .map(
            (file) => SyncFileRef(
              path: file.name,
              updatedAt: file.modifiedTime,
              size: file.size,
            ),
          )
          .toList();
    } on SyncAdapterException catch (error) {
      if (_isNotFound(error)) {
        return const <SyncFileRef>[];
      }
      rethrow;
    }
  }

  @override
  Future<SyncFile?> getFile(String path) async {
    try {
      await _ensureBaseFolder();
      final fullPath = _fullPath(path);
      final metadata = await _apiClient.getMetadata(fullPath);
      if (metadata == null) {
        return null;
      }
      final bytes = await _apiClient.download(fullPath);
      return SyncFile(
        ref: SyncFileRef(
          path: path,
          updatedAt: metadata.modifiedTime,
          size: bytes.length,
        ),
        bytes: bytes,
      );
    } on SyncAdapterException catch (error) {
      if (_isNotFound(error)) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> putFile(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    try {
      await _ensureBaseFolder();
      await _apiClient.upload(
        path: _fullPath(path),
        bytes: bytes,
        contentType: contentType,
      );
    } on SyncAdapterException catch (error) {
      if (_isNotFound(error) && _basePath.trim().isNotEmpty) {
        _baseFolderReady = false;
        await _ensureBaseFolder();
        await _apiClient.upload(
          path: _fullPath(path),
          bytes: bytes,
          contentType: contentType,
        );
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    try {
      await _ensureBaseFolder();
      await _apiClient.delete(_fullPath(path));
    } on SyncAdapterException catch (error) {
      if (_isNotFound(error)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _ensureBaseFolder() async {
    if (_baseFolderReady) {
      return;
    }
    if (_basePath.trim().isEmpty) {
      _baseFolderReady = true;
      return;
    }
    final normalized = _basePath.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      _baseFolderReady = true;
      return;
    }
    var current = '';
    for (final segment in segments) {
      current = current.isEmpty ? segment : '$current/$segment';
      try {
        final metadata = await _apiClient.getMetadata(current);
        if (metadata == null) {
          await _safeCreateFolder(current);
        }
      } on SyncAdapterException catch (error) {
        if (!_isNotFound(error)) {
          rethrow;
        }
        await _safeCreateFolder(current);
      }
    }
    _baseFolderReady = true;
  }

  Future<void> _safeCreateFolder(String path) async {
    try {
      await _apiClient.createFolder(path);
    } on SyncAdapterException catch (error) {
      if (_isNotFound(error)) {
        return;
      }
      rethrow;
    }
  }

  bool _isNotFound(SyncAdapterException error) {
    final code = error.code ?? '';
    if (code.contains('404')) {
      return true;
    }
    return error.message.contains('404');
  }

  String _fullPath(String name) {
    if (_basePath.isEmpty) {
      return name;
    }
    final normalized = name.startsWith('/') ? name.substring(1) : name;
    return '$_basePath/$normalized';
  }
}
