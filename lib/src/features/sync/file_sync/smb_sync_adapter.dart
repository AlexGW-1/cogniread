import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:path/path.dart' as p;

class SmbSyncAdapter implements SyncAdapter {
  SmbSyncAdapter({required String mountPath, String basePath = 'cogniread'})
    : _mountPath = p.normalize(mountPath),
      _basePath = basePath;

  final String _mountPath;
  final String _basePath;

  @override
  Future<List<SyncFileRef>> listFiles() async {
    final baseDir = await _ensureBaseDir();
    final refs = <SyncFileRef>[];
    await for (final entity in baseDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final stat = await entity.stat();
      final relative = p.relative(entity.path, from: baseDir.path);
      refs.add(
        SyncFileRef(
          path: _toSyncPath(relative),
          updatedAt: stat.modified,
          size: stat.size,
        ),
      );
    }
    return refs;
  }

  @override
  Future<SyncFile?> getFile(String path) async {
    final baseDir = await _ensureBaseDir();
    final target = File(_resolve(path, baseDir));
    if (!await target.exists()) {
      return null;
    }
    final bytes = await target.readAsBytes();
    final stat = await target.stat();
    return SyncFile(
      ref: SyncFileRef(path: path, updatedAt: stat.modified, size: stat.size),
      bytes: bytes,
    );
  }

  @override
  Future<void> putFile(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    final baseDir = await _ensureBaseDir();
    final targetPath = _resolve(path, baseDir);
    final parent = Directory(p.dirname(targetPath));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final file = File(targetPath);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> deleteFile(String path) async {
    final baseDir = await _ensureBaseDir();
    final resolved = _resolve(path, baseDir);
    final targetFile = File(resolved);
    if (await targetFile.exists()) {
      await targetFile.delete();
      return;
    }
    final targetDir = Directory(resolved);
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
  }

  String _resolve(String path, Directory baseDir) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return p.join(baseDir.path, normalized);
  }

  Future<Directory> _ensureBaseDir() async {
    final mountDir = Directory(_mountPath);
    if (!await mountDir.exists()) {
      throw SyncAdapterException(
        'SMB path not found: ${mountDir.path}',
        code: 'smb_not_found',
      );
    }
    if (_basePath.isEmpty) {
      return mountDir;
    }
    final baseDir = Directory(p.join(mountDir.path, _basePath));
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }

  String _toSyncPath(String relative) {
    return p.posix.joinAll(p.split(relative));
  }
}
