import '../models/unified_media.dart';

class SourceCatalogScope {
  const SourceCatalogScope({
    required this.id,
    required this.label,
    required this.sourceKey,
    this.categories,
  });

  /// 来源命名空间内稳定标识，不能跨来源使用。
  final String id;
  final String label;
  final String sourceKey;
  final Set<MediaCategory>? categories;

  bool appliesTo(MediaCategory category) =>
      categories == null || categories!.contains(category);
}

/// 可在同一媒体来源内切换的目录范围，例如 TVBox 配置中的站点 key。
/// UI 只依赖此契约，不读取来源专有配置。
abstract interface class SourceCatalogScopes {
  Future<List<SourceCatalogScope>> catalogScopes();

  /// 返回当前分类下能成功响应目录请求的范围 ID。
  /// 实现方可以缓存检测结果；[refresh] 为 true 时应重新检测。
  Future<Set<String>> availableCatalogScopeIds({
    required MediaCategory category,
    bool refresh = false,
  });

  String? get selectedCatalogScopeId;

  /// `null` 恢复来源自己的自动选择策略。
  Future<void> selectCatalogScope(String? id);
}
