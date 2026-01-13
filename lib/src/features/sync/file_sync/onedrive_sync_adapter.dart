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

  @override
  Future<List<SyncFileRef>> listFiles() async {
    final files = await _apiClient.listChildren(_basePath);
    return files
        .map(
          (file) => SyncFileRef(
            path: file.name,
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
      contentType: contentType,
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    await _apiClient.delete(_fullPath(path));
  }

  String _fullPath(String name) {
    if (_basePath.isEmpty) {
      return name;
    }
    final normalized = name.startsWith('/') ? name.substring(1) : name;
    return '$_basePath/$normalized';
  }
}
