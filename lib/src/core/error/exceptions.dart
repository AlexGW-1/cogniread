class AppException implements Exception {
  AppException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'AppException(message: $message, cause: $cause)';
}

class NotImplementedYetException extends AppException {
  NotImplementedYetException(String message, {Object? cause})
      : super(message, cause: cause);
}
