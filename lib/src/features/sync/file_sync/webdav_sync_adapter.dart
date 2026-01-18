import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_api_client.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:path/path.dart' as p;

class WebDavSyncAdapter implements SyncAdapter {
  WebDavSyncAdapter({
    required WebDavApiClient apiClient,
    String basePath = '/cogniread/',
    String? legacyBasePath,
  }) : _apiClient = apiClient,
       _basePath = basePath,
       _legacyBasePath =
           legacyBasePath ??
           (basePath == '/cogniread/' || basePath == '/cogniread'
               ? null
               : '/cogniread/');

  final WebDavApiClient _apiClient;
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
    final primary = await _getFileAtBase(path, basePath: _basePath);
    if (primary != null) {
      return primary;
    }
    final legacy = _legacyBasePath;
    if (legacy != null && legacy.isNotEmpty && legacy != _basePath) {
      return _getFileAtBase(path, basePath: legacy);
    }
    return null;
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
    final legacy = _legacyBasePath;
    if (legacy != null && legacy.isNotEmpty && legacy != _basePath) {
      try {
        await _apiClient.delete(_fullPath(path, basePath: legacy));
      } on SyncAdapterException catch (error) {
        // Legacy cleanup is best-effort: ignore errors for old paths.
        Log.d('WebDAV legacy delete skipped: $error');
        return;
      }
    }
  }

  String _fullPath(String name, {String? basePath}) {
    final effectiveBasePath = basePath ?? _basePath;
    final normalized = name.startsWith('/') ? name.substring(1) : name;
    if (effectiveBasePath.isEmpty) {
      return '/$normalized';
    }
    final base = effectiveBasePath.endsWith('/')
        ? effectiveBasePath
        : '$effectiveBasePath/';
    return '$base$normalized';
  }

  String _stripBase(String path, {String? basePath}) {
    final effectiveBasePath = basePath ?? _basePath;
    if (effectiveBasePath.isEmpty) {
      return path;
    }
    final base = effectiveBasePath.endsWith('/')
        ? effectiveBasePath
        : '$effectiveBasePath/';
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

  Future<List<SyncFileRef>> _listFilesAtBase(
    String basePath, {
    required bool allowCreate,
  }) async {
    Log.d('WebDAV listFiles: basePath=$basePath');
    List<WebDavItem> items;
    try {
      items = await _apiClient.listFolder(basePath);
    } on SyncAdapterException catch (error) {
      if (allowCreate &&
          (error.code == 'webdav_404' || error.code == 'webdav_405')) {
        await _ensureBaseFolder();
        items = await _apiClient.listFolder(basePath);
      } else if (!allowCreate &&
          (error.code == 'webdav_404' || error.code == 'webdav_405')) {
        return const <SyncFileRef>[];
      } else {
        rethrow;
      }
    }
    final files = items.where((item) => !item.isDirectory).toList();
    Log.d('WebDAV listFiles: ${files.length} items');
    return files
        .map(
          (item) => SyncFileRef(
            path: _stripBase(item.path, basePath: basePath),
            updatedAt: item.modifiedTime,
            size: item.size,
          ),
        )
        .toList();
  }

  Future<SyncFile?> _getFileAtBase(
    String path, {
    required String basePath,
  }) async {
    final fullPath = _fullPath(path, basePath: basePath);
    Log.d('WebDAV getFile: $fullPath');
    List<int>? bytes;
    try {
      bytes = await _apiClient.download(fullPath, allowNotFound: true);
    } on SyncAdapterException catch (error) {
      if (error.code == 'webdav_404' || error.code == 'webdav_405') {
        return null;
      }
      rethrow;
    }
    if (bytes == null) {
      Log.d('WebDAV missing file: $fullPath');
      return null;
    }
    Log.d('WebDAV getFile: $fullPath (${bytes.length} bytes)');
    return SyncFile(
      ref: SyncFileRef(path: path, updatedAt: null, size: bytes.length),
      bytes: bytes,
    );
  }
}
