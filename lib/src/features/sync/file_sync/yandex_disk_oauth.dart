import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_errors.dart';

class OAuthPkcePair {
  const OAuthPkcePair({
    required this.verifier,
    required this.challenge,
  });

  final String verifier;
  final String challenge;
}

class YandexDiskOAuthConfig {
  const YandexDiskOAuthConfig({
    required this.clientId,
    this.clientSecret,
    required this.redirectUri,
  });

  final String clientId;
  final String? clientSecret;
  final String redirectUri;
}

class YandexDiskOAuthClient {
  YandexDiskOAuthClient(this.config, {HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final YandexDiskOAuthConfig config;
  final HttpClient _httpClient;

  static OAuthPkcePair createPkce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final verifier = base64Url.encode(bytes).replaceAll('=', '');
    final digest = sha256.convert(utf8.encode(verifier));
    final challenge = base64Url.encode(digest.bytes).replaceAll('=', '');
    return OAuthPkcePair(
      verifier: verifier,
      challenge: challenge,
    );
  }

  Uri authorizationUrl({
    required String state,
    // Yandex Disk API uses `cloud_api:*` scopes; app_folder is the most
    // user-friendly and requires no full-disk access.
    List<String> scopes = const <String>['cloud_api:disk.app_folder'],
    String responseType = 'code',
    String? codeChallenge,
    String codeChallengeMethod = 'S256',
  }) {
    final query = <String, String>{
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri,
      'response_type': responseType,
      'scope': scopes.join(' '),
      'state': state,
    };
    if (codeChallenge != null && codeChallenge.isNotEmpty) {
      query['code_challenge'] = codeChallenge;
      query['code_challenge_method'] = codeChallengeMethod;
    }
    return Uri.https('oauth.yandex.ru', '/authorize', query);
  }

  Future<OAuthToken> exchangeCode(
    String code, {
    String? codeVerifier,
  }) async {
    final uri = Uri.https('oauth.yandex.ru', '/token');
    final payload = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri,
    };
    final clientSecret = config.clientSecret;
    if (clientSecret != null && clientSecret.trim().isNotEmpty) {
      payload['client_secret'] = clientSecret.trim();
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
      throw SyncAuthException(
        _formatOAuthError(
          'Yandex OAuth exchange failed',
          statusCode: response.statusCode,
          bytes: bytes,
        ),
      );
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw SyncAuthException('Unexpected Yandex OAuth response');
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
      tokenType: 'OAuth',
    );
  }

  Future<OAuthToken> refreshToken(OAuthToken token) async {
    final refreshToken = token.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw SyncAuthException('Re-auth required');
    }
    final uri = Uri.https('oauth.yandex.ru', '/token');
    final payload = <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri,
    };
    final clientSecret = config.clientSecret;
    if (clientSecret != null && clientSecret.trim().isNotEmpty) {
      payload['client_secret'] = clientSecret.trim();
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
      throw SyncAuthException(
        _formatOAuthError(
          'Yandex OAuth refresh failed',
          statusCode: response.statusCode,
          bytes: bytes,
        ),
      );
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw SyncAuthException('Unexpected Yandex OAuth response');
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
      tokenType: _normalizeTokenType(decoded['token_type']),
    );
  }

  String _normalizeTokenType(Object? raw) {
    final tokenType = raw is String ? raw.trim() : '';
    if (tokenType.isEmpty) {
      return 'OAuth';
    }
    if (tokenType.toUpperCase() == 'BEARER') {
      return 'OAuth';
    }
    return tokenType;
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
      if (description?.isNotEmpty == true)
        'description=$description',
    ];
    return parts.join(', ');
  }
}
