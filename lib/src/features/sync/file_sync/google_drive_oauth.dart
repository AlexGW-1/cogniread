import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/oauth_pkce.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_errors.dart';

class GoogleDriveOAuthConfig {
  const GoogleDriveOAuthConfig({
    required this.clientId,
    this.clientSecret,
    required this.redirectUri,
  });

  final String clientId;
  final String? clientSecret;
  final String redirectUri;
}

class GoogleDriveOAuthClient {
  GoogleDriveOAuthClient(this.config, {HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final GoogleDriveOAuthConfig config;
  final HttpClient _httpClient;

  static OAuthPkcePair createPkce() {
    return OAuthPkce.create();
  }

  Uri authorizationUrl({
    required String state,
    List<String> scopes = const <String>[
      'https://www.googleapis.com/auth/drive.appdata',
    ],
    String accessType = 'offline',
    String responseType = 'code',
    String? codeChallenge,
    String codeChallengeMethod = 'S256',
  }) {
    final params = <String, String>{
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri,
      'response_type': responseType,
      'scope': scopes.join(' '),
      'access_type': accessType,
      'state': state,
      'prompt': 'consent',
    };
    if (codeChallenge != null && codeChallenge.isNotEmpty) {
      params['code_challenge'] = codeChallenge;
      params['code_challenge_method'] = codeChallengeMethod;
    }
    return Uri.https('accounts.google.com', '/o/oauth2/v2/auth', params);
  }

  Future<OAuthToken> exchangeCode(
    String code, {
    String? codeVerifier,
  }) async {
    final uri = Uri.https('oauth2.googleapis.com', '/token');
    final payload = <String, String>{
      'code': code,
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri,
      'grant_type': 'authorization_code',
    };
    final secret = config.clientSecret;
    if (secret != null && secret.trim().isNotEmpty) {
      payload['client_secret'] = secret.trim();
    }
    if (codeVerifier != null && codeVerifier.trim().isNotEmpty) {
      payload['code_verifier'] = codeVerifier.trim();
    }
    final body = payload.entries
        .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
        .join('&');

    final request = await _httpClient.postUrl(uri);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/x-www-form-urlencoded',
    );
    request.add(utf8.encode(body));
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (response.statusCode >= 400) {
      throw SyncAuthException('OAuth exchange failed');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw SyncAuthException('Unexpected OAuth response');
    }
    final accessToken = decoded['access_token'] as String? ?? '';
    final refreshToken = decoded['refresh_token'] as String?;
    final expiresIn = decoded['expires_in'];
    final expiresAt = expiresIn is num
        ? DateTime.now().toUtc().add(Duration(seconds: expiresIn.toInt()))
        : null;
    return OAuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      tokenType: decoded['token_type'] as String? ?? 'Bearer',
    );
  }

  Future<OAuthToken> refreshToken(OAuthToken token) async {
    final refreshToken = token.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw SyncAuthException('Missing refresh token');
    }
    final uri = Uri.https('oauth2.googleapis.com', '/token');
    final payload = <String, String>{
      'client_id': config.clientId,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    };
    final secret = config.clientSecret;
    if (secret != null && secret.trim().isNotEmpty) {
      payload['client_secret'] = secret.trim();
    }
    final body = payload.entries
        .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
        .join('&');

    final request = await _httpClient.postUrl(uri);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/x-www-form-urlencoded',
    );
    request.add(utf8.encode(body));
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (response.statusCode >= 400) {
      throw SyncAuthException('OAuth refresh failed');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw SyncAuthException('Unexpected OAuth refresh response');
    }
    final accessToken = decoded['access_token'] as String? ?? '';
    final expiresIn = decoded['expires_in'];
    final expiresAt = expiresIn is num
        ? DateTime.now().toUtc().add(Duration(seconds: expiresIn.toInt()))
        : null;
    return OAuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      tokenType: decoded['token_type'] as String? ?? 'Bearer',
    );
  }
}
