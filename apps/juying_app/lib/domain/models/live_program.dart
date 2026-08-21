class LiveProgram {
  const LiveProgram({
    required this.sourceId,
    required this.sourceItemId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.description,
  });

  final String sourceId;
  final String sourceItemId;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? description;
}
