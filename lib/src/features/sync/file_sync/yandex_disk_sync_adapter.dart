import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_api_client.dart';

class YandexDiskSyncAdapter implements SyncAdapter {
  YandexDiskSyncAdapter({
    required YandexDiskApiClient apiClient,
    String basePath = 'app:/',
    String? legacyBasePath,
  })  : _apiClient = apiClient,
        _basePath = basePath,
        _legacyBasePath = legacyBasePath ??
            ((basePath == 'app:/' || basePath == 'app:' || basePath.isEmpty)
                ? 'app:/cogniread'
                : null);

  final YandexDiskApiClient _apiClient;
  final String _basePath;
  final String? _legacyBasePath;
  final Set<String> _ensuredFolders = <String>{};

  @override
  Future<List<SyncFileRef>> listFiles() async {
    await _ensureBaseFolder();
    final all = <SyncFileRef>[];
    final primary = await _apiClient.listFolder(_basePath);
    all.addAll(_toRefs(primary, basePath: _basePath));
    final legacy = _legacyBasePath;
    if (legacy != null && legacy.isNotEmpty && legacy != _basePath) {
      try {
        final legacyFiles = await _apiClient.listFolder(legacy);
        all.addAll(_toRefs(legacyFiles, basePath: legacy));
      } on SyncAdapterException catch (error) {
        if (error.code != 'yandex_404') {
          rethrow;
        }
      }
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
    await _ensureFolders(path);
    await _apiClient.upload(
      path: _fullPath(path),
      bytes: bytes,
      overwrite: true,
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    await _apiClient.delete(_fullPath(path, basePath: _basePath));
    final legacy = _legacyBasePath;
    if (legacy != null && legacy.isNotEmpty && legacy != _basePath) {
      await _apiClient.delete(_fullPath(path, basePath: legacy));
    }
  }

  Future<void> _ensureBaseFolder() async {
    if (_basePath.isEmpty || _isRootCollection(_basePath)) {
      return;
    }
    await _ensureFolder(_basePath);
  }

  Future<void> _ensureFolders(String path) async {
    if (_basePath.isEmpty) {
      return;
    }
    final fullPath = _fullPath(path, basePath: _basePath);
    final parent = _parentPath(fullPath);
    if (parent == null) {
      return;
    }
    for (final folder in _folderChain(parent)) {
      await _ensureFolder(folder);
    }
  }

  Future<void> _ensureFolder(String folder) async {
    if (_ensuredFolders.contains(folder)) {
      return;
    }
    try {
      await _apiClient.createFolder(folder);
    } on SyncAdapterException catch (error) {
      // Yandex returns 409 when a directory already exists at `path`.
      // This is safe to ignore for idempotent folder creation.
      if (error.code == 'yandex_409' &&
          error.message.contains('DiskPathPointsToExistentDirectoryError')) {
        _ensuredFolders.add(folder);
        return;
      }
      rethrow;
    }
    _ensuredFolders.add(folder);
  }

  String? _parentPath(String fullPath) {
    final normalized = fullPath.endsWith('/')
        ? fullPath.substring(0, fullPath.length - 1)
        : fullPath;
    final index = normalized.lastIndexOf('/');
    final colonIndex = normalized.indexOf(':');
    if (colonIndex != -1 && index == colonIndex + 1) {
      // Keep the root collection slash, e.g. `app:/`.
      return normalized.substring(0, index + 1);
    }
    if (index <= 0) {
      return null;
    }
    return normalized.substring(0, index);
  }

  List<String> _folderChain(String folderPath) {
    final normalized = folderPath.endsWith('/')
        ? folderPath.substring(0, folderPath.length - 1)
        : folderPath;
    if (normalized.isEmpty) {
      return const <String>[];
    }

    final colonIndex = normalized.indexOf(':');
    final hasPrefix = colonIndex != -1;
    final prefix = hasPrefix ? normalized.substring(0, colonIndex + 1) : '';
    final rest = hasPrefix ? normalized.substring(colonIndex + 1) : normalized;

    final segments = rest.split('/').where((seg) => seg.isNotEmpty).toList();
    if (segments.isEmpty) {
      return const <String>[];
    }

    final chain = <String>[];
    final base = prefix.isNotEmpty
        ? '$prefix/'
        : (folderPath.startsWith('/') ? '/' : '');
    var current = base;
    for (final segment in segments) {
      current = current.isEmpty || current.endsWith('/')
          ? '$current$segment'
          : '$current/$segment';
      chain.add(current);
    }
    return chain;
  }

  String _fullPath(String name, {String? basePath}) {
    final effectiveBasePath = basePath ?? _basePath;
    final normalized = name.startsWith('/') ? name.substring(1) : name;
    if (effectiveBasePath.isEmpty) {
      return normalized;
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

  Future<SyncFile?> _getFileAtBase(
    String path, {
    required String basePath,
  }) async {
    final fullPath = _fullPath(path, basePath: basePath);
    YandexDiskApiFile? metadata;
    try {
      metadata = await _apiClient.getMetadata(fullPath);
    } on SyncAdapterException catch (error) {
      if (error.code == 'yandex_404') {
        return null;
      }
      rethrow;
    }
    if (metadata == null) {
      return null;
    }
    List<int> bytes;
    try {
      bytes = await _apiClient.download(fullPath);
    } on SyncAdapterException catch (error) {
      if (error.code == 'yandex_404') {
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

  List<SyncFileRef> _toRefs(
    List<YandexDiskApiFile> files, {
    required String basePath,
  }) {
    return files
        .map(
          (file) => SyncFileRef(
            path: _stripBase(file.path, basePath: basePath),
            updatedAt: file.modifiedTime,
            size: file.size,
          ),
        )
        .toList();
  }

  bool _isRootCollection(String basePath) {
    final trimmed = basePath.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return true;
    }
    final normalized = trimmed.endsWith('/') ? trimmed : '$trimmed/';
    final colonIndex = normalized.indexOf(':');
    if (colonIndex == -1) {
      return normalized == '/';
    }
    final prefix = normalized.substring(0, colonIndex + 1);
    return normalized == '$prefix/';
  }
}
