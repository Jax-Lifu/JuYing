import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/spider_playback_response.dart';

/// 标准 TVBox type=4 HTTP Spider 的跨平台客户端。
///
/// type=4 是远端 CatVod 协议而非“央视”编号。把生命周期调用收敛为普通 HTTP
/// 请求，既覆盖桌面和移动端，也不需要执行远端 JAR、JS 或 Python 代码。
class T4HttpSpiderAdapter {
  T4HttpSpiderAdapter(this._dio);

  final Dio _dio;

  static bool supports(TvBoxSite site) =>
      site.type == 4 && site.key != 'cctv_vod' && site.api.startsWith('http');

  Future<List<TvBoxCategory>> fetchCategories(TvBoxSite site) async {
    final root = await _request(site, <String, dynamic>{'filter': 'true'});
    final classes = root['class'];
    if (classes is! List) return const <TvBoxCategory>[];
    return classes
        .whereType<Map>()
        .map((item) => TvBoxCategory.fromJson(Map<String, dynamic>.from(item)))
        .where((category) => category.id.isNotEmpty && category.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<MediaItem>> fetchCategory(
    TvBoxSite site,
    String categoryId, {
    int page = 1,
  }) async {
    final root = await _request(site, <String, dynamic>{
      'ac': 'detail',
      't': categoryId,
      'pg': page,
      // FongMi/CatVod 约定筛选 ext 是 URL-safe Base64 JSON；与站点 extend 分离。
      'ext': base64Url.encode(utf8.encode('{}')).replaceAll('=', ''),
    });
    return _parseMedia(root);
  }

  Future<List<MediaItem>> search(
    TvBoxSite site,
    String keyword, {
    int page = 1,
  }) async {
    final root = await _request(site, <String, dynamic>{
      'wd': keyword,
      'quick': 'false',
      'pg': page,
    });
    return _parseMedia(root);
  }

  Future<List<PlaybackCandidate>> fetchCandidates(
    TvBoxSite site,
    MediaItem item,
  ) async {
    final root = await _request(site, <String, dynamic>{
      'ac': 'detail',
      'ids': item.id,
    });
    final list = root['list'];
    if (list is! List || list.isEmpty || list.first is! Map) {
      return const <PlaybackCandidate>[];
    }
    final detail = Map<String, dynamic>.from(list.first as Map);
    final flags = (detail['vod_play_from']?.toString() ?? '').split(r'$$$');
    final groups = (detail['vod_play_url']?.toString() ?? '').split(r'$$$');
    final candidates = <PlaybackCandidate>[];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final flag = groupIndex < flags.length && flags[groupIndex].isNotEmpty
          ? flags[groupIndex]
          : '线路 ${groupIndex + 1}';
      final episodes = <PlaybackEpisode>[];
      for (final rawEpisode in groups[groupIndex].split('#')) {
        final separator = rawEpisode.indexOf(r'$');
        final name =
            separator > 0 ? rawEpisode.substring(0, separator).trim() : '播放';
        final playId = separator > 0
            ? rawEpisode.substring(separator + 1).trim()
            : rawEpisode.trim();
        if (playId.isEmpty) continue;
        final episode = PlaybackEpisode(
          name: name.isEmpty ? '播放' : name,
          url: playId,
          sortIndex: episodes.length + 1,
        );
        episodes.add(
          PlaybackEpisode(
            name: episode.name,
            url: episode.url,
            sortIndex: episode.sortIndex,
            // HTTP episode IDs may be web pages and still require playerContent.
            resolvePlayback: () => _resolvePlayback(site, flag, episode),
          ),
        );
      }
      if (episodes.isNotEmpty) {
        candidates.add(
          PlaybackCandidate(
            sourceKey: '${site.key}_$groupIndex',
            sourceName: site.name,
            lineName: flag,
            episodes: episodes,
          ),
        );
      }
    }
    return candidates;
  }

  Future<PlaybackEpisode> _resolvePlayback(
    TvBoxSite site,
    String flag,
    PlaybackEpisode episode,
  ) async {
    final root = await _request(site, <String, dynamic>{
      'play': episode.url,
      'flag': flag,
    });
    return resolveSpiderPlayback(
      site: site,
      episode: episode,
      response: {'flag': flag, ...root},
      dio: _dio,
    );
  }

  Future<Map<String, dynamic>> _request(
    TvBoxSite site,
    Map<String, dynamic> query,
  ) async {
    final extend = site.ext is String
        ? site.ext as String
        : site.ext == null
            ? ''
            : json.encode(site.ext);
    final response = await _dio.get<dynamic>(
      site.api,
      queryParameters: <String, dynamic>{
        ...query,
        if (extend.isNotEmpty) 'extend': extend,
      },
      // Some servers label an error page as JSON. Parse after HTTP completion
      // so that malformed payloads remain protocol errors rather than Dio's
      // opaque "unknown" transport failure.
      options: Options(
        responseType: ResponseType.plain,
        headers: const <String, String>{'User-Agent': 'okhttp/3.15'},
      ),
    );
    final value = response.data;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      final decoded = json.decode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException('T4 Spider 没有返回 JSON 对象');
  }

  static List<MediaItem> _parseMedia(Map<String, dynamic> root) {
    final list = root['list'];
    if (list is! List) return const <MediaItem>[];
    return list
        .whereType<Map>()
        .map((raw) {
          final item = Map<String, dynamic>.from(raw);
          return MediaItem(
            id: item['vod_id']?.toString() ?? '',
            title: item['vod_name']?.toString() ?? '未知节目',
            posterUrl: item['vod_pic']?.toString(),
            overview: item['vod_content']?.toString() ??
                item['vod_remarks']?.toString(),
            year: item['vod_year']?.toString(),
            genres: (item['vod_tag']?.toString() ?? '')
                .split(',')
                .where((value) => value.trim().isNotEmpty)
                .toList(growable: false),
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }
}
