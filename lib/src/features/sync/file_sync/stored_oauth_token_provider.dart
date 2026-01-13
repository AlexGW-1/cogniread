import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_auth_store.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_errors.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_provider.dart';

typedef TokenRefresher = Future<OAuthToken> Function(OAuthToken token);

class StoredOAuthTokenProvider implements OAuthTokenProvider {
  StoredOAuthTokenProvider({
    required this.provider,
    required SyncAuthStore store,
    required TokenRefresher refreshToken,
  })  : _store = store,
        _refreshToken = refreshToken;

  final SyncProvider provider;
  final SyncAuthStore _store;
  final TokenRefresher _refreshToken;

  @override
  Future<OAuthToken> getToken() async {
    final token = await _store.loadToken(provider);
    if (token == null) {
      throw SyncAuthException('Missing access token');
    }
    if (token.isExpired) {
      final refreshed = await _refreshToken(token);
      await _store.saveToken(provider, refreshed);
      return refreshed;
    }
    return token;
  }

  @override
  Future<OAuthToken> refreshToken(OAuthToken token) async {
    final refreshed = await _refreshToken(token);
    await _store.saveToken(provider, refreshed);
    return refreshed;
  }
}
