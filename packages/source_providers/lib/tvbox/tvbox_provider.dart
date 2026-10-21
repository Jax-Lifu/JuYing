import '../juying_source_providers.dart';
export 'ports/ported_spider_contract.dart';

/// TVBox Single/Multi-Repository Configuration Provider (Section 6.1 source_providers/tvbox).
class TvboxSourceProvider implements SourceProvider {
  @override
  String get type => 'tvbox';

  @override
  Set<SourceCapability> get capabilities => {
        SourceCapability.vod,
        SourceCapability.live,
        SourceCapability.search,
        SourceCapability.browse,
      };

  @override
  Future<SourceValidationResult> validate(SourceConfig config) async {
    final uri = Uri.tryParse(config.endpoint);
    if (uri != null &&
        (uri.hasScheme || config.endpoint.startsWith('file://'))) {
      return const SourceValidationResult(isValid: true);
    }
    return const SourceValidationResult(
      isValid: false,
      message: 'TVBox 配置地址无效',
    );
  }
}
