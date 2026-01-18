import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_api_client.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:path/path.dart' as p;

class WebDavSyncAdapter implements SyncAdapter {
  WebDavSyncAdapter({
    required WebDavApiClient apiClient,
    String basePath = '/cogniread/',
  })  : _apiClient = apiClient,
        _basePath = basePath;

  final WebDavApiClient _apiClient;
  final String _basePath;

  @override
  Future<List<SyncFileRef>> listFiles() async {
    Log.d('WebDAV listFiles: basePath=$_basePath');
    List<WebDavItem> items;
    try {
      items = await _apiClient.listFolder(_basePath);
    } on SyncAdapterException catch (error) {
      if (error.code == 'webdav_404' || error.code == 'webdav_405') {
        await _ensureBaseFolder();
        items = await _apiClient.listFolder(_basePath);
      } else {
        rethrow;
      }
    }
    final files = items.where((item) => !item.isDirectory).toList();
    Log.d('WebDAV listFiles: ${files.length} items');
    return files
        .map(
          (item) => SyncFileRef(
            path: _stripBase(item.path),
            updatedAt: item.modifiedTime,
            size: item.size,
          ),
        )
        .toList();
  }

  @override
  Future<SyncFile?> getFile(String path) async {
    final fullPath = _fullPath(path);
    Log.d('WebDAV getFile: $fullPath');
    final bytes = await _apiClient.download(
      fullPath,
      allowNotFound: true,
    );
    if (bytes == null) {
      Log.d('WebDAV missing file: $fullPath');
      return null;
    }
    Log.d('WebDAV getFile: $fullPath (${bytes.length} bytes)');
    return SyncFile(
      ref: SyncFileRef(
        path: path,
        updatedAt: null,
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
    Log.d('WebDAV putFile: ${_fullPath(path)} (${bytes.length} bytes)');
    await _ensureFolders(path);
    await _apiClient.upload(
      path: _fullPath(path),
      bytes: bytes,
      contentType: contentType,
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    Log.d('WebDAV deleteFile: ${_fullPath(path)}');
    await _apiClient.delete(_fullPath(path));
  }

  String _fullPath(String name) {
    final normalized = name.startsWith('/') ? name.substring(1) : name;
    if (_basePath.isEmpty) {
      return '/$normalized';
    }
    final base =
        _basePath.endsWith('/') ? _basePath : '$_basePath/';
    return '$base$normalized';
  }

  String _stripBase(String path) {
    if (_basePath.isEmpty) {
      return path;
    }
    final base =
        _basePath.endsWith('/') ? _basePath : '$_basePath/';
    if (path.startsWith(base)) {
      return path.substring(base.length);
    }
    return path;
  }

  Future<void> _ensureBaseFolder() async {
    if (_basePath.isEmpty) {
      return;
    }
    final base = _basePath.endsWith('/') ? _basePath : '$_basePath/';
    final trimmed = base.startsWith('/') ? base.substring(1) : base;
    final parts = trimmed.split('/').where((part) => part.isNotEmpty);
    var current = '';
    for (final part in parts) {
      current = '$current/$part';
      await _apiClient.createFolder(current);
    }
  }

  Future<void> _ensureFolders(String path) async {
    final fullPath = _fullPath(path);
    final normalized = p.posix.normalize(fullPath);
    final parent = p.posix.dirname(normalized);
    if (parent.isEmpty || parent == '.' || parent == '/') {
      return;
    }
    final trimmed = parent.startsWith('/') ? parent.substring(1) : parent;
    final parts = trimmed.split('/').where((part) => part.isNotEmpty);
    var current = '';
    for (final part in parts) {
      current = '$current/$part';
      await _apiClient.createFolder(current);
    }
  }
}
