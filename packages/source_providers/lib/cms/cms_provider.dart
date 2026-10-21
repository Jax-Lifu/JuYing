import '../juying_source_providers.dart';

/// MacCMS / OpenCMS JSON and XML API Provider (Section 6.1 source_providers/cms).
class CmsSourceProvider implements SourceProvider {
  @override
  String get type => 'cms';

  @override
  Set<SourceCapability> get capabilities => {
        SourceCapability.vod,
        SourceCapability.search,
        SourceCapability.browse,
      };

  @override
  Future<SourceValidationResult> validate(SourceConfig config) async {
    final uri = Uri.tryParse(config.endpoint);
    if (uri != null && uri.hasScheme) {
      return const SourceValidationResult(isValid: true);
    }
    return const SourceValidationResult(
      isValid: false,
      message: 'CMS 接口地址必须是有效的 HTTP(S) URL',
    );
  }
}
