import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_api_client.dart';

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
    final items = await _apiClient.listFolder(_basePath);
    return items
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
    final bytes = await _apiClient.download(fullPath);
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
    await _apiClient.upload(
      path: _fullPath(path),
      bytes: bytes,
      contentType: contentType,
    );
  }

  @override
  Future<void> deleteFile(String path) async {
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
}
