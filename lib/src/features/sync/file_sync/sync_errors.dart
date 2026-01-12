import 'sync_adapter.dart';

class SyncAuthException extends SyncAdapterException {
  SyncAuthException(super.message) : super(code: 'auth_failed');
}

class SyncRateLimitException extends SyncAdapterException {
  SyncRateLimitException(super.message) : super(code: 'rate_limited');
}

class SyncNetworkException extends SyncAdapterException {
  SyncNetworkException(super.message) : super(code: 'network_error');
}
