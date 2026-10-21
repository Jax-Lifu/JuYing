/// Source Provider Interfaces and Registry for JuYing.
///
/// **What**: Defines [SourceProvider] contracts for IPTV playlists, VOD crawlers,
/// TVBox configs, and network storage shares (Section 5.2).
///
/// **Why**: A unified source interface ensures that presentation layers interact
/// only with capability-checked abstractions rather than concrete protocol parsers.
library;

export 'cms/cms_provider.dart';
export 'm3u/m3u_provider.dart';
export 'storage/storage_providers.dart';
export 'tvbox/tvbox_provider.dart';

/// Capabilities exposed by a media source.
enum SourceCapability {
  live,
  vod,
  browse,
  search,
  epg,
}

/// Generic source configuration.
class SourceConfig {
  const SourceConfig({
    required this.id,
    required this.type,
    required this.name,
    required this.endpoint,
    this.headers = const <String, String>{},
    this.credentialRef,
    this.enabled = true,
  });

  final String id;
  final String type;
  final String name;
  final String endpoint;
  final Map<String, String> headers;
  final String? credentialRef;
  final bool enabled;
}

/// Validation result for a source configuration.
class SourceValidationResult {
  const SourceValidationResult({
    required this.isValid,
    this.message,
  });

  final bool isValid;
  final String? message;
}

/// Abstract contract for all media source providers (Section 5.2).
abstract class SourceProvider {
  String get type;
  Set<SourceCapability> get capabilities;
  Future<SourceValidationResult> validate(SourceConfig config);
}
