import 'dart:async';

import 'package:http/http.dart' as http;

import '../../domain/models/media_source.dart';
import '../../domain/models/playable_media.dart';
import '../../domain/models/playlist_source.dart';
import '../../domain/models/unified_media.dart';
import '../../domain/ports/media_source_adapter.dart';
import '../../domain/ports/source_catalog_tabs.dart';
import '../network/safe_text_response_decoder.dart';
import 'live_channel_sorter.dart';
import 'm3u_playlist_parser.dart';

class M3uPlaylistAdapter implements MediaSourceAdapter, SourceCatalogTabs {
  M3uPlaylistAdapter({
    required PlaylistSourceDefinition definition,
    http.Client? client,
  })  : _definition = definition,
        _client = client ?? http.Client();

  static const maxPlaylistBytes = 32 * 1024 * 1024;
  static const playlistRequestTimeout = Duration(seconds: 12);

  final PlaylistSourceDefinition _definition;
  final http.Client _client;
  List<M3uChannel>? _channels;

  @override
  MediaSource get source => MediaSource(
        id: _definition.id,
        name: _definition.name,
        kind: MediaSourceKind.custom,
        entryUrl: _definition.playlistUri.toString(),
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
        },
      );

  @override
  bool get supportsSubtabs => true;

  @override
  List<SourceCatalogTab> get primaryTabs => const [
        SourceCatalogTab(
          id: 'live',
          label: '直播',
          category: MediaCategory.live,
        ),
      ];

  @override
  List<SourceCatalogTab> subTabsFor(
    MediaCategory category,
    Iterable<MediaItem> items,
  ) {
    if (category != MediaCategory.live) return const [];
    final groups = <String>{};
    final result = <SourceCatalogTab>[];
    for (final item in items) {
      final label = item.sourceCategoryLabel;
      if (label != null && label.isNotEmpty && groups.add(label)) {
        result.add(SourceCatalogTab(
          id: label,
          label: label,
          category: MediaCategory.live,
        ));
      }
    }
    return result;
  }

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) async {
    if (query.category != MediaCategory.live) {
      return MediaCatalogPage(items: const [], page: query.page, total: 0);
    }
    final all = await _load();
    final filtered = query.sourceSubcategoryId == null
        ? all
        : all
            .where((channel) => channel.group == query.sourceSubcategoryId)
            .toList(growable: false);
    final sorted = LiveChannelSorter.sort(filtered);
    final start = (query.page - 1) * query.pageSize;
    final items = start >= sorted.length || start < 0
        ? const <MediaItem>[]
        : sorted
            .skip(start)
            .take(query.pageSize)
            .map((channel) => MediaItem(
                  sourceId: source.id,
                  sourceItemId: channel.id,
                  title: channel.name,
                  category: MediaCategory.live,
                  sourceCategoryLabel: channel.group,
                  posterUri: channel.logoUri,
                  defaultEpisodePageUri:
                      channel.officialPageUri ?? channel.streamUri,
                  officialDetailUri:
                      channel.officialPageUri ?? channel.streamUri,
                  brief: channel.channelNumber != null &&
                          channel.channelNumber!.isNotEmpty
                      ? '频道 ${channel.channelNumber}'
                      : null,
                ))
            .toList(growable: false);

    return MediaCatalogPage(
      items: items,
      page: query.page,
      total: sorted.length,
    );
  }

  @override
  Future<List<MediaSearchHit>> search(String query) async {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return const [];
    final all = await _load();
    final hits = <MediaSearchHit>[];
    for (final channel in all) {
      final inName = channel.name.toLowerCase().contains(term);
      final inGroup = channel.group?.toLowerCase().contains(term) ?? false;
      if (inName || inGroup) {
        hits.add(MediaSearchHit(
          item: MediaItem(
            sourceId: source.id,
            sourceItemId: channel.id,
            title: channel.name,
            category: MediaCategory.live,
            sourceCategoryLabel: channel.group,
            posterUri: channel.logoUri,
            defaultEpisodePageUri:
                channel.officialPageUri ?? channel.streamUri,
            officialDetailUri: channel.officialPageUri ?? channel.streamUri,
            brief: channel.channelNumber != null &&
                    channel.channelNumber!.isNotEmpty
                ? '频道 ${channel.channelNumber}'
                : null,
          ),
          query: query,
          matchedField: inName ? 'title' : 'category',
          relevance: inName ? 1.0 : 0.8,
          playable: true,
        ));
      }
    }
    return hits;
  }

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) async {
    final channels = await _load();
    final channel = channels
        .where((candidate) => candidate.id == item.sourceItemId)
        .firstOrNull;
    return [
      MediaEpisode(
        sourceId: source.id,
        sourceEpisodeId: channel?.id ?? item.sourceItemId,
        title: channel?.name ?? item.title,
        officialPageUri: channel?.officialPageUri ??
            channel?.streamUri ??
            item.officialDetailUri,
      ),
    ];
  }

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) async {
    final channels = await _load();
    final channel = channels
        .where((candidate) => candidate.id == episode.sourceEpisodeId)
        .firstOrNull;
    if (channel == null) {
      throw StateError('未找到对应的频道');
    }
    final uris = [channel.streamUri, ...channel.alternateStreamUris];
    final headers = [channel.httpHeaders, ...channel.alternateHttpHeaders];
    final qualityOptions = <PlaybackQuality>[];
    for (var i = 0; i < uris.length; i++) {
      final label =
          i < channel.lineLabels.length && channel.lineLabels[i].isNotEmpty
              ? channel.lineLabels[i]
              : '线路 ${i + 1}';
      final h = i < headers.length ? headers[i] : channel.httpHeaders;
      qualityOptions.add(PlaybackQuality(
        id: 'line-$i',
        label: label,
        streamUri: uris[i],
        httpHeaders: h,
      ));
    }
    return PlaybackDescriptor(
      sourceId: source.id,
      sourceEpisodeId: channel.id,
      title: channel.name,
      nativeStreamUri: channel.streamUri,
      officialPageUri: channel.officialPageUri ?? channel.streamUri,
      httpHeaders: channel.httpHeaders,
      qualityOptions: qualityOptions,
    );
  }

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(
      MediaEpisode episode) async {
    final channels = await _load();
    final channel = channels
        .where((candidate) => candidate.id == episode.sourceEpisodeId)
        .firstOrNull;
    if (channel?.officialPageUri != null) {
      return PlaybackDescriptor(
        sourceId: source.id,
        sourceEpisodeId: channel!.id,
        title: channel.name,
        officialPageUri: channel.officialPageUri!,
      );
    }
    throw StateError('此频道不支持官网回退');
  }

  Future<List<M3uChannel>> _load() async {
    final cached = _channels;
    if (cached != null) return cached;
    const headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    };
    http.Response response;
    var attempts = 0;
    while (true) {
      attempts++;
      response = await _client
          .get(_definition.playlistUri, headers: headers)
          .timeout(playlistRequestTimeout);
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
      throw StateError('清单请求失败（HTTP ${response.statusCode}）');
    }
    if (response.bodyBytes.length > maxPlaylistBytes) {
      throw StateError('清单超过 32 MiB 安全上限');
    }
    final text = await SafeTextResponseDecoder.decode(
      response.bodyBytes,
      maxDecodedBytes: maxPlaylistBytes,
      contentEncoding: response.headers['content-encoding'],
    );
    final parsed = M3uPlaylistParser.parse(
      text,
      baseUri: _definition.playlistUri,
    );
    if (parsed.isEmpty) throw StateError('清单没有可用的公开 HTTP(S) 频道');
    return _channels = parsed;
  }
}
