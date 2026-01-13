class WebDavCredentials {
  const WebDavCredentials({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  final String baseUrl;
  final String username;
  final String password;
}
