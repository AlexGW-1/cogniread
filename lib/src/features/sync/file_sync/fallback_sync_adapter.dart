import 'dart:async';
import 'dart:io';

import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';

class FallbackSyncAdapter implements SyncAdapter {
  FallbackSyncAdapter({
    required SyncAdapter primary,
    required SyncAdapter secondary,
    String label = 'nas',
  })  : _primary = primary,
        _secondary = secondary,
        _label = label;

  final SyncAdapter _primary;
  final SyncAdapter _secondary;
  final String _label;
  bool _useSecondary = false;

  @override
  Future<List<SyncFileRef>> listFiles() {
    return _run('listFiles', (adapter) => adapter.listFiles());
  }

  @override
  Future<SyncFile?> getFile(String path) {
    return _run('getFile($path)', (adapter) => adapter.getFile(path));
  }

  @override
  Future<void> putFile(
    String path,
    List<int> bytes, {
    String? contentType,
  }) {
    return _run(
      'putFile($path)',
      (adapter) => adapter.putFile(
        path,
        bytes,
        contentType: contentType,
      ),
    );
  }

  @override
  Future<void> deleteFile(String path) {
    return _run('deleteFile($path)', (adapter) => adapter.deleteFile(path));
  }

  Future<T> _run<T>(
    String action,
    Future<T> Function(SyncAdapter adapter) run,
  ) async {
    if (_useSecondary) {
      return run(_secondary);
    }
    try {
      return await run(_primary);
    } catch (error) {
      if (_shouldFallback(error)) {
        Log.d(
          'FallbackSyncAdapter($_label): $action failed, switching to secondary: $error',
        );
        _useSecondary = true;
        return run(_secondary);
      }
      rethrow;
    }
  }

  bool _shouldFallback(Object error) {
    if (error is SyncAdapterException) {
      final code = error.code;
      if (code == 'webdav_401' || code == 'webdav_403') {
        return false;
      }
      if (code != null && code.startsWith('webdav_')) {
        return true;
      }
      return false;
    }
    return error is TimeoutException ||
        error is HandshakeException ||
        error is SocketException ||
        error is HttpException;
  }
}
