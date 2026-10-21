import '../juying_source_providers.dart';

/// Extended M3U and TXT Live Playlist Provider (Section 6.1 source_providers/m3u).
class M3uSourceProvider implements SourceProvider {
  @override
  String get type => 'm3u';

  @override
  Set<SourceCapability> get capabilities => {
        SourceCapability.live,
        SourceCapability.epg,
      };

  @override
  Future<SourceValidationResult> validate(SourceConfig config) async {
    final endpoint = config.endpoint.toLowerCase();
    if (endpoint.endsWith('.m3u') ||
        endpoint.endsWith('.m3u8') ||
        endpoint.endsWith('.txt')) {
      return const SourceValidationResult(isValid: true);
    }
    return const SourceValidationResult(
      isValid: false,
      message: '地址必须以 .m3u, .m3u8 或 .txt 结尾',
    );
  }
}
