import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_errors.dart';
import 'package:cogniread/src/core/utils/logger.dart';

class DropboxOAuthConfig {
  const DropboxOAuthConfig({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
  });

  final String clientId;
  final String clientSecret;
  final String redirectUri;
}

class DropboxOAuthClient {
  DropboxOAuthClient(this.config, {HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final DropboxOAuthConfig config;
  final HttpClient _httpClient;

  Uri authorizationUrl({
    required String state,
    List<String> scopes = const <String>[
      'files.content.write',
      'files.content.read',
      'files.metadata.read',
    ],
    String responseType = 'code',
    String tokenAccessType = 'offline',
  }) {
    final params = <String, String>{
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri,
      'response_type': responseType,
      'token_access_type': tokenAccessType,
      'state': state,
      'scope': scopes.join(' '),
    };
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

  Future<OAuthToken> exchangeCode(String code) async {
    Log.d('Dropbox token exchange start');
    final uri = Uri.https('api.dropboxapi.com', '/oauth2/token');
    final payload = <String, String>{
      'code': code,
      'grant_type': 'authorization_code',
      'client_id': config.clientId,
      'client_secret': config.clientSecret,
      'redirect_uri': config.redirectUri,
    };
    final body = payload.entries
        .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
        .join('&');

    HttpClientRequest request;
    HttpClientResponse response;
    List<int> bytes;
    String responseText = '';
    try {
      Log.d('Dropbox token exchange: opening connection');
      request = await _httpClient.postUrl(uri);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      Log.d('Dropbox token exchange: sending request');
      request.add(utf8.encode(body));
      Log.d('Dropbox token exchange: awaiting response');
      response = await request.close();
      Log.d('Dropbox token exchange: response opened');
      bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      responseText = utf8.decode(bytes);
      Log.d(
        'Dropbox token exchange: status=${response.statusCode}, '
        'body=$responseText',
      );
      if (response.statusCode >= 400) {
        throw SyncAuthException('Dropbox OAuth exchange failed');
      }
    } catch (error) {
      Log.d('Dropbox token exchange error: $error');
      throw SyncAuthException('Dropbox OAuth exchange failed: $error');
    }
    final decoded = jsonDecode(responseText);
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
      'client_secret': config.clientSecret,
    };
    final body = payload.entries
        .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
        .join('&');

    HttpClientRequest request;
    HttpClientResponse response;
    List<int> bytes;
    String responseText = '';
    try {
      request = await _httpClient.postUrl(uri);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      request.add(utf8.encode(body));
      response = await request.close();
      bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      responseText = utf8.decode(bytes);
      Log.d(
        'Dropbox token refresh: status=${response.statusCode}, '
        'body=$responseText',
      );
      if (response.statusCode >= 400) {
        throw SyncAuthException('Dropbox OAuth refresh failed');
      }
    } catch (error) {
      Log.d('Dropbox token refresh error: $error');
      throw SyncAuthException('Dropbox OAuth refresh failed: $error');
    }
    final decoded = jsonDecode(responseText);
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
  }
}
