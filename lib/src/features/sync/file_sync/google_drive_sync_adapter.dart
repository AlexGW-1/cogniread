import 'package:cogniread/src/features/sync/file_sync/google_drive_api_client.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';

class GoogleDriveSyncAdapter implements SyncAdapter {
  GoogleDriveSyncAdapter({required GoogleDriveApiClient apiClient})
      : _apiClient = apiClient;

  final GoogleDriveApiClient _apiClient;
  final Map<String, String> _fileIdCache = <String, String>{};

  @override
  Future<List<SyncFileRef>> listFiles() async {
    final files = await _apiClient.listFiles();
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
    final file = await _getByName(path);
    if (file == null) {
      return null;
    }
    final bytes = await _apiClient.downloadFile(file.id);
    return SyncFile(
      ref: SyncFileRef(
        path: file.name,
        updatedAt: file.modifiedTime,
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
    final existing = await _getByName(path);
    if (existing == null) {
      final created = await _apiClient.createFile(
        name: path,
        bytes: bytes,
        contentType: contentType,
      );
      _fileIdCache[path] = created.id;
      return;
    }
    final updated = await _apiClient.updateFile(
      fileId: existing.id,
      bytes: bytes,
      contentType: contentType,
    );
    _fileIdCache[path] = updated.id;
  }

  @override
  Future<void> deleteFile(String path) async {
    final existing = await _getByName(path);
    if (existing == null) {
      return;
    }
    await _apiClient.deleteFile(existing.id);
    _fileIdCache.remove(path);
  }

  Future<GoogleDriveApiFile?> _getByName(String name) async {
    final cachedId = _fileIdCache[name];
    if (cachedId != null && cachedId.isNotEmpty) {
      final files = await _apiClient.listFiles(
        query: "name='${_escapeQueryValue(name)}' and trashed=false",
      );
      final match = files.where((file) => file.id == cachedId).toList();
      if (match.isNotEmpty) {
        return match.first;
      }
    }
    final fetched = await _apiClient.getFileByName(name);
    if (fetched != null) {
      _fileIdCache[name] = fetched.id;
    }
    return fetched;
  }

  String _escapeQueryValue(String value) {
    return value.replaceAll("'", "\\'");
  }
}
