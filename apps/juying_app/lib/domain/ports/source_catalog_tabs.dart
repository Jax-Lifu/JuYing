import '../models/unified_media.dart';

abstract interface class SourceCatalogTabs {
  /// 子分类入口需要在目录请求完成前可见，避免网络失败时丢失可发现性。
  bool get supportsSubtabs;

  List<SourceCatalogTab> get primaryTabs;

  List<SourceCatalogTab> subTabsFor(
    MediaCategory category,
    Iterable<MediaItem> items,
  );
}
