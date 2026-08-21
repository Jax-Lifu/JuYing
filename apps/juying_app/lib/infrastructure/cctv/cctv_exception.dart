class CctvException implements Exception {
  const CctvException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
