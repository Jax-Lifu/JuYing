class PlaylistSourceDefinition {
  const PlaylistSourceDefinition({
    required this.id,
    required this.name,
    required this.playlistUri,
    required this.rightsConfirmedAt,
    this.enabled = true,
  });

  final String id;
  final String name;
  final Uri playlistUri;
  final DateTime rightsConfirmedAt;
  final bool enabled;
}
