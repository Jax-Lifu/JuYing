import '../../domain/models/media_source.dart';
import '../../domain/models/live_program.dart';
import '../../domain/models/unified_media.dart';
import '../../domain/ports/live_program_guide.dart';
import '../../domain/ports/catalog_initial_category.dart';
import '../../domain/ports/media_source_adapter.dart';
import '../../domain/ports/source_catalog_tabs.dart';
import '../../domain/ports/source_catalog_scopes.dart';

/// 在来源边界阻止来源身份泄漏或跨源数据混入通用流程。
class MediaSourceContractViolation implements Exception {
  const MediaSourceContractViolation(this.message);
  final String message;

  @override
  String toString() => 'MediaSourceContractViolation: $message';
}

class ValidatedMediaSourceAdapter
    implements
        MediaSourceAdapter,
        LiveProgramGuide,
        SourceCatalogTabs,
        SourceCatalogScopes,
        CatalogInitialCategory {
  const ValidatedMediaSourceAdapter(this._delegate);
  final MediaSourceAdapter _delegate;

  @override
  get source => _delegate.source;

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) async {
    _requireCapability(SourceCapability.browse, '目录');
    final page = await _delegate.browse(query);
    if (page.page != query.page || page.total < page.items.length) {
      throw const MediaSourceContractViolation('目录分页信息无效');
    }
    _verifyItems(page.items, '目录');
    return page;
  }

  @override
  Future<List<MediaSearchHit>> search(String query) async {
    _requireCapability(SourceCapability.search, '搜索');
    final hits = await _delegate.search(query);
    _verifyItems(hits.map((hit) => hit.item), '搜索');
    for (final hit in hits) {
      if (hit.query.trim().isEmpty || hit.matchedField.trim().isEmpty) {
        throw const MediaSourceContractViolation('搜索命中缺少查询或匹配字段');
      }
    }
    return hits;
  }

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) async {
    _requireCapability(SourceCapability.episodes, '选集');
    _verifySource(item.sourceId, '请求选集');
    final episodes = await _delegate.episodes(item);
    final ids = <String>{};
    for (final episode in episodes) {
      _verifySource(episode.sourceId, '选集');
      if (episode.sourceEpisodeId.trim().isEmpty || !ids.add(episode.id)) {
        throw const MediaSourceContractViolation('选集缺少稳定 ID 或存在重复 ID');
      }
    }
    return episodes;
  }

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) async {
    _requireCapability(SourceCapability.nativePublicPlayback, '原生播放');
    _verifySource(episode.sourceId, '请求原生播放');
    return _verifyPlayback(await _delegate.resolvePlayback(episode), episode);
  }

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(
    MediaEpisode episode,
  ) async {
    _requireCapability(SourceCapability.officialFallback, '官方回退');
    _verifySource(episode.sourceId, '请求官方回退');
    return _verifyPlayback(
      await _delegate.resolveOfficialFallback(episode),
      episode,
    );
  }

  @override
  Future<List<LiveProgram>> programGuide(
    MediaItem item, {
    DateTime? now,
  }) async {
    _requireCapability(SourceCapability.liveProgramGuide, '节目单');
    _verifySource(item.sourceId, '请求节目单');
    final delegate = _delegate;
    if (delegate is! LiveProgramGuide) {
      throw const MediaSourceContractViolation('来源未实现节目单能力');
    }
    final programs = await (delegate as LiveProgramGuide).programGuide(
      item,
      now: now,
    );
    for (final program in programs) {
      _verifySource(program.sourceId, '节目单');
      if (program.sourceItemId != item.sourceItemId ||
          program.title.trim().isEmpty ||
          !program.endsAt.isAfter(program.startsAt)) {
        throw const MediaSourceContractViolation('节目单条目无效');
      }
    }
    return programs;
  }

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

  PlaybackDescriptor _verifyPlayback(
    PlaybackDescriptor playback,
    MediaEpisode episode,
  ) {
    _verifySource(playback.sourceId, '播放描述');
    if (playback.sourceEpisodeId != episode.sourceEpisodeId) {
      throw const MediaSourceContractViolation('播放描述与请求集不一致');
    }
    if (playback.title.trim().isEmpty ||
        !_isSupportedHttpUri(playback.officialPageUri)) {
      throw const MediaSourceContractViolation('播放描述缺少有效官方入口');
    }
    if (playback.nativeStreamUri != null &&
        !_isSupportedHttpUri(playback.nativeStreamUri!)) {
      throw const MediaSourceContractViolation('播放描述包含无效原生地址');
    }
    if (playback.expiresAt?.isBefore(DateTime.now()) ?? false) {
      throw const MediaSourceContractViolation('播放描述已过期');
    }
    return playback;
  }

  void _verifyItems(Iterable<MediaItem> items, String action) {
    final ids = <String>{};
    for (final item in items) {
      _verifySource(item.sourceId, action);
      if (item.sourceItemId.trim().isEmpty ||
          !_isSupportedHttpUri(item.officialDetailUri) ||
          !_isSupportedHttpUri(item.defaultEpisodePageUri) ||
          (item.workIdentity != null && item.workIdentity!.id.trim().isEmpty) ||
          !ids.add(item.id)) {
        throw MediaSourceContractViolation('$action缺少稳定 ID 或存在重复 ID');
      }
    }
  }

  void _verifySource(String sourceId, String action) {
    if (sourceId != source.id) {
      throw MediaSourceContractViolation('$action返回了其他来源的数据');
    }
  }

  void _requireCapability(SourceCapability capability, String action) {
    if (!source.capabilities.contains(capability)) {
      throw MediaSourceContractViolation('来源未声明$action能力');
    }
  }

  bool _isSupportedHttpUri(Uri uri) =>
      uri.isAbsolute && (uri.scheme == 'https' || uri.scheme == 'http');
}
