import 'dart:async';

import 'package:http/http.dart' as http;

import '../../domain/models/media_source.dart';
import '../../domain/models/tvbox_source.dart';
import '../../domain/models/unified_media.dart';
import '../../domain/ports/catalog_initial_category.dart';
import '../../domain/ports/media_source_adapter.dart';
import '../../domain/ports/source_catalog_scopes.dart';
import '../../domain/ports/source_catalog_tabs.dart';
import '../network/safe_text_response_decoder.dart';
import 'tvbox_config_parser.dart';
import 'tvbox_javascript_runtime.dart';
import 'tvbox_javascript_site_adapter.dart';
import 'tvbox_live_adapter.dart';
import 'tvbox_playback_resolver.dart';
import 'tvbox_site_adapter.dart';
import 'tvbox_standard_site_adapter.dart';

class _ConfiguredSite {
  const _ConfiguredSite({
    required this.id,
    required this.label,
    required this.siteKey,
    required this.adapter,
  });

  final String id;
  final String label;
  final String siteKey;
  final TvboxSiteAdapter adapter;
}

class TvboxConfigAdapter
    implements
        MediaSourceAdapter,
        SourceCatalogScopes,
        CatalogInitialCategory,
        SourceCatalogTabs {
  TvboxConfigAdapter({
    required TvboxSourceDefinition definition,
    http.Client? client,
    MediaCategory? initialCategory,
  })  : _definition = definition,
        _client = client ?? http.Client(),
        _preferredInitialCategory = initialCategory;

  static const maxConfigBytes = 4 * 1024 * 1024;

  final TvboxSourceDefinition _definition;
  final http.Client _client;
  final MediaCategory? _preferredInitialCategory;

  TvboxLiveAdapter? _liveAdapter;
  final List<_ConfiguredSite> _sites = [];
  String? _selectedScopeId;
  final Map<String, Set<String>> _availableScopeIdsByCategory = {};
  bool _initialized = false;
  bool _liveAvailable = false;

  @override
  MediaSource get source => MediaSource(
        id: _definition.id,
        name: _definition.name,
        kind: MediaSourceKind.custom,
        entryUrl: _definition.configUri.toString(),
        enabled: _definition.enabled,
        authorization: SourceAuthorization.userOwned,
        capabilities: const {
          SourceCapability.browse,
          SourceCapability.liveCatalog,
          SourceCapability.search,
          SourceCapability.episodes,
          SourceCapability.nativePublicPlayback,
          SourceCapability.qualitySelection,
          SourceCapability.volumeControl,
          SourceCapability.fullscreen,
          SourceCapability.officialFallback,
        },
      );

  @override
  MediaCategory get initialCatalogCategory {
    if (_preferredInitialCategory != null) return _preferredInitialCategory;
    if (_liveAvailable) return MediaCategory.live;
    if (_sites.isNotEmpty) return MediaCategory.movie;
    return MediaCategory.live;
  }

  @override
  bool get supportsSubtabs => true;

  @override
  List<SourceCatalogTab> get primaryTabs {
    final tabs = <SourceCatalogTab>[];
    if (_liveAvailable || _liveAdapter != null) {
      tabs.add(const SourceCatalogTab(
        id: 'live',
        label: '直播',
        category: MediaCategory.live,
      ));
    }
    if (_sites.isNotEmpty) {
      tabs.addAll(const [
        SourceCatalogTab(
          id: 'movie',
          label: '电影',
          category: MediaCategory.movie,
        ),
        SourceCatalogTab(
          id: 'drama',
          label: '电视剧',
          category: MediaCategory.drama,
        ),
        SourceCatalogTab(
          id: 'animation',
          label: '动漫',
          category: MediaCategory.animation,
        ),
        SourceCatalogTab(
          id: 'variety',
          label: '综艺',
          category: MediaCategory.variety,
        ),
        SourceCatalogTab(
          id: 'documentary',
          label: '纪录片',
          category: MediaCategory.documentary,
        ),
      ]);
    }
    return tabs;
  }

  @override
  List<SourceCatalogTab> subTabsFor(
    MediaCategory category,
    Iterable<MediaItem> items,
  ) {
    if (category == MediaCategory.live) {
      return _liveAdapter?.subTabsFor(category, items) ?? const [];
    }
    final active = _activeSiteAdapter;
    if (active is SourceCatalogTabs) {
      return (active as SourceCatalogTabs).subTabsFor(category, items);
    }
    return const [];
  }

  @override
  String? get selectedCatalogScopeId => _selectedScopeId;

  @override
  Future<List<SourceCatalogScope>> catalogScopes() async {
    await _ensureInitialized();
    return _sites
        .map((site) => SourceCatalogScope(
              id: site.id,
              label: site.label,
              sourceKey: site.siteKey,
              categories: const {
                MediaCategory.movie,
                MediaCategory.drama,
                MediaCategory.animation,
                MediaCategory.variety,
                MediaCategory.documentary,
                MediaCategory.other,
              },
            ))
        .toList(growable: false);
  }

  @override
  Future<Set<String>> availableCatalogScopeIds({
    required MediaCategory category,
    bool refresh = false,
  }) async {
    await _ensureInitialized();
    if (category == MediaCategory.live) {
      return const {};
    }
    if (!refresh &&
        _availableScopeIdsByCategory.containsKey(category.name)) {
      return _availableScopeIdsByCategory[category.name]!;
    }
    final available = <String>{};
    for (final site in _sites) {
      try {
        final result = await site.adapter.browse(MediaCatalogQuery(
          category: category,
          page: 1,
          pageSize: 2,
        ));
        if (result.items.isNotEmpty || result.total > 0) {
          available.add(site.id);
        }
      } catch (_) {}
    }
    _availableScopeIdsByCategory[category.name] = available;
    return available;
  }

  @override
  Future<void> selectCatalogScope(String? id) async {
    await _ensureInitialized();
    _selectedScopeId = id;
  }

  Future<void> validate() async {
    await _ensureInitialized(force: true);
  }

  TvboxSiteAdapter? get _activeSiteAdapter {
    if (_sites.isEmpty) return null;
    if (_selectedScopeId != null) {
      final matched = _sites
          .where((site) => site.id == _selectedScopeId)
          .map((site) => site.adapter)
          .firstOrNull;
      if (matched != null) return matched;
    }
    return _sites.first.adapter;
  }

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) async {
    await _ensureInitialized();
    if (query.category == MediaCategory.live) {
      if (_liveAdapter == null) {
        return MediaCatalogPage(items: const [], page: query.page, total: 0);
      }
      final page = await _liveAdapter!.browse(query);
      return MediaCatalogPage(
        items: page.items
            .map((item) => _mapItem(item, sourceId: _definition.id))
            .toList(growable: false),
        page: page.page,
        total: page.total,
      );
    }

    final site = _activeSiteAdapter;
    if (site == null) {
      return MediaCatalogPage(items: const [], page: query.page, total: 0);
    }
    final page = await site.browse(query);
    return MediaCatalogPage(
      items: page.items
          .map((item) => _mapItem(
                item,
                sourceId: _definition.id,
              ))
          .toList(growable: false),
      page: page.page,
      total: page.total,
    );
  }

  @override
  Future<List<MediaSearchHit>> search(String query) async {
    await _ensureInitialized();
    final term = query.trim();
    if (term.isEmpty) return const [];
    final hits = <MediaSearchHit>[];

    if (_liveAdapter != null) {
      try {
        final liveHits = await _liveAdapter!.search(term);
        hits.addAll(liveHits.map((hit) => MediaSearchHit(
              item: _mapItem(hit.item, sourceId: _definition.id),
              query: hit.query,
              matchedField: hit.matchedField,
              relevance: hit.relevance,
              playable: hit.playable,
            )));
      } catch (_) {}
    }

    final site = _activeSiteAdapter;
    if (site != null) {
      try {
        final siteHits = await site.search(term);
        hits.addAll(siteHits.map((hit) => MediaSearchHit(
              item: _mapItem(
                hit.item,
                sourceId: _definition.id,
              ),
              query: hit.query,
              matchedField: hit.matchedField,
              relevance: hit.relevance,
              playable: hit.playable,
            )));
      } catch (_) {}
    }

    return hits;
  }

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) async {
    await _ensureInitialized();
    if (item.category == MediaCategory.live ||
        !item.sourceItemId.contains('::')) {
      if (_liveAdapter != null) {
        final eps = await _liveAdapter!.episodes(item);
        return eps
            .map((ep) => _mapEpisode(ep, sourceId: _definition.id))
            .toList(growable: false);
      }
      return [
        MediaEpisode(
          sourceId: _definition.id,
          sourceEpisodeId: item.sourceItemId,
          title: item.title,
          officialPageUri: item.officialDetailUri,
        ),
      ];
    }

    final parts = item.sourceItemId.split('::');
    final siteKey = parts.first;
    final siteAdapter = _sites
        .where((site) => site.siteKey == siteKey)
        .map((site) => site.adapter)
        .firstOrNull;
    if (siteAdapter == null) {
      throw StateError('未找到站点：$siteKey');
    }
    final eps = await siteAdapter.episodes(item);
    return eps
        .map((ep) => _mapEpisode(
              ep,
              sourceId: _definition.id,
            ))
        .toList(growable: false);
  }

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) async {
    await _ensureInitialized();
    if (!episode.sourceEpisodeId.contains('::')) {
      if (_liveAdapter != null) {
        final descriptor = await _liveAdapter!.resolvePlayback(episode);
        return _mapDescriptor(descriptor, sourceId: _definition.id);
      }
      throw StateError('未找到直播播放描述符');
    }

    final parts = episode.sourceEpisodeId.split('::');
    final siteKey = parts.first;
    final siteAdapter = _sites
        .where((site) => site.siteKey == siteKey)
        .map((site) => site.adapter)
        .firstOrNull;
    if (siteAdapter == null) {
      throw StateError('未找到站点：$siteKey');
    }
    final descriptor = await siteAdapter.resolvePlayback(episode);
    return _mapDescriptor(
      descriptor,
      sourceId: _definition.id,
    );
  }

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(
      MediaEpisode episode) async {
    await _ensureInitialized();
    if (!episode.sourceEpisodeId.contains('::')) {
      if (_liveAdapter != null) {
        final descriptor =
            await _liveAdapter!.resolveOfficialFallback(episode);
        return _mapDescriptor(descriptor, sourceId: _definition.id);
      }
      throw StateError('未找到官方回退');
    }

    final parts = episode.sourceEpisodeId.split('::');
    final siteKey = parts.first;
    final siteAdapter = _sites
        .where((site) => site.siteKey == siteKey)
        .map((site) => site.adapter)
        .firstOrNull;
    if (siteAdapter == null) {
      throw StateError('未找到站点：$siteKey');
    }
    final descriptor =
        await siteAdapter.resolveOfficialFallback(episode);
    return _mapDescriptor(
      descriptor,
      sourceId: _definition.id,
    );
  }

  MediaItem _mapItem(
    MediaItem item, {
    required String sourceId,
    String? sourceItemId,
  }) =>
      MediaItem(
        sourceId: sourceId,
        sourceItemId: sourceItemId ?? item.sourceItemId,
        title: item.title,
        category: item.category,
        officialDetailUri: item.officialDetailUri,
        defaultEpisodePageUri: item.defaultEpisodePageUri,
        posterUri: item.posterUri,
        brief: item.brief,
        year: item.year,
        area: item.area,
        sourceCategoryLabel: item.sourceCategoryLabel,
        sourceSubcategoryId: item.sourceSubcategoryId,
        sourceSubcategoryLabel: item.sourceSubcategoryLabel,
        episodeCount: item.episodeCount,
        workIdentity: item.workIdentity,
      );

  MediaEpisode _mapEpisode(
    MediaEpisode ep, {
    required String sourceId,
    String? sourceEpisodeId,
  }) =>
      MediaEpisode(
        sourceId: sourceId,
        sourceEpisodeId: sourceEpisodeId ?? ep.sourceEpisodeId,
        title: ep.title,
        officialPageUri: ep.officialPageUri,
        posterUri: ep.posterUri,
        brief: ep.brief,
        seasonNumber: ep.seasonNumber,
        episodeNumber: ep.episodeNumber,
        isSpecial: ep.isSpecial,
      );

  PlaybackDescriptor _mapDescriptor(
    PlaybackDescriptor desc, {
    required String sourceId,
    String? sourceEpisodeId,
  }) =>
      PlaybackDescriptor(
        sourceId: sourceId,
        sourceEpisodeId: sourceEpisodeId ?? desc.sourceEpisodeId,
        title: desc.title,
        officialPageUri: desc.officialPageUri,
        nativeStreamUri: desc.nativeStreamUri,
        expiresAt: desc.expiresAt,
        posterUri: desc.posterUri,
        duration: desc.duration,
        qualityOptions: desc.qualityOptions,
        httpHeaders: desc.httpHeaders,
      );

  Future<void> _ensureInitialized({bool force = false}) async {
    if (_initialized && !force) return;
    final configText = await _fetchConfig(_definition.configUri);
    final baseUri = _definition.configUri;

    // 1. Live entry
    final directLives = TvboxConfigParser.parseDirectLives(
      configText,
      baseUri: baseUri,
    );
    if (directLives.isNotEmpty) {
      _liveAdapter = TvboxLiveAdapter(
        definition: _definition,
        client: _client,
      );
      try {
        final liveResult = await _liveAdapter!.browse(
          const MediaCatalogQuery(category: MediaCategory.live, pageSize: 1),
        );
        _liveAvailable = liveResult.items.isNotEmpty || liveResult.total > 0;
      } catch (_) {
        _liveAvailable = false;
      }
    }

    // 2. Parsers
    final playbackParsers = TvboxConfigParser.parsePlaybackParsers(
      configText,
      baseUri: baseUri,
    );
    final playbackResolver = playbackParsers.isEmpty
        ? null
        : TvboxPlaybackResolver(
            parsers: playbackParsers,
            client: _client,
          );

    // 3. Repositories (Multi-warehouse)
    final repos = TvboxConfigParser.parseRepositories(
      configText,
      baseUri: baseUri,
    );
    _sites.clear();

    if (repos.isNotEmpty) {
      for (final repo in repos.take(10)) {
        try {
          final subConfigText = await _fetchConfig(repo.configUri);
          final subBaseUri = repo.configUri;
          final standardSites = TvboxConfigParser.parseStandardSites(
            subConfigText,
            baseUri: subBaseUri,
          );
          for (final site in standardSites) {
            final adapter = TvboxStandardSiteAdapter(
              sourceId: _definition.id,
              site: site,
              client: _client,
              fallbackUri: subBaseUri,
              playbackResolver: playbackResolver,
            );
            _sites.add(_ConfiguredSite(
              id: '${repo.name} · ${site.key}',
              label: '${repo.name} · ${site.name}',
              siteKey: site.key,
              adapter: adapter,
            ));
          }
        } catch (_) {}
      }
    } else {
      // Standard sites
      final standardSites = TvboxConfigParser.parseStandardSites(
        configText,
        baseUri: baseUri,
      );
      for (final site in standardSites) {
        final adapter = TvboxStandardSiteAdapter(
          sourceId: _definition.id,
          site: site,
          client: _client,
          fallbackUri: baseUri,
          playbackResolver: playbackResolver,
        );
        _sites.add(_ConfiguredSite(
          id: site.key,
          label: site.name,
          siteKey: site.key,
          adapter: adapter,
        ));
      }

      // JS sites
      final jsSites = TvboxConfigParser.parseJavascriptSites(
        configText,
        baseUri: baseUri,
      );
      if (jsSites.isNotEmpty) {
        final jsRuntime = ProcessTvboxJavascriptRuntime();
        for (final site in jsSites) {
          final adapter = TvboxJavascriptSiteAdapter(
            sourceId: _definition.id,
            site: site,
            runtime: jsRuntime,
            fallbackUri: baseUri,
            playbackResolver: playbackResolver,
          );
          _sites.add(_ConfiguredSite(
            id: site.key,
            label: site.name,
            siteKey: site.key,
            adapter: adapter,
          ));
        }
      }
    }

    if (_sites.isEmpty && _liveAdapter == null) {
      throw StateError('TVBox 配置中没有可用的标准站点或直播清单');
    }
    _initialized = true;
  }

  Future<String> _fetchConfig(Uri uri) async {
    const headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    };
    http.Response response;
    var attempts = 0;
    while (true) {
      attempts++;
      response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if ((response.statusCode == 502 ||
              response.statusCode == 503 ||
              response.statusCode == 504 ||
              response.statusCode == 429) &&
          attempts < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        continue;
      }
      break;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('配置请求失败（HTTP ${response.statusCode}）');
    }
    if (response.bodyBytes.length > maxConfigBytes) {
      throw StateError('配置超过安全上限');
    }
    return SafeTextResponseDecoder.decode(
      response.bodyBytes,
      maxDecodedBytes: maxConfigBytes,
      contentEncoding: response.headers['content-encoding'],
    );
  }
}
