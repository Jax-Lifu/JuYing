import 'cctv_models.dart';
import '../../domain/models/media_source.dart';
import '../../domain/models/unified_media.dart';
import '../../domain/ports/media_source_adapter.dart';
import '../../domain/ports/source_catalog_tabs.dart';
import 'cctv_repository.dart';

/// CCTV 的来源专有字段只在此处与 [CctvRepository] 之间流转。
class CctvOfficialAdapter implements MediaSourceAdapter, SourceCatalogTabs {
  CctvOfficialAdapter({required CctvRepository repository})
      : _repository = repository;

  static const sourceId = 'cctv-official';
  final CctvRepository _repository;

  @override
  MediaSource get source => const MediaSource(
        id: sourceId,
        name: 'CCTV 节目官网',
        kind: MediaSourceKind.officialWeb,
        entryUrl:
            'https://tv.cctv.com/yxg/index.shtml?spm=C28340.P2qo7O8Q1Led.EEfEAhEnQFPl.64#datacid=dhp&datafl=&datadq=&fc=%E5%8A%A8%E7%94%BB%E7%89%87&dataszm=',
        enabled: true,
        authorization: SourceAuthorization.officialEntryOnly,
        capabilities: {
          SourceCapability.browse,
          SourceCapability.search,
          SourceCapability.episodes,
          SourceCapability.officialFallback,
          SourceCapability.qualitySelection,
          SourceCapability.playbackSpeed,
          SourceCapability.volumeControl,
          SourceCapability.fullscreen,
          SourceCapability.continueWatching,
        },
      );

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) async {
    final result = await _repository.fetchPrograms(
      category: _cctvCategory(query.category),
      subcategory: _subcategoryValue(query.sourceSubcategoryId),
      page: query.page,
      pageSize: query.pageSize,
    );
    return MediaCatalogPage(
      items: result.items.map(_item).toList(growable: false),
      page: result.page,
      total: result.total,
    );
  }

  @override
  Future<List<MediaSearchHit>> search(String query) async {
    final items = await _repository.searchPrograms(query);
    return items
        .map((program) => MediaSearchHit(
              item: _item(program),
              query: query,
              matchedField: 'title',
              playable: true,
            ))
        .toList(growable: false);
  }

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) async {
    _assertSource(item.sourceId);
    final episodes = await _repository.fetchEpisodes(_program(item));
    return episodes.map(_episode).toList(growable: false);
  }

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) async {
    _assertSource(episode.sourceId);
    final playable = await _repository.resolvePlayback(CctvEpisode(
      id: episode.sourceEpisodeId,
      title: episode.title,
      officialPageUrl: episode.officialPageUri,
      imageUrl: episode.posterUri,
      brief: episode.brief,
      number: episode.episodeNumber,
    ));
    return PlaybackDescriptor(
      sourceId: sourceId,
      sourceEpisodeId: episode.sourceEpisodeId,
      title: playable.title,
      officialPageUri: playable.officialPageUri,
      nativeStreamUri: playable.streamUri,
      posterUri: playable.posterUri,
      duration: playable.duration,
      qualityOptions: playable.qualityOptions,
      httpHeaders: playable.httpHeaders,
    );
  }

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(
      MediaEpisode episode) async {
    _assertSource(episode.sourceId);
    return PlaybackDescriptor(
      sourceId: sourceId,
      sourceEpisodeId: episode.sourceEpisodeId,
      title: episode.title,
      officialPageUri: episode.officialPageUri,
      posterUri: episode.posterUri,
    );
  }

  MediaItem _item(CctvProgram program) => MediaItem(
        sourceId: sourceId,
        sourceItemId: program.id,
        title: program.title,
        category: _mediaCategory(program.category),
        officialDetailUri: program.officialPageUrl,
        defaultEpisodePageUri: program.episodePageUrl,
        posterUri: program.imageUrl,
        brief: program.brief,
        year: program.year,
        area: program.area,
        sourceCategoryLabel: program.category.label,
        sourceSubcategoryId: _subcategoryId(program.subcategory),
        sourceSubcategoryLabel: program.subcategory,
        episodeCount: program.episodeCount,
      );

  MediaEpisode _episode(CctvEpisode episode) => MediaEpisode(
        sourceId: sourceId,
        sourceEpisodeId: episode.id,
        title: episode.title,
        officialPageUri: episode.officialPageUrl,
        posterUri: episode.imageUrl,
        brief: episode.brief,
        episodeNumber: episode.number,
      );

  CctvProgram _program(MediaItem item) => CctvProgram(
        id: item.sourceItemId,
        title: item.title,
        officialPageUrl: item.officialDetailUri,
        episodePageUrl: item.defaultEpisodePageUri,
        category: _cctvCategory(item.category),
        imageUrl: item.posterUri,
        brief: item.brief,
        year: item.year,
        area: item.area,
        episodeCount: item.episodeCount,
        subcategory: _subcategoryValue(item.sourceSubcategoryId),
      );

  MediaCategory _mediaCategory(CctvCatalogCategory category) =>
      switch (category) {
        CctvCatalogCategory.animation => MediaCategory.animation,
        CctvCatalogCategory.drama => MediaCategory.drama,
        CctvCatalogCategory.documentary => MediaCategory.documentary,
        CctvCatalogCategory.special => MediaCategory.other,
      };

  CctvCatalogCategory _cctvCategory(MediaCategory category) =>
      switch (category) {
        MediaCategory.animation ||
        MediaCategory.kids =>
          CctvCatalogCategory.animation,
        MediaCategory.drama => CctvCatalogCategory.drama,
        MediaCategory.documentary => CctvCatalogCategory.documentary,
        _ => CctvCatalogCategory.special,
      };

  void _assertSource(String itemSourceId) {
    if (itemSourceId != sourceId) {
      throw ArgumentError.value(itemSourceId, 'sourceId', '来源不匹配');
    }
  }

  @override
  bool get supportsSubtabs => true;

  @override
  List<SourceCatalogTab> get primaryTabs => const [
        SourceCatalogTab(
          id: 'cctv-drama',
          label: '电视剧',
          category: MediaCategory.drama,
        ),
        SourceCatalogTab(
          id: 'cctv-animation',
          label: '动画片',
          category: MediaCategory.animation,
        ),
        SourceCatalogTab(
          id: 'cctv-documentary',
          label: '纪录片',
          category: MediaCategory.documentary,
        ),
        SourceCatalogTab(
          id: 'cctv-special',
          label: '特别节目',
          category: MediaCategory.other,
        ),
      ];

  @override
  List<SourceCatalogTab> subTabsFor(
    MediaCategory category,
    Iterable<MediaItem> items,
  ) {
    final tabs = <String, SourceCatalogTab>{};
    for (final item in items) {
      final id = item.sourceSubcategoryId;
      final label = item.sourceSubcategoryLabel;
      if (id == null || label == null || item.category != category) continue;
      tabs[id] = SourceCatalogTab(id: id, label: label, category: category);
    }
    return tabs.values.toList(growable: false);
  }

  String? _subcategoryId(String? value) =>
      value == null || value.trim().isEmpty ? null : 'cctv-sc:${value.trim()}';

  String? _subcategoryValue(String? id) =>
      id != null && id.startsWith('cctv-sc:') ? id.substring(8) : null;
}
