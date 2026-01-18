import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';

class ResilientSyncAdapter implements SyncAdapter {
  ResilientSyncAdapter({
    required SyncAdapter inner,
    int maxAttempts = 3,
    Duration initialBackoff = const Duration(milliseconds: 400),
    Duration maxBackoff = const Duration(seconds: 4),
    int maxConcurrentUploads = 2,
  })  : _inner = inner,
        _maxAttempts = maxAttempts,
        _initialBackoff = initialBackoff,
        _maxBackoff = maxBackoff,
        _uploadSemaphore = _AsyncSemaphore(maxConcurrentUploads);

  final SyncAdapter _inner;
  final int _maxAttempts;
  final Duration _initialBackoff;
  final Duration _maxBackoff;
  final _AsyncSemaphore _uploadSemaphore;

  @override
  Future<List<SyncFileRef>> listFiles() {
    return _withRetry('listFiles', _inner.listFiles);
  }

  @override
  Future<SyncFile?> getFile(String path) {
    return _withRetry('getFile($path)', () => _inner.getFile(path));
  }

  @override
  Future<void> putFile(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    await _uploadSemaphore.withPermit(() {
      return _withRetry(
        'putFile($path)',
        () => _inner.putFile(path, bytes, contentType: contentType),
      );
    });
  }

  @override
  Future<void> deleteFile(String path) {
    return _withRetry('deleteFile($path)', () => _inner.deleteFile(path));
  }

  Future<T> _withRetry<T>(String label, Future<T> Function() action) async {
    final attempts = _maxAttempts < 1 ? 1 : _maxAttempts;
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 1; attempt <= attempts; attempt += 1) {
      try {
        return await action();
      } on SyncAdapterException catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;
        if (attempt >= attempts || !_isRetryable(error)) {
          rethrow;
        }
        final delay = _backoffDelay(attempt);
        Log.d(
          'Sync retry ($attempt/$attempts) $label: $error '
          '→ wait ${delay.inMilliseconds}ms',
        );
        await Future<void>.delayed(delay);
      } on TimeoutException catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;
        if (attempt >= attempts) {
          throw SyncAdapterException(
            'Network timeout',
            code: 'sync_timeout',
          );
        }
        final delay = _backoffDelay(attempt);
        Log.d(
          'Sync retry ($attempt/$attempts) $label: timeout '
          '→ wait ${delay.inMilliseconds}ms',
        );
        await Future<void>.delayed(delay);
      } on SocketException catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;
        if (attempt >= attempts) {
          throw SyncAdapterException(
            'Network error: ${error.message}',
            code: 'sync_socket',
          );
        }
        final delay = _backoffDelay(attempt);
        Log.d(
          'Sync retry ($attempt/$attempts) $label: socket '
          '→ wait ${delay.inMilliseconds}ms',
        );
        await Future<void>.delayed(delay);
      } on HttpException catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;
        if (attempt >= attempts) {
          throw SyncAdapterException(
            'HTTP error: ${error.message}',
            code: 'sync_http',
          );
        }
        final delay = _backoffDelay(attempt);
        Log.d(
          'Sync retry ($attempt/$attempts) $label: http '
          '→ wait ${delay.inMilliseconds}ms',
        );
        await Future<void>.delayed(delay);
      }
    }
    throw StateError(
      'Retry failed: $label, lastError=$lastError, lastStack=$lastStack',
    );
  }

  bool _isRetryable(SyncAdapterException error) {
    final code = error.code;
    if (code == null || code.trim().isEmpty) {
      return false;
    }
    final normalized = code.trim().toLowerCase();
    if (normalized.contains('timeout') ||
        normalized.contains('socket') ||
        normalized.contains('_http')) {
      return true;
    }
    final parts = normalized.split('_');
    final status = parts.isEmpty ? null : int.tryParse(parts.last);
    if (status == null) {
      return false;
    }
    if (status == 429) {
      return true;
    }
    return status >= 500 && status < 600;
  }

  Duration _backoffDelay(int attempt) {
    final base = _initialBackoff;
    final multiplier = 1 << (attempt - 1).clamp(0, 10);
    var delay = Duration(milliseconds: base.inMilliseconds * multiplier);
    if (delay > _maxBackoff) {
      delay = _maxBackoff;
    }
    final jitterMs = Random.secure().nextInt(120);
    return delay + Duration(milliseconds: jitterMs);
  }
}

class _AsyncSemaphore {
  _AsyncSemaphore(this._permits);

  int _permits;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<T> withPermit<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_permits > 0) {
      _permits -= 1;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _permits += 1;
  }
}
