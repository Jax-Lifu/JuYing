import '../../domain/models/unified_media.dart';

/// 在缺少可靠分级数据时采取保守策略：儿童档案只见动画片和少儿分类。
/// 后续来源提供可审计分级后，再按儿童档案的 allowedRating 放宽。
abstract final class ChildContentPolicy {
  static const allowedCategories = {
    MediaCategory.animation,
    MediaCategory.kids,
  };

  static bool allows(MediaItem item, {required bool isChildProfile}) =>
      !isChildProfile || allowedCategories.contains(item.category);

  static bool allowsCategory(
    MediaCategory category, {
    required bool isChildProfile,
  }) =>
      !isChildProfile || allowedCategories.contains(category);
}
