import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:juying_source_providers/juying_source_providers.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/spider_playback_response.dart';

/// Pure Dart adapter executing spiders ported from Java/DEX (ADR-008).
///
/// **What**: Bridges [PortedSpiderRegistry] and [PortedSpiderProvider] into the
/// [TvBoxSpiderEngine] lifecycle (categories, catalog browsing, detail, and search).
///
/// **Why**: Implements ADR-008. Over 80% of TVBox Jar crawlers follow standardized
/// CMS or REST patterns. This adapter runs them on Windows, macOS, Linux, and Android
/// TV without DEX bytecode or JVM overhead.
class PortedSpiderAdapter {
  PortedSpiderAdapter(this._dio);

  final Dio _dio;

  static bool supports(TvBoxSite site) {
    return site.type == 3 && PortedSpiderRegistry.instance.has(site.api);
  }

  Future<List<TvBoxCategory>> fetchCategories(TvBoxSite site) async {
    final provider = PortedSpiderRegistry.instance.create(
      site.api,
      httpClient: _httpClient,
      overrideHost: _extractHost(site.ext),
    );
    if (provider == null) return const <TvBoxCategory>[];

    try {
      final res = await provider.homeContent();
      final classes = res['class'];
      if (classes is List) {
        return classes
            .whereType<Map>()
            .map((m) => TvBoxCategory(
                  id: (m['type_id'] ?? '').toString(),
                  name: (m['type_name'] ?? '').toString(),
                ))
            .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      // Fallback handled gracefully
    }
    return const <TvBoxCategory>[];
  }

  Future<List<MediaItem>> fetchCategory(
    TvBoxSite site,
    String categoryId, {
    int page = 1,
  }) async {
    final provider = PortedSpiderRegistry.instance.create(
      site.api,
      httpClient: _httpClient,
      overrideHost: _extractHost(site.ext),
    );
    if (provider == null) return const <MediaItem>[];

    try {
      final res = await provider.categoryContent(categoryId, '$page');
      return _parseList(res);
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  Future<List<MediaItem>> search(TvBoxSite site, String keyword) async {
    final provider = PortedSpiderRegistry.instance.create(
      site.api,
      httpClient: _httpClient,
      overrideHost: _extractHost(site.ext),
    );
    if (provider == null) return const <MediaItem>[];

    try {
      final res = await provider.searchContent(keyword);
      return _parseList(res);
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  Future<List<PlaybackCandidate>> fetchCandidates(
    TvBoxSite site,
    MediaItem item,
  ) async {
    final provider = PortedSpiderRegistry.instance.create(
      site.api,
      httpClient: _httpClient,
      overrideHost: _extractHost(site.ext),
    );
    if (provider == null) return const <PlaybackCandidate>[];

    try {
      final res = await provider.detailContent(<String>[item.id]);
      final list = res['list'];
      if (list is! List || list.isEmpty) return const <PlaybackCandidate>[];
      final detail = list.first;
      if (detail is! Map) return const <PlaybackCandidate>[];

      final from = (detail['vod_play_from']?.toString() ?? '默认').split(r'$$$');
      final urls = (detail['vod_play_url']?.toString() ?? '').split(r'$$$');

      final candidates = <PlaybackCandidate>[];
      for (var i = 0; i < from.length; i++) {
        final lineName = from[i].trim();
        final urlGroup = i < urls.length ? urls[i] : '';
        final episodes = <PlaybackEpisode>[];
        for (final rawEp in urlGroup.split('#')) {
          final sep = rawEp.indexOf(r'$');
          final epName = sep > 0 ? rawEp.substring(0, sep).trim() : '播放';
          final epUrl =
              sep > 0 ? rawEp.substring(sep + 1).trim() : rawEp.trim();
          if (epUrl.isEmpty) continue;
          final original = PlaybackEpisode(
            name: epName.isEmpty ? '播放' : epName,
            url: epUrl,
            sortIndex: episodes.length + 1,
          );
          episodes.add(PlaybackEpisode(
            name: original.name,
            url: original.url,
            sortIndex: original.sortIndex,
            resolvePlayback: () => _resolve(site, provider, original, lineName),
          ));
        }
        if (episodes.isNotEmpty) {
          candidates.add(PlaybackCandidate(
            sourceKey: '${site.key}_$i',
            sourceName: site.name,
            lineName: lineName.isEmpty ? '线路 ${i + 1}' : lineName,
            episodes: episodes,
          ));
        }
      }
      return candidates;
    } catch (_) {
      return const <PlaybackCandidate>[];
    }
  }

  Future<PlaybackEpisode> _resolve(
    TvBoxSite site,
    PortedSpiderProvider provider,
    PlaybackEpisode episode,
    String flag,
  ) async {
    Map<String, dynamic> playerRes;
    try {
      playerRes = await provider.playerContent(flag, episode.url);
    } catch (_) {
      playerRes = <String, dynamic>{
        'parse': 0,
        'url': episode.url,
      };
    }
    return resolveSpiderPlayback(
      site: site,
      episode: episode,
      response: playerRes,
      dio: _dio,
    );
  }

  Future<String> _httpClient(String url, {Map<String, String>? headers}) async {
    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    return response.data ?? '';
  }

  List<MediaItem> _parseList(Map<String, dynamic> res) {
    final list = res['list'];
    if (list is! List) return const <MediaItem>[];
    return list
        .whereType<Map>()
        .map((m) => MediaItem(
              id: (m['vod_id'] ?? '').toString(),
              title: (m['vod_name'] ?? '未知').toString(),
              posterUrl: m['vod_pic']?.toString(),
              overview: m['vod_remarks']?.toString(),
              year: m['vod_year']?.toString(),
            ))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  static String? _extractHost(Object? ext) {
    if (ext == null) return null;
    if (ext is String) {
      final trimmed = ext.trim();
      if (trimmed.startsWith('http')) {
        final uri =
            Uri.tryParse(trimmed.split(r'$$$').first.split('###').first.trim());
        if (uri != null && uri.host.isNotEmpty) {
          return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
        }
      }
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          final map = jsonDecode(trimmed);
          if (map is Map) {
            final host = map['host'] ?? map['site'] ?? map['url'] ?? map['api'];
            if (host is String && host.startsWith('http')) {
              final uri = Uri.tryParse(host);
              if (uri != null && uri.host.isNotEmpty) {
                return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
              }
            }
          }
        } catch (_) {}
      }
    } else if (ext is Map) {
      final host = ext['host'] ?? ext['site'] ?? ext['url'] ?? ext['api'];
      if (host is String && host.startsWith('http')) {
        final uri = Uri.tryParse(host);
        if (uri != null && uri.host.isNotEmpty) {
          return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
        }
      }
    }
    return null;
  }
}
