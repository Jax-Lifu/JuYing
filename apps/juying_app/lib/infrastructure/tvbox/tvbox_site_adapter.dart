import '../../domain/ports/media_source_adapter.dart';

/// TVBox 配置内单个站点的统一内部边界。
abstract interface class TvboxSiteAdapter implements MediaSourceAdapter {
  String get siteKey;
}
