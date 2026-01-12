import 'sync_adapter.dart';

class SyncAuthException extends SyncAdapterException {
  SyncAuthException(String message)
      : super(message, code: 'auth_failed');
}

class SyncRateLimitException extends SyncAdapterException {
  SyncRateLimitException(String message)
      : super(message, code: 'rate_limited');
}

class SyncNetworkException extends SyncAdapterException {
  SyncNetworkException(String message)
      : super(message, code: 'network_error');
}
