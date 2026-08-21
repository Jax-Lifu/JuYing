import 'dart:async';

import 'package:http/http.dart' as http;

import '../../domain/models/live_program.dart';
import '../../domain/models/media_source.dart';
import '../../domain/models/playable_media.dart';
import '../../domain/models/tvbox_source.dart';
import '../../domain/models/unified_media.dart';
import '../../domain/ports/live_program_guide.dart';
import '../../domain/ports/media_source_adapter.dart';
import '../../domain/ports/source_catalog_tabs.dart';
import '../network/safe_text_response_decoder.dart';
import '../playlist/live_channel_sorter.dart';
import '../playlist/m3u_playlist_parser.dart';
import 'tvbox_config_parser.dart';
import 'tvbox_live_playlist_parser.dart';
import 'xmltv_program_parser.dart';

class _ChannelEntry {
  const _ChannelEntry({
    required this.channel,
    this.epgUri,
  });

  final M3uChannel channel;
  final String? epgUri;
}

class TvboxLiveAdapter
    implements MediaSourceAdapter, LiveProgramGuide, SourceCatalogTabs {
  TvboxLiveAdapter({
    required TvboxSourceDefinition definition,
    http.Client? client,
  })  : _definition = definition,
        _client = client ?? http.Client();

  static const maxConfigBytes = 4 * 1024 * 1024;
  static const maxPlaylistBytes = 32 * 1024 * 1024;
  static const maxEpgBytes = 32 * 1024 * 1024;

  final TvboxSourceDefinition _definition;
  final http.Client _client;
  List<_ChannelEntry>? _entries;
  final Map<String, (DateTime, String)> _epgCache = {};

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
          SourceCapability.liveProgramGuide,
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
    final channels = all.map((entry) => entry.channel).toList(growable: false);
    final filtered = query.sourceSubcategoryId == null
        ? channels
        : channels
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
    for (final entry in all) {
      final channel = entry.channel;
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
    final all = await _load();
    final entry = all
        .where((candidate) => candidate.channel.id == item.sourceItemId)
        .firstOrNull;
    final channel = entry?.channel;
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
    final all = await _load();
    final entry = all
        .where((candidate) => candidate.channel.id == episode.sourceEpisodeId)
        .firstOrNull;
    if (entry == null) {
      throw StateError('未找到对应的频道');
    }
    final channel = entry.channel;
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
    final all = await _load();
    final entry = all
        .where((candidate) => candidate.channel.id == episode.sourceEpisodeId)
        .firstOrNull;
    final channel = entry?.channel;
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

  @override
  Future<List<LiveProgram>> programGuide(
    MediaItem item, {
    DateTime? now,
  }) async {
    final all = await _load();
    final entry = all
        .where((candidate) => candidate.channel.id == item.sourceItemId)
        .firstOrNull;
    if (entry == null || entry.epgUri == null) return const [];
    final epgUrl = entry.epgUri!;
    final xml = await _loadEpgXml(epgUrl);
    if (xml.isEmpty) return const [];
    final channelId = entry.channel.epgChannelId ?? entry.channel.name;
    return XmltvProgramParser.parse(
      xml,
      sourceId: source.id,
      sourceItemId: item.sourceItemId,
      channelId: channelId,
    );
  }

  Future<String> _loadEpgXml(String epgUrl) async {
    final cached = _epgCache[epgUrl];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(hours: 1)) {
      return cached.$2;
    }
    try {
      final uri = Uri.parse(epgUrl);
      final text = await _getText(uri, maxEpgBytes, 'EPG');
      _epgCache[epgUrl] = (DateTime.now(), text);
      return text;
    } catch (_) {
      return '';
    }
  }

  Future<List<_ChannelEntry>> _load() async {
    final cached = _entries;
    if (cached != null) return cached;
    final configText = await _getText(
      _definition.configUri,
      maxConfigBytes,
      '配置',
    );
    final lives = TvboxConfigParser.parseDirectLives(
      configText,
      baseUri: _definition.configUri,
    );
    if (lives.isEmpty) {
      return _entries = const [];
    }

    final entries = <_ChannelEntry>[];
    for (final live in lives) {
      try {
        final playlistText = live.inlinePlaylist ??
            await _getText(
              live.playlistUri!,
              maxPlaylistBytes,
              '直播清单',
              headers: live.httpHeaders,
            );
        final channels = TvboxLivePlaylistParser.parse(
          playlistText,
          baseUri: live.playlistUri ?? _definition.configUri,
          defaultHeaders: live.httpHeaders,
        );
        for (final channel in channels) {
          entries.add(_ChannelEntry(
            channel: channel,
            epgUri: live.epgTemplate,
          ));
        }
      } catch (_) {}
    }
    return _entries = entries;
  }

  Future<String> _getText(
    Uri uri,
    int maxBytes,
    String label, {
    Duration timeout = const Duration(seconds: 10),
    Map<String, String> headers = const {},
  }) async {
    final effectiveHeaders = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      ...headers,
    };
    http.Response response;
    var attempts = 0;
    while (true) {
      attempts++;
      response = await _client
          .get(uri, headers: effectiveHeaders)
          .timeout(timeout);
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
      throw StateError('$label请求失败（HTTP ${response.statusCode}）');
    }
    if (response.bodyBytes.length > maxBytes) {
      throw StateError('$label超过安全上限');
    }
    return SafeTextResponseDecoder.decode(
      response.bodyBytes,
      maxDecodedBytes: maxBytes,
      contentEncoding: response.headers['content-encoding'],
    );
  }
}
