import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class OAuthPkcePair {
  const OAuthPkcePair({
    required this.verifier,
    required this.challenge,
  });

  final String verifier;
  final String challenge;
}

class OAuthPkce {
  static OAuthPkcePair create({int length = 32}) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    final verifier = base64Url.encode(bytes).replaceAll('=', '');
    final digest = sha256.convert(utf8.encode(verifier));
    final challenge = base64Url.encode(digest.bytes).replaceAll('=', '');
    return OAuthPkcePair(
      verifier: verifier,
      challenge: challenge,
    );
  }
}

