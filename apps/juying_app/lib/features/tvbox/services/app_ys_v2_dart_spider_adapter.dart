import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/spider_playback_response.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_runtime_capability.dart';

/// Cross-platform implementation of the common `csp_AppYsV2` App API family.
///
/// Many TVBox repositories package identical HTTP contracts in a Dex class.
/// Reimplementing that stable contract in Dart removes the Android dependency
/// while keeping source-specific endpoints in the subscription `ext` field.
class AppYsV2DartSpiderAdapter {
  AppYsV2DartSpiderAdapter(this._dio);

  final Dio _dio;

  static bool supports(TvBoxSite site) =>
      site.type == 3 &&
      TvBoxSpiderRuntimeCapability.supportsAppApi(api: site.api, ext: site.ext);

  Future<List<TvBoxCategory>> fetchCategories(TvBoxSite site) async {
    final root = await _get('${_baseUrl(site)}nav?token=');
    return _dataList(root)
        .map((item) => TvBoxCategory.fromJson(item))
        .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<MediaItem>> fetchCategory(
    TvBoxSite site,
    String categoryId, {
    int page = 1,
  }) async {
    final base = _baseUrl(site);
    final uri = Uri.parse('${base}video').replace(
      queryParameters: <String, String>{
        'tid': categoryId,
        'class': '',
        'area': '',
        'lang': '',
        'year': '',
        'limit': '18',
        'pg': '$page',
      },
    );
    return _parseMedia(await _get(uri.toString()));
  }

  Future<List<MediaItem>> search(TvBoxSite site, String keyword) async {
    final uri = Uri.parse('${_baseUrl(site)}search').replace(
      queryParameters: <String, String>{'text': keyword, 'pg': '1'},
    );
    return _parseMedia(await _get(uri.toString()));
  }

  Future<List<PlaybackCandidate>> fetchCandidates(
    TvBoxSite site,
    MediaItem item,
  ) async {
    final uri = Uri.parse('${_baseUrl(site)}video_detail').replace(
      queryParameters: <String, String>{'id': item.id},
    );
    final root = await _get(uri.toString());
    final rawData = root['data'];
    if (rawData is! Map) return const <PlaybackCandidate>[];
    final data = Map<String, dynamic>.from(rawData);
    final players = data['vod_url_with_player'];
    if (players is! List) return const <PlaybackCandidate>[];

    final candidates = <PlaybackCandidate>[];
    for (var lineIndex = 0; lineIndex < players.length; lineIndex++) {
      final rawPlayer = players[lineIndex];
      if (rawPlayer is! Map) continue;
      final player = Map<String, dynamic>.from(rawPlayer);
      final lineName = (player['code'] ?? player['name'] ?? '线路').toString();
      final parserUrls = (player['parse_api']?.toString() ?? '')
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.startsWith('http'))
          .toList(growable: false);
      final episodes = <PlaybackEpisode>[];
      for (final rawEpisode in (player['url']?.toString() ?? '').split('#')) {
        final separator = rawEpisode.indexOf(r'$');
        final name =
            separator > 0 ? rawEpisode.substring(0, separator).trim() : '播放';
        final playId = separator > 0
            ? rawEpisode.substring(separator + 1).trim()
            : rawEpisode.trim();
        if (playId.isEmpty) continue;
        final original = PlaybackEpisode(
          name: name.isEmpty ? '播放' : name,
          url: playId,
          headers: _headers(player['header']),
          sortIndex: episodes.length + 1,
        );
        episodes.add(
          PlaybackEpisode(
            name: original.name,
            url: original.url,
            headers: original.headers,
            sortIndex: original.sortIndex,
            resolvePlayback: () => _resolve(
              site,
              original,
              parserUrls,
              player['code']?.toString() ?? '',
            ),
          ),
        );
      }
      if (episodes.isEmpty) continue;
      candidates.add(
        PlaybackCandidate(
          sourceKey: '${site.key}_$lineIndex',
          sourceName: site.name,
          lineName: lineName,
          episodes: episodes,
        ),
      );
    }
    return candidates;
  }

  Future<PlaybackEpisode> _resolve(TvBoxSite site, PlaybackEpisode episode,
      List<String> parsers, String flag) async {
    Future<PlaybackEpisode> resolve(Map<String, dynamic> response,
            {bool useGlobalParser = false}) =>
        resolveSpiderPlayback(
          site: site,
          episode: episode,
          response: <String, dynamic>{
            if (useGlobalParser) 'flag': flag,
            ...response,
          },
          dio: _dio,
        );
    if (_isDirectVideo(episode.url)) {
      return resolve(<String, dynamic>{'url': episode.url, 'parse': 0});
    }
    for (final parser in parsers) {
      try {
        final url = '$parser${Uri.encodeComponent(episode.url)}';
        final response = await _request(url);
        Object? value = response.data;
        if (value is String) {
          final text = value;
          try {
            value = json.decode(text);
          } on FormatException {
            if (text.toLowerCase().contains('<html') ||
                text.toLowerCase().contains('<iframe') ||
                text.toLowerCase().contains('<script')) {
              return await resolve(<String, dynamic>{'url': url, 'parse': 1});
            }
          }
        }
        if (value is Map) {
          final result = <String, dynamic>{
            if (value['data'] is Map)
              ...Map<String, dynamic>.from(value['data'] as Map),
            ...Map<String, dynamic>.from(value),
          };
          if (result['url']?.toString().isNotEmpty == true) {
            return await resolve(<String, dynamic>{'parse': 0, ...result});
          }
        }
      } catch (_) {
        // Parser routes are independent; one dead route must not hide later ones.
      }
    }
    // A web episode remains available to the common resolver; opaque IDs need
    // an actual parser result and must not be silently removed from the list.
    if (Uri.tryParse(episode.url)?.hasScheme == true ||
        site.flags.contains(flag)) {
      return resolve(<String, dynamic>{'url': episode.url, 'parse': 1},
          useGlobalParser: true);
    }
    throw const FormatException('App API 解析器没有返回有效播放地址');
  }

  Future<Map<String, dynamic>> _get(String url) async {
    final response = await _request(url);
    Object? value = response.data;
    if (value is String) {
      try {
        value = json.decode(value);
      } catch (_) {}
    }
    return value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
  }

  Future<Response<dynamic>> _request(String url) => _dio.get<dynamic>(
        url,
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 6),
          headers: const <String, String>{'User-Agent': 'Dart/2.14 (dart:io)'},
        ),
      );

  static List<Map<String, dynamic>> _dataList(Map<String, dynamic> root) {
    Object? value = root['list'] ?? root['data'];
    if (value is Map) value = value['list'];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static List<MediaItem> _parseMedia(Map<String, dynamic> root) {
    return _dataList(root)
        .map(
          (item) => MediaItem(
            id: (item['vod_id'] ?? item['nextlink'] ?? '').toString(),
            title: (item['vod_name'] ?? item['title'] ?? '未知节目').toString(),
            posterUrl: (item['vod_pic'] ?? item['pic'])?.toString(),
            overview:
                (item['vod_content'] ?? item['vod_remarks'] ?? item['state'])
                    ?.toString(),
            year: item['vod_year']?.toString(),
          ),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  static String _baseUrl(TvBoxSite site) {
    Object? ext = site.ext;
    if (ext is Map) ext = ext['url'] ?? ext['api'];
    final value = ext?.toString().split('###').first.trim() ?? '';
    if (!value.startsWith('http')) return '';
    return value.endsWith('/') ? value : '$value/';
  }

  static Map<String, String>? _headers(Object? value) {
    if (value is String) {
      try {
        value = json.decode(value);
      } on FormatException {
        return null;
      }
    }
    return value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value.toString()))
        : null;
  }

  static bool _isDirectVideo(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !<String>{'http', 'https'}.contains(uri.scheme)) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return <String>['.m3u8', '.mp4', '.flv', '.mpd', '.mkv'].any(path.endsWith);
  }
}
