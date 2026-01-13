import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_errors.dart';

class OneDriveOAuthConfig {
  const OneDriveOAuthConfig({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.tenant = 'common',
  });

  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final String tenant;
}

class OneDriveOAuthClient {
  OneDriveOAuthClient(this.config, {HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final OneDriveOAuthConfig config;
  final HttpClient _httpClient;

  Uri authorizationUrl({
    required String state,
    List<String> scopes = const <String>[
      'offline_access',
      'Files.ReadWrite.AppFolder',
    ],
    String responseType = 'code',
  }) {
    return Uri.https(
      'login.microsoftonline.com',
      '/${config.tenant}/oauth2/v2.0/authorize',
      <String, String>{
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri,
        'response_type': responseType,
        'scope': scopes.join(' '),
        'state': state,
      },
    );
  }

  Future<OAuthToken> exchangeCode(String code) async {
    final uri = Uri.https(
      'login.microsoftonline.com',
      '/${config.tenant}/oauth2/v2.0/token',
    );
    final payload = <String, String>{
      'client_id': config.clientId,
      'client_secret': config.clientSecret,
      'redirect_uri': config.redirectUri,
      'grant_type': 'authorization_code',
      'code': code,
    };
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
      throw SyncAuthException('OneDrive OAuth exchange failed');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw SyncAuthException('Unexpected OneDrive OAuth response');
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
    final uri = Uri.https(
      'login.microsoftonline.com',
      '/${config.tenant}/oauth2/v2.0/token',
    );
    final payload = <String, String>{
      'client_id': config.clientId,
      'client_secret': config.clientSecret,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    };
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
      throw SyncAuthException('OneDrive OAuth refresh failed');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw SyncAuthException('Unexpected OneDrive OAuth response');
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
