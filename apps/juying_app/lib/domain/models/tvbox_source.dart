class TvboxSourceDefinition {
  const TvboxSourceDefinition({
    required this.id,
    required this.name,
    required this.configUri,
    required this.rightsConfirmedAt,
    this.epgTemplate,
    this.enabled = true,
  });

  final String id;
  final String name;
  final Uri configUri;
  final DateTime rightsConfirmedAt;
  final String? epgTemplate;
  final bool enabled;

  TvboxSourceDefinition copyWith({String? epgTemplate}) =>
      TvboxSourceDefinition(
        id: id,
        name: name,
        configUri: configUri,
        rightsConfirmedAt: rightsConfirmedAt,
        epgTemplate: epgTemplate ?? this.epgTemplate,
        enabled: enabled,
      );
}
