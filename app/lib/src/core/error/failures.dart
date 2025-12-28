sealed class Failure {
  const Failure(this.message);
  final String message;

  @override
  String toString() => 'Failure($message)';
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Unknown failure']);
}
