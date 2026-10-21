import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:juying/core/models/live_channel.dart';
import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/live/services/iptv_service.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_runtime_capability.dart';

/// Implements live2vod's playlist contract in Dart, without executing its script.
/// Playlist groups become titles and their channels become selectable episodes.
class LiveToVodSpiderAdapter {
  LiveToVodSpiderAdapter(this._dio);

  final Dio _dio;

  /// Match the known script identity, rather than accepting arbitrary JS files.
  static bool supportsConfig({required String api, Object? ext}) =>
      TvBoxSpiderRuntimeCapability.supportsLiveToVod(api: api, ext: ext);

  static bool supports(TvBoxSite site) =>
      site.type == 3 && supportsConfig(api: site.api, ext: site.ext);

  Future<List<TvBoxCategory>> fetchCategories(TvBoxSite site) async {
    var config = (site.ext as String).trim();
    var base = Uri.parse(site.api);
    if (config.contains(r'$$$')) {
      final split = config.indexOf(r'$$$');
      base = base.resolve(config.substring(0, split));
      config = config.substring(split + 3);
    }
    final posterParts = config.split('&&&');
    final poster =
        posterParts.length > 1 ? base.resolve(posterParts[1]).toString() : '';
    final categories = <TvBoxCategory>[];
    for (final source in posterParts.first.split('#')) {
      final separator = source.indexOf(r'$');
      if (separator > 0) {
        categories.add(_category(source.substring(0, separator),
            _resolveList(base, source.substring(separator + 1)), poster));
        continue;
      }
      final uri = base.resolve(source.trim());
      final data = jsonDecode(await _get(uri.toString()));
      if (data is! List) throw const FormatException('直播目录必须是数组');
      for (final row in data.whereType<Map>()) {
        final name = row['name']?.toString().trim() ?? '';
        final url = row['url']?.toString().trim() ?? '';
        if (name.isEmpty || url.isEmpty) continue;
        categories.add(_category(name, _resolveList(uri, url), poster));
      }
    }
    return categories;
  }

  // A playlist's pipe suffix contains request headers, not URL path characters.
  String _resolveList(Uri base, String value) {
    final separator = value.indexOf('|');
    return separator < 0
        ? base.resolve(value).toString()
        : '${base.resolve(value.substring(0, separator))}${value.substring(separator)}';
  }

  TvBoxCategory _category(String name, String url, String poster) =>
      TvBoxCategory(
        id: jsonEncode(
            <String, String>{'name': name, 'url': url, 'poster': poster}),
        name: name.replaceAll('!!', ''),
      );

  Future<List<MediaItem>> fetchCategory(TvBoxSite site, String categoryId,
      {int page = 1}) async {
    if (page != 1) return const [];
    final config = jsonDecode(categoryId) as Map;
    final groups = await _groups(categoryId);
    return groups.entries
        .map((entry) => MediaItem(
              id: jsonEncode(
                  <String, String>{'category': categoryId, 'group': entry.key}),
              title: entry.key,
              posterUrl: entry.value.first.logoUrl ??
                  (config['poster']?.toString().isNotEmpty == true
                      ? config['poster'].toString()
                      : null),
              totalEpisodes: entry.value.length,
            ))
        .toList(growable: false);
  }

  /// The original Spider has no search endpoint; avoid downloading every list
  /// for each federated keystroke and preserve that contract.
  Future<List<MediaItem>> search(TvBoxSite site, String keyword,
          {int page = 1}) async =>
      const [];

  Future<List<PlaybackCandidate>> fetchCandidates(
      TvBoxSite site, MediaItem item) async {
    final id = jsonDecode(item.id) as Map;
    final groups = await _groups(id['category'] as String);
    final channels = groups[id['group']] ?? const <LiveChannel>[];
    final lines = <List<PlaybackEpisode>>[];
    final routeCount = channels.fold<int>(
        0,
        (count, channel) =>
            channel.routes.length > count ? channel.routes.length : count);
    for (var channelIndex = 0; channelIndex < channels.length; channelIndex++) {
      final channel = channels[channelIndex];
      for (var routeIndex = 0; routeIndex < routeCount; routeIndex++) {
        while (lines.length <= routeIndex) {
          lines.add([]);
        }
        // Every line retains channel identity; sparse fallback lines would make
        // the player's episode matcher silently switch to another channel.
        final route = routeIndex < channel.routes.length
            ? channel.routes[routeIndex]
            : channel.routes.first;
        lines[routeIndex].add(PlaybackEpisode(
          name: channel.name,
          url: route.url,
          sortIndex: channelIndex + 1,
          headers: route.headers,
          thumbnailUrl: channel.logoUrl,
        ));
      }
    }
    return <PlaybackCandidate>[
      for (var i = 0; i < lines.length; i++)
        PlaybackCandidate(
            sourceKey: '${site.key}_$i',
            sourceName: site.name,
            lineName: '线路 ${i + 1}',
            episodes: lines[i],
            resolution: ''),
    ];
  }

  Future<Map<String, List<LiveChannel>>> _groups(String categoryId) async {
    final config = jsonDecode(categoryId) as Map;
    final rawUrl = config['url'] as String;
    final parts = rawUrl.split('|');
    final headers = <String, String>{'User-Agent': 'okhttp/3.15'};
    if (parts.length > 1) {
      headers.addAll(Uri.splitQueryString(parts.sublist(1).join('|')));
    }
    var content = (await _get(parts.first, headers: headers)).trim();
    final parser = IptvService(dio: _dio);
    List<LiveChannel> channels;
    if (content.startsWith('[') || content.startsWith('{')) {
      final decoded = jsonDecode(content);
      final groups = decoded is List ? decoded : decoded['data']?['datalist'];
      if (groups is! List) throw const FormatException('直播列表格式不受支持');
      final text = StringBuffer();
      for (final group in groups.whereType<Map>()) {
        text.writeln(
            '${group['name'] ?? group['prov'] ?? config['name']},#genre#');
        final rows = group['channel'] ?? group['list'];
        if (rows is! List) continue;
        for (final row in rows.whereType<Map>()) {
          final urls = row['urls'];
          if (urls is! List) continue;
          for (final url in urls) {
            text.writeln('${row['name']},${url is Map ? url['url'] : url}');
          }
        }
      }
      content = text.toString();
    }
    if (content.contains('#EXTINF')) {
      channels = parser.parseM3u(content);
    } else {
      // live2vod also accepts bare category headings in grouped TXT lists.
      final normalized = content.split(RegExp(r'\r?\n')).map((line) {
        final value = line.trim();
        return value.isNotEmpty &&
                !value.contains(',') &&
                !value.startsWith('#') &&
                !value.contains('://')
            ? '$value,#genre#'
            : value;
      }).join('\n');
      channels = parser.parseTxt('${config['name']},#genre#\n$normalized');
    }
    final grouped = <String, List<LiveChannel>>{};
    for (final channel in channels) {
      final routes = channel.routes
          .where((route) {
            final uri = Uri.tryParse(route.url);
            return uri != null &&
                uri.host.isNotEmpty &&
                const {'http', 'https', 'rtmp', 'rtsp'}.contains(uri.scheme);
          })
          .map((route) => route.copyWith(headers: <String, String>{
                ...headers,
                ...?route.headers,
              }))
          .toList(growable: false);
      if (routes.isEmpty) continue;
      (grouped[channel.category] ??= []).add(channel.copyWith(routes: routes));
    }
    if (grouped.isEmpty) throw const FormatException('直播列表没有有效频道');
    return grouped;
  }

  Future<String> _get(String url, {Map<String, String>? headers}) async {
    final uri = Uri.parse(url);
    if (!const {'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('直播订阅地址必须是 HTTP(S)');
    }
    final response = await _dio.get<String>(url,
        options: Options(
            responseType: ResponseType.plain,
            headers: headers ?? const {'User-Agent': 'okhttp/3.15'}));
    return response.data ?? '';
  }
}
