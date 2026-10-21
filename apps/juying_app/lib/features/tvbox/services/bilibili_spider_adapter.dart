import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';

/// Bili、BiliGuard 与 Bili2 关键词目录的跨平台 Dart 实现。
///
/// Android TVBox 通过 Dex Spider 包装 B 站公开 Web API；直接实现同一 CatVod
/// 契约可避免在 Windows/iOS 等平台加载不可信 Dex，同时保留分类、搜索与播放能力。
class BilibiliSpiderAdapter {
  BilibiliSpiderAdapter(this._dio);

  static const String _apiRoot = 'https://api.bilibili.com';
  static const Map<String, String> playbackHeaders = <String, String>{
    'Referer': 'https://www.bilibili.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
  };

  final Dio _dio;

  static bool supports(TvBoxSite site) =>
      site.type == 3 &&
      <String>{'csp_bili', 'csp_biliguard', 'csp_bili2'}
          .contains(site.api.trim().toLowerCase());

  /// 加载订阅 ext 中的关键词分类；失效 ext 不影响搜索和已缓存分类。
  Future<List<TvBoxCategory>> fetchCategories(TvBoxSite site) async {
    final inline = _parseCategories(site.ext);
    if (inline.isNotEmpty) return inline;
    final config = _asMap(site.ext);
    final extUrl = (config?['json'] ?? site.ext)?.toString().trim() ?? '';
    final uri = Uri.tryParse(extUrl);
    if (uri == null ||
        !<String>{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return const <TvBoxCategory>[];
    }
    final response = await _dio.get<dynamic>(extUrl);
    return _parseCategories(response.data);
  }

  Future<List<MediaItem>> fetchCategory(
    String keyword, {
    int page = 1,
  }) {
    return search(keyword, page: page);
  }

  Future<List<MediaItem>> search(String keyword, {int page = 1}) async {
    final response = await _dio.get<dynamic>(
      '$_apiRoot/x/web-interface/search/type',
      queryParameters: <String, dynamic>{
        'search_type': 'video',
        'keyword': keyword,
        'page': page,
      },
      options: Options(headers: playbackHeaders),
    );
    final root = _asMap(response.data);
    final data = _asMap(root?['data']);
    final rawItems = data?['result'];
    if (root?['code'] != 0 || rawItems is! List) {
      return const <MediaItem>[];
    }
    return rawItems
        .whereType<Map>()
        .map((raw) {
          final item = Map<String, dynamic>.from(raw);
          final picture = item['pic']?.toString() ?? '';
          return MediaItem(
            id: item['bvid']?.toString() ?? '',
            title: _stripHtml(item['title']?.toString() ?? '未知视频'),
            posterUrl: picture.startsWith('//') ? 'https:$picture' : picture,
            overview: _stripHtml(item['description']?.toString() ?? ''),
            genres: const <String>['哔哩哔哩'],
          );
        })
        .where((item) => item.id.startsWith('BV'))
        .toList(growable: false);
  }

  /// BV 详情只列出分 P；临时直链到选集时再获取，避免长合集的请求风暴和过期。
  Future<List<PlaybackCandidate>> fetchCandidates(
    TvBoxSite site,
    MediaItem item,
  ) async {
    final viewResponse = await _dio.get<dynamic>(
      '$_apiRoot/x/web-interface/view',
      queryParameters: <String, dynamic>{'bvid': item.id},
      options: Options(headers: playbackHeaders),
    );
    final viewRoot = _asMap(viewResponse.data);
    final viewData = _asMap(viewRoot?['data']);
    final pages = viewData?['pages'];
    if (viewRoot?['code'] != 0 || pages is! List) {
      return const <PlaybackCandidate>[];
    }

    final episodes = <PlaybackEpisode>[];
    for (final rawPage in pages.whereType<Map>()) {
      final page = Map<String, dynamic>.from(rawPage);
      final cid = page['cid']?.toString() ?? '';
      if (cid.isEmpty) continue;
      final sortIndex =
          int.tryParse(page['page']?.toString() ?? '') ?? episodes.length + 1;
      final name = page['part']?.toString().trim().isNotEmpty == true
          ? page['part'].toString().trim()
          : '第 $sortIndex P';
      final duration = Duration(
        seconds: int.tryParse(page['duration']?.toString() ?? '') ?? 0,
      );
      final pageUrl = 'https://www.bilibili.com/video/${item.id}?p=$sortIndex';
      episodes.add(
        PlaybackEpisode(
          name: name,
          url: pageUrl,
          sortIndex: sortIndex,
          duration: duration,
          headers: playbackHeaders,
          officialPageUrl: pageUrl,
          resolvePlayback: () => _resolvePage(
            item.id,
            cid,
            name: name,
            sortIndex: sortIndex,
            duration: duration,
            pageUrl: pageUrl,
          ),
        ),
      );
    }
    if (episodes.isEmpty) return const <PlaybackCandidate>[];
    return <PlaybackCandidate>[
      PlaybackCandidate(
        sourceKey: site.key,
        sourceName: site.name,
        lineName: 'B站直连',
        resolution: '自动',
        episodes: episodes,
      ),
    ];
  }

  Future<PlaybackEpisode> _resolvePage(
    String bvid,
    String cid, {
    required String name,
    required int sortIndex,
    required Duration duration,
    required String pageUrl,
  }) async {
    final response = await _dio.get<dynamic>(
      '$_apiRoot/x/player/playurl',
      queryParameters: <String, dynamic>{
        'bvid': bvid,
        'cid': cid,
        'qn': 64,
        // durl 携带完整音视频；当前统一模型尚不表示 DASH 的独立音轨。
        'fnval': 0,
      },
      options: Options(headers: playbackHeaders),
    );
    final root = _asMap(response.data);
    final data = _asMap(root?['data']);
    final durl = data?['durl'];
    if (root?['code'] != 0 || durl is! List || durl.isEmpty) {
      throw StateError('B站未返回此分P的可播放地址');
    }
    // 多段 durl 不是多条备选线路；只播首段会把完整视频静默截断。
    if (durl.length != 1) {
      throw UnsupportedError('此B站视频使用分段文件，当前直连播放器尚不支持');
    }
    final url = _asMap(durl.single)?['url']?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !<String>{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw StateError('B站返回的播放地址无效');
    }
    return PlaybackEpisode(
      name: name,
      url: url,
      sortIndex: sortIndex,
      duration: duration,
      badge: const <int, String>{
        16: '360P',
        32: '480P',
        64: '720P',
        74: '720P60',
        80: '1080P',
        112: '1080P+',
        116: '1080P60',
        120: '4K',
      }[data?['quality']],
      headers: playbackHeaders,
      officialPageUrl: pageUrl,
    );
  }

  static List<TvBoxCategory> _parseCategories(Object? value) {
    Object? decoded = value;
    if (value is String && value.trimLeft().startsWith('{')) {
      try {
        decoded = json.decode(value);
      } catch (_) {
        return const <TvBoxCategory>[];
      }
    }
    final root = _asMap(decoded);
    final classes = root?['classes'] ?? root?['class'];
    if (classes is! List) return const <TvBoxCategory>[];
    return classes
        .whereType<Map>()
        .map((item) => TvBoxCategory.fromJson(Map<String, dynamic>.from(item)))
        // Guard 配置的 peizhi 是原宿主登录动作，不是搜索关键词分类。
        .where((category) =>
            category.id.isNotEmpty &&
            category.name.isNotEmpty &&
            category.id != 'peizhi')
        .toList(growable: false);
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = json.decode(value);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .trim();
  }
}
