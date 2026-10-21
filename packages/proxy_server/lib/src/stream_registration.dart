/// Stream token and registration info.
class StreamRegistration {
  const StreamRegistration({
    required this.token,
    required this.upstreamUrl,
    this.headers = const <String, String>{},
    required this.createdAt,
    this.ttl = const Duration(hours: 4),
  });

  final String token;
  final String upstreamUrl;
  final Map<String, String> headers;
  final DateTime createdAt;
  final Duration ttl;

  bool get isExpired => DateTime.now().isAfter(createdAt.add(ttl));
}
