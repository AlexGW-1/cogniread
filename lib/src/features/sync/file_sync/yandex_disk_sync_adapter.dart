import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_api_client.dart';

class YandexDiskSyncAdapter implements SyncAdapter {
  YandexDiskSyncAdapter({
    required YandexDiskApiClient apiClient,
    String basePath = 'app:/cogniread',
  })  : _apiClient = apiClient,
        _basePath = basePath;

  final YandexDiskApiClient _apiClient;
  final String _basePath;

  @override
  Future<List<SyncFileRef>> listFiles() async {
    final files = await _apiClient.listFolder(_basePath);
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
      overwrite: true,
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    await _apiClient.delete(_fullPath(path));
  }

  String _fullPath(String name) {
    final normalized = name.startsWith('/') ? name.substring(1) : name;
    if (_basePath.isEmpty) {
      return normalized;
    }
    final base = _basePath.endsWith('/') ? _basePath : '$_basePath/';
    return '$base$normalized';
  }

  String _stripBase(String path) {
    if (_basePath.isEmpty) {
      return path;
    }
    final base = _basePath.endsWith('/') ? _basePath : '$_basePath/';
    if (path.startsWith(base)) {
      return path.substring(base.length);
    }
    return path;
  }
}
