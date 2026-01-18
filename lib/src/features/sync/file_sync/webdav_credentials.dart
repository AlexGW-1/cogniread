class WebDavCredentials {
  const WebDavCredentials({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.allowInsecure = false,
    this.syncPath = 'cogniread',
  });

  final String baseUrl;
  final String username;
  final String password;
  final bool allowInsecure;
  final String syncPath;
}
