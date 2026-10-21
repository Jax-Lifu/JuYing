import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_runtime_capability.dart';

/// Implements the known Tuxiaobei DRPY rule through its public website protocol.
///
/// Only this rule identity is mapped to Dart. No subscription JavaScript is
/// downloaded or executed, and media URLs are refreshed when an episode opens.
class TuxiaobeiDartSpiderAdapter {
  TuxiaobeiDartSpiderAdapter(this._dio);

  final Dio _dio;
  static const _origin = 'https://www.tuxiaobei.com';
  static const _userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
      'AppleWebKit/605.1.15 Version/16.0 Mobile/15E148 Safari/604.1';

  static bool supports(TvBoxSite site) =>
      site.type == 3 &&
      TvBoxSpiderRuntimeCapability.supportsTuxiaobei(
          api: site.api, ext: site.ext);

  List<TvBoxCategory> fetchCategories() => const <TvBoxCategory>[
        TvBoxCategory(id: '2', name: '儿歌'),
        TvBoxCategory(id: '3', name: '故事'),
        TvBoxCategory(id: '4', name: '国学'),
        TvBoxCategory(id: '25', name: '启蒙'),
      ];

  Future<List<MediaItem>> fetchCategory(String categoryId,
      {int page = 1}) async {
    final text = await _get('$_origin/list/mip-data', query: <String, String>{
      'typeId': categoryId,
      'page': '$page',
      'callback': '',
    });
    // An empty callback still produces `(json);`; unwrap the data, never eval it.
    final jsonText = text.startsWith('(') && text.endsWith(');')
        ? text.substring(1, text.length - 2)
        : text;
    final root = json.decode(jsonText);
    if (root is! Map || root['status'] != 0) {
      throw const FormatException('兔小贝分类接口返回异常');
    }
    final data = root['data'];
    final items = data is Map ? data['items'] : null;
    if (items is! List) throw const FormatException('兔小贝分类列表格式异常');
    return items
        .whereType<Map>()
        .map((item) {
          final pageUrl = _playPage(item['video_id']?.toString() ?? '');
          return MediaItem(
            id: pageUrl ?? '',
            title: item['name']?.toString() ?? '',
            posterUrl: item['image']?.toString(),
            overview: item['duration_string']?.toString(),
          );
        })
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList();
  }

  Future<List<MediaItem>> search(String keyword) async {
    // /search/index redirects with raw UTF-8 Chinese in Location. Use the
    // canonical encoded route so Dart's HTTP header decoding cannot corrupt it.
    final html = await _get('$_origin/search/${Uri.encodeComponent(keyword)}');
    final blocks = RegExp(
      r'''<div\b[^>]*class=["']items["'][^>]*>([\s\S]*?)<!--\s*items end\s*-->''',
      caseSensitive: false,
    ).allMatches(html);
    final items = <MediaItem>[];
    final seen = <String>{};
    for (final block in blocks) {
      final content = block.group(1)!;
      final href =
          RegExp(r'''href=["'](/play/\d+)["']''').firstMatch(content)?.group(1);
      final pageUrl = href == null ? null : _playPage('$_origin$href');
      final title = _classText(content, 'title');
      if (pageUrl == null || title.isEmpty || !seen.add(pageUrl)) continue;
      final imageTag = RegExp(r'<mip-img\b[^>]*>', caseSensitive: false)
          .firstMatch(content)
          ?.group(0);
      items.add(MediaItem(
        id: pageUrl,
        title: title,
        posterUrl: imageTag == null ? null : _attribute(imageTag, 'src'),
        overview: _classText(content, 'time'),
      ));
    }
    return items;
  }

  /// This site publishes individual clips; each card is one selectable episode.
  List<PlaybackCandidate> fetchCandidates(TvBoxSite site, MediaItem item) {
    final pageUrl = _playPage(item.id);
    if (pageUrl == null) throw const FormatException('兔小贝节目地址无效');
    return <PlaybackCandidate>[
      PlaybackCandidate(
        sourceKey: site.key,
        sourceName: site.name,
        lineName: '兔小贝官方',
        resolution: '官方',
        episodes: <PlaybackEpisode>[
          PlaybackEpisode(
            name: item.title,
            url: pageUrl,
            thumbnailUrl: item.posterUrl,
            resolvePlayback: () => _resolvePlayback(item, pageUrl),
          ),
        ],
      ),
    ];
  }

  Future<PlaybackEpisode> _resolvePlayback(
      MediaItem item, String pageUrl) async {
    final html = await _get(pageUrl);
    final videoTag = RegExp(r'<[^>]+>', caseSensitive: false)
        .allMatches(html)
        .map((match) => match.group(0)!)
        .where((tag) => _attribute(tag, 'id') == 'videoWrap')
        .firstOrNull;
    final rawUrl = videoTag == null ? null : _attribute(videoTag, 'video-src');
    final media = rawUrl == null ? null : Uri.parse(pageUrl).resolve(rawUrl);
    if (media == null ||
        !<String>{'http', 'https'}.contains(media.scheme) ||
        media.host.isEmpty ||
        !RegExp(r'\.(mp4|m3u8)$', caseSensitive: false).hasMatch(media.path)) {
      throw const FormatException('兔小贝播放页未返回原生媒体地址');
    }
    return PlaybackEpisode(
      name: item.title,
      url: media.toString(),
      thumbnailUrl: item.posterUrl,
      headers: <String, String>{'User-Agent': _userAgent, 'Referer': pageUrl},
    );
  }

  Future<String> _get(String url, {Map<String, String>? query}) async {
    final response = await _dio.get<String>(
      url,
      queryParameters: query,
      options: Options(
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: const <String, String>{'User-Agent': _userAgent},
      ),
    );
    return response.data?.trim() ?? '';
  }

  static String? _playPage(String id) {
    if (RegExp(r'^\d+$').hasMatch(id)) return '$_origin/play/$id';
    final uri = Uri.tryParse(id);
    return uri != null &&
            <String>{'http', 'https'}.contains(uri.scheme) &&
            uri.host == 'www.tuxiaobei.com' &&
            RegExp(r'^/play/\d+$').hasMatch(uri.path)
        ? '$_origin${uri.path}'
        : null;
  }

  static String? _attribute(String tag, String name) {
    final value = RegExp('''(?:^|\\s)$name\\s*=\\s*["']([^"']*)["']''',
            caseSensitive: false)
        .firstMatch(tag)
        ?.group(1);
    return value == null ? null : _decodeText(value);
  }

  static String _classText(String html, String name) {
    final value = RegExp('''<[^>]+class=["']$name["'][^>]*>([\\s\\S]*?)</''',
            caseSensitive: false)
        .firstMatch(html)
        ?.group(1);
    return _decodeText(value?.replaceAll(RegExp('<[^>]*>'), '') ?? '').trim();
  }

  static String _decodeText(String text) => text.replaceAllMapped(
        RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|quot|apos|lt|gt|nbsp);'),
        (match) {
          final entity = match.group(1)!;
          if (entity.startsWith('#')) {
            final code = entity.startsWith('#x')
                ? int.parse(entity.substring(2), radix: 16)
                : int.parse(entity.substring(1));
            return code <= 0x10ffff
                ? String.fromCharCode(code)
                : match.group(0)!;
          }
          return const <String, String>{
            'amp': '&',
            'quot': '"',
            'apos': "'",
            'lt': '<',
            'gt': '>',
            'nbsp': ' ',
          }[entity]!;
        },
      );
}
