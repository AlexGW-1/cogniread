import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/oauth_pkce.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_errors.dart';
import 'package:cogniread/src/core/utils/logger.dart';

class DropboxOAuthConfig {
  const DropboxOAuthConfig({
    required this.clientId,
    this.clientSecret,
    required this.redirectUri,
  });

  final String clientId;
  final String? clientSecret;
  final String redirectUri;
}

class DropboxOAuthClient {
  DropboxOAuthClient(this.config, {HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final DropboxOAuthConfig config;
  final HttpClient _httpClient;

  static OAuthPkcePair createPkce() {
    return OAuthPkce.create();
  }

  Uri authorizationUrl({
    required String state,
    List<String> scopes = const <String>[
      'files.content.write',
      'files.content.read',
      'files.metadata.read',
    ],
    String responseType = 'code',
    String tokenAccessType = 'offline',
    String? codeChallenge,
    String codeChallengeMethod = 'S256',
  }) {
    final params = <String, String>{
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri,
      'response_type': responseType,
      'token_access_type': tokenAccessType,
      'state': state,
      'scope': scopes.join(' '),
    };
    if (codeChallenge != null && codeChallenge.isNotEmpty) {
      params['code_challenge'] = codeChallenge;
      params['code_challenge_method'] = codeChallengeMethod;
    }
    Log.d(
      'Dropbox OAuth URL params: client_id=${config.clientId}, '
      'redirect_uri=${config.redirectUri}, '
      'response_type=$responseType, token_access_type=$tokenAccessType, '
      'scopes=${scopes.join(' ')}',
    );
    final uri = Uri.https('www.dropbox.com', '/oauth2/authorize', params);
    Log.d('Dropbox OAuth URL: $uri');
    return uri;
  }

  Future<OAuthToken> exchangeCode(
    String code, {
    String? codeVerifier,
  }) async {
    final uri = Uri.https('api.dropboxapi.com', '/oauth2/token');
    final payload = <String, String>{
      'code': code,
      'grant_type': 'authorization_code',
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri,
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

    try {
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
        throw SyncAuthException(
          _formatOAuthError(
            'Dropbox OAuth exchange failed',
            statusCode: response.statusCode,
            bytes: bytes,
          ),
        );
      }
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is! Map) {
      throw SyncAuthException('Unexpected Dropbox OAuth response');
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
    } catch (error) {
      Log.d('Dropbox token exchange error: $error');
      throw SyncAuthException('Dropbox OAuth exchange failed');
    }
  }

  Future<OAuthToken> refreshToken(OAuthToken token) async {
    final refreshToken = token.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw SyncAuthException('Missing refresh token');
    }
    final uri = Uri.https('api.dropboxapi.com', '/oauth2/token');
    final payload = <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': config.clientId,
    };
    final secret = config.clientSecret;
    if (secret != null && secret.trim().isNotEmpty) {
      payload['client_secret'] = secret.trim();
    }
    final body = payload.entries
        .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
        .join('&');

    try {
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
        throw SyncAuthException(
          _formatOAuthError(
            'Dropbox OAuth refresh failed',
            statusCode: response.statusCode,
            bytes: bytes,
          ),
        );
      }
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is! Map) {
        throw SyncAuthException('Unexpected Dropbox OAuth response');
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
    } catch (error) {
      Log.d('Dropbox token refresh error: $error');
      throw SyncAuthException('Dropbox OAuth refresh failed');
    }
  }

  String _formatOAuthError(
    String message, {
    required int statusCode,
    required List<int> bytes,
  }) {
    final raw = bytes.isEmpty ? '' : utf8.decode(bytes, allowMalformed: true);
    String? error;
    String? description;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        error = decoded['error']?.toString();
        description = decoded['error_description']?.toString();
      }
    } catch (_) {}
    final parts = <String>[
      message,
      'status=$statusCode',
      if (error?.isNotEmpty == true) 'error=$error',
      if (description?.isNotEmpty == true) 'description=$description',
    ];
    return parts.join(', ');
  }
}
