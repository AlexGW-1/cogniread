import 'sync_errors.dart';

class OAuthToken {
  const OAuthToken({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.tokenType = 'Bearer',
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String tokenType;

  bool get isExpired {
    if (expiresAt == null) {
      return false;
    }
    return DateTime.now().toUtc().isAfter(expiresAt!);
  }
}

abstract class OAuthTokenProvider {
  Future<OAuthToken> getToken();

  Future<OAuthToken> refreshToken(OAuthToken token);
}

OAuthToken requireValidToken(OAuthToken token) {
  if (token.accessToken.isEmpty) {
    throw SyncAuthException('Missing access token');
  }
  if (token.isExpired) {
    throw SyncAuthException('Access token expired');
  }
  return token;
}
