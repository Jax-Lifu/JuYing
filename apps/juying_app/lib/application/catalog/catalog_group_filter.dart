import '../../domain/models/unified_media.dart';

/// 目录层只消费适配器已规范化的来源分组标签；不会识别某个来源的原始字段。
abstract final class CatalogGroupFilter {
  static List<String> groups(Iterable<MediaItem> items) => items
      .map((item) => item.sourceCategoryLabel?.trim())
      .whereType<String>()
      .where((label) => label.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  static List<MediaItem> apply(Iterable<MediaItem> items, String? group) {
    if (group == null) return items.toList(growable: false);
    return items
        .where((item) => item.sourceCategoryLabel?.trim() == group)
        .toList(growable: false);
  }
}
