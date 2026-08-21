enum MediaSourceKind { officialWeb, authorizedApi, nas, local, custom }

enum SourceAuthorization { officialEntryOnly, userOwned, licensed, unknown }

enum SourceCapability {
  browse,
  liveCatalog,
  search,
  episodes,
  nativePublicPlayback,
  officialFallback,
  qualitySelection,
  playbackSpeed,
  volumeControl,
  fullscreen,
  continueWatching,
  liveProgramGuide,
}

enum SourceHealth { unknown, healthy, degraded, unavailable }

enum SourceLifecycle { active, paused, circuitOpen, retired }

class MediaSource {
  const MediaSource({
    required this.id,
    required this.name,
    required this.kind,
    required this.entryUrl,
    required this.enabled,
    required this.authorization,
    this.capabilities = const {},
    this.health = SourceHealth.unknown,
    this.lifecycle = SourceLifecycle.active,
    this.regionCode,
    this.authorizationExpiresAt,
    this.configVersion = 1,
    this.priority = 0,
  });

  final String id;
  final String name;
  final MediaSourceKind kind;
  final String entryUrl;
  final bool enabled;
  final SourceAuthorization authorization;
  final Set<SourceCapability> capabilities;
  final SourceHealth health;
  final SourceLifecycle lifecycle;
  final String? regionCode;
  final DateTime? authorizationExpiresAt;
  final int configVersion;

  /// 同等匹配条件下的用户/部署优先级；不允许覆盖授权和可播放性排序。
  final int priority;

  bool get isActive => enabled && lifecycle == SourceLifecycle.active;

  MediaSource copyWith({
    bool? enabled,
    Set<SourceCapability>? capabilities,
    SourceHealth? health,
    SourceLifecycle? lifecycle,
    String? regionCode,
    DateTime? authorizationExpiresAt,
    int? configVersion,
    int? priority,
  }) =>
      MediaSource(
        id: id,
        name: name,
        kind: kind,
        entryUrl: entryUrl,
        enabled: enabled ?? this.enabled,
        authorization: authorization,
        capabilities: capabilities ?? this.capabilities,
        health: health ?? this.health,
        lifecycle: lifecycle ?? this.lifecycle,
        regionCode: regionCode ?? this.regionCode,
        authorizationExpiresAt:
            authorizationExpiresAt ?? this.authorizationExpiresAt,
        configVersion: configVersion ?? this.configVersion,
        priority: priority ?? this.priority,
      );
}
