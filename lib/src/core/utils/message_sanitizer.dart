String sanitizeUserMessage(String message) {
  var sanitized = message;
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'\bauthorization\b\s*[:=]\s*(bearer|basic)\s+[A-Za-z0-9\-_\.=:+/]+',
      caseSensitive: false,
    ),
    (match) => 'authorization: ***',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'https?://[^\s\)\]]+'),
    (match) {
      final raw = match.group(0) ?? '';
      final uri = Uri.tryParse(raw);
      if (uri == null) {
        return raw;
      }
      var updated = uri;
      if (uri.userInfo.isNotEmpty) {
        updated = updated.replace(userInfo: '');
      }
      if (uri.hasQuery) {
        final masked = <String, String>{};
        for (final key in uri.queryParameters.keys) {
          masked[key] = '***';
        }
        updated = updated.replace(queryParameters: masked);
      }
      if (uri.fragment.isNotEmpty) {
        updated = updated.replace(fragment: '***');
      }
      return updated.toString();
    },
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'\b(authorization|token|access_token|refresh_token|api[_-]?key|secret|password|passwd|pwd|client_secret)\b\s*[:=]\s*([^\s,;]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}: ***',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'\b(bearer|basic)\s+[A-Za-z0-9\-_\.=:+/]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)} ***',
  );
  return sanitized;
}
