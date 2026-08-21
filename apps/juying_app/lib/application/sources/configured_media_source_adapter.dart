import '../../domain/models/media_source.dart';
import '../../domain/models/unified_media.dart';
import '../../domain/ports/media_source_adapter.dart';
import '../../domain/ports/catalog_initial_category.dart';
import '../../domain/ports/source_catalog_tabs.dart';
import '../../domain/ports/source_catalog_scopes.dart';

/// 用声明式来源清单替换内建适配器的显示、启用与能力快照。
/// 仅允许收窄能力，禁止配置把来源升级为未实现的能力。
class ConfiguredMediaSourceAdapter
    implements
        MediaSourceAdapter,
        SourceCatalogTabs,
        SourceCatalogScopes,
        CatalogInitialCategory {
  ConfiguredMediaSourceAdapter(this._delegate, this._source) {
    if (_delegate.source.id != _source.id) {
      throw ArgumentError('配置来源 ID 与内建适配器不一致');
    }
    if (!_delegate.source.capabilities.containsAll(_source.capabilities)) {
      throw ArgumentError('配置声明了内建适配器不支持的能力');
    }
  }

  final MediaSourceAdapter _delegate;
  final MediaSource _source;

  @override
  MediaSource get source => _source;

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) =>
      _delegate.browse(query);

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) =>
      _delegate.episodes(item);

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(MediaEpisode episode) =>
      _delegate.resolveOfficialFallback(episode);

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) =>
      _delegate.resolvePlayback(episode);

  @override
  Future<List<MediaSearchHit>> search(String query) => _delegate.search(query);

  @override
  MediaCategory get initialCatalogCategory =>
      _delegate is CatalogInitialCategory
          ? (_delegate as CatalogInitialCategory).initialCatalogCategory
          : MediaCategory.live;

  @override
  bool get supportsSubtabs =>
      _delegate is SourceCatalogTabs &&
      (_delegate as SourceCatalogTabs).supportsSubtabs;

  @override
  List<SourceCatalogTab> get primaryTabs => _delegate is SourceCatalogTabs
      ? (_delegate as SourceCatalogTabs).primaryTabs
      : const [];

  @override
  List<SourceCatalogTab> subTabsFor(
    MediaCategory category,
    Iterable<MediaItem> items,
  ) =>
      _delegate is SourceCatalogTabs
          ? (_delegate as SourceCatalogTabs).subTabsFor(category, items)
          : const [];

  @override
  Future<List<SourceCatalogScope>> catalogScopes() =>
      _delegate is SourceCatalogScopes
          ? (_delegate as SourceCatalogScopes).catalogScopes()
          : Future.value(const []);

  @override
  Future<Set<String>> availableCatalogScopeIds({
    required MediaCategory category,
    bool refresh = false,
  }) =>
      _delegate is SourceCatalogScopes
          ? (_delegate as SourceCatalogScopes).availableCatalogScopeIds(
              category: category,
              refresh: refresh,
            )
          : Future.value(const {});

  @override
  String? get selectedCatalogScopeId => _delegate is SourceCatalogScopes
      ? (_delegate as SourceCatalogScopes).selectedCatalogScopeId
      : null;

  @override
  Future<void> selectCatalogScope(String? id) =>
      _delegate is SourceCatalogScopes
          ? (_delegate as SourceCatalogScopes).selectCatalogScope(id)
          : Future.value();
}
