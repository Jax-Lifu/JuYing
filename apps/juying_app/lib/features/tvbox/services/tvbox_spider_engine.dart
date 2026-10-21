import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/android_dex_spider_adapter.dart';
import 'package:juying/features/tvbox/services/app_ys_v2_dart_spider_adapter.dart';
import 'package:juying/features/tvbox/services/bilibili_spider_adapter.dart';
import 'package:juying/features/tvbox/services/cctv_vod_adapter.dart';
import 'package:juying/features/tvbox/services/live_to_vod_spider_adapter.dart';
import 'package:juying/features/tvbox/services/python_compat_spider_adapter.dart';
import 'package:juying/features/tvbox/services/spider_playback_response.dart';
import 'package:juying/features/tvbox/services/t4_http_spider_adapter.dart';
import 'package:juying/features/tvbox/services/tuxiaobei_dart_spider_adapter.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_runtime_capability.dart';
import 'package:juying/features/tvbox/services/xbpq_dart_spider_adapter.dart';

/// Unified TVBox Spider runtime engine and multi-site dispatcher.
///
/// **What**: Manages the lifecycle, category fetching, detail parsing, and federated searching
/// across CatVod JS spiders, MacCMS JSON providers, and CCTV official VOD adapters.
///
/// **Why**: TVBox architecture relies on multiple site definitions. This engine provides
/// a unified, decoupled API layer so the UI and Player engine work transparently across all sources.
class TvBoxSpiderEngine {
  TvBoxSpiderEngine({
    AndroidDexSpiderAdapter? dexAdapter,
    CctvVodAdapter? cctvAdapter,
    PythonCompatSpiderAdapter? pythonAdapter,
    Dio? dio,
  })  : _dexAdapter = dexAdapter ?? AndroidDexSpiderAdapter(),
        _cctvAdapter = cctvAdapter ?? CctvVodAdapter(),
        _pythonAdapter = pythonAdapter ?? PythonCompatSpiderAdapter(),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: <String, dynamic>{
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
                },
              ),
            );

  final AndroidDexSpiderAdapter _dexAdapter;
  final CctvVodAdapter _cctvAdapter;
  final PythonCompatSpiderAdapter _pythonAdapter;
  final Dio _dio;
  final Map<String, DateTime> _sourceCooldowns = <String, DateTime>{};
  final Map<String, int> _sourceFailureCounts = <String, int>{};

  /// Default preset TVBox sites pre-configured out-of-the-box.
  static final List<TvBoxSite> defaultPresetSites = <TvBoxSite>[
    const TvBoxSite(
      key: 'cctv_vod',
      name: '🏛️ 央视片库',
      type: 4,
      searchable: true,
      quickSearch: true,
      categories: <TvBoxCategory>[
        TvBoxCategory(id: 'cctv_movie_电影', name: '电影'),
        TvBoxCategory(id: 'CHAL1460955899450127_动画片', name: '少儿动画'),
        TvBoxCategory(id: 'CHAL1460955924871139_电视剧', name: '经典剧场'),
        TvBoxCategory(id: 'CHAL1460955853485115_纪录片', name: '央视纪录片'),
        TvBoxCategory(id: 'CHAL1460955909280133_特别节目', name: '特别节目'),
      ],
    ),
    const TvBoxSite(
      key: 'bilibili_dart',
      name: '📺 哔哩哔哩',
      type: 3,
      api: 'csp_Bili',
      searchable: true,
      quickSearch: true,
      // B站适配器的分类契约是搜索关键词，不能传入仅用于本地展示的编号。
      categories: <TvBoxCategory>[
        TvBoxCategory(id: '热门视频', name: '热门视频'),
        TvBoxCategory(id: '番剧国创', name: '番剧国创'),
        TvBoxCategory(id: '影视精选', name: '影视精选'),
        TvBoxCategory(id: '纪录片', name: '纪录片'),
      ],
    ),
    const TvBoxSite(
      key: 'tuxiaobei_dart',
      name: '🐰 兔小贝',
      type: 3,
      api: 'csp_Tuxiaobei',
      searchable: true,
      quickSearch: true,
    ),
    const TvBoxSite(
      key: 'lz_maccms',
      name: '🌟 量子影视',
      type: 1,
      api: 'https://cj.lziapi.com/api.php/provide/vod/',
      searchable: true,
      quickSearch: true,
      categories: <TvBoxCategory>[
        TvBoxCategory(id: '1', name: '电影'),
        TvBoxCategory(id: '2', name: '连续剧'),
        TvBoxCategory(id: '3', name: '综艺'),
        TvBoxCategory(id: '4', name: '动漫'),
      ],
    ),
    const TvBoxSite(
      key: 'ff_maccms',
      name: '🎬 非凡影视',
      type: 1,
      api: 'http://cj.ffzyapi.com/api.php/provide/vod/',
      searchable: true,
      quickSearch: true,
      categories: <TvBoxCategory>[
        TvBoxCategory(id: '1', name: '电影'),
        TvBoxCategory(id: '2', name: '连续剧'),
        TvBoxCategory(id: '3', name: '综艺'),
        TvBoxCategory(id: '4', name: '动漫'),
      ],
    ),
    const TvBoxSite(
      key: 'bf_maccms',
      name: '⚡ 暴风影院',
      type: 1,
      api: 'https://bfzyapi.com/api.php/provide/vod/',
      searchable: true,
      quickSearch: true,
      categories: <TvBoxCategory>[
        TvBoxCategory(id: '1', name: '电影'),
        TvBoxCategory(id: '2', name: '连续剧'),
        TvBoxCategory(id: '3', name: '综艺'),
        TvBoxCategory(id: '4', name: '动漫'),
      ],
    ),
  ];

  /// Fetches category listings and media cards for a specific TVBox site.
  Future<List<MediaItem>> fetchCategoryMedia(
    TvBoxSite site,
    String categoryId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (!site.isRuntimeSupported) return const <MediaItem>[];
    if (_isSourceCoolingDown(site)) return const <MediaItem>[];

    if (LiveToVodSpiderAdapter.supports(site)) {
      try {
        final items = await LiveToVodSpiderAdapter(_dio)
            .fetchCategory(site, categoryId, page: page);
        _recordSourceSuccess(site);
        return items;
      } catch (error) {
        _recordSourceFailure(site, 'live2vod 目录', error);
        return const <MediaItem>[];
      }
    }

    if (TuxiaobeiDartSpiderAdapter.supports(site)) {
      try {
        final items = await TuxiaobeiDartSpiderAdapter(_dio)
            .fetchCategory(categoryId, page: page);
        _recordSourceSuccess(site);
        return items;
      } catch (error) {
        _recordSourceFailure(site, '兔小贝目录', error);
        return const <MediaItem>[];
      }
    }

    if (PythonCompatSpiderAdapter.supports(site)) {
      try {
        return await _pythonAdapter.fetchCategory(
          site,
          categoryId,
          page: page,
          pageSize: pageSize,
        );
      } catch (error) {
        _recordSourceFailure(site, 'Dart Python 兼容目录', error);
        return const <MediaItem>[];
      }
    }
    if (XbpqDartSpiderAdapter.supports(site)) {
      try {
        final list = await XbpqDartSpiderAdapter(_dio).fetchCategory(
          site,
          categoryId,
          page: page,
        );
        if (list.isNotEmpty) _recordSourceSuccess(site);
        return list;
      } catch (error) {
        _recordSourceFailure(site, 'Dart XBPQ 目录', error);
        return const <MediaItem>[];
      }
    }
    if (AppYsV2DartSpiderAdapter.supports(site)) {
      try {
        final list = await AppYsV2DartSpiderAdapter(_dio).fetchCategory(
          site,
          categoryId,
          page: page,
        );
        if (list.isNotEmpty) _recordSourceSuccess(site);
        return list;
      } catch (error) {
        _recordSourceFailure(site, 'Dart AppYsV2 目录', error);
        return const <MediaItem>[];
      }
    }
    if (_dexAdapter.supports(site) && !BilibiliSpiderAdapter.supports(site)) {
      try {
        return await _dexAdapter.fetchCategory(
          site,
          categoryId,
          page: page,
        );
      } catch (error) {
        _recordSourceFailure(site, 'Dex 目录', error);
        return const <MediaItem>[];
      }
    }
    if (BilibiliSpiderAdapter.supports(site)) {
      return BilibiliSpiderAdapter(_dio).fetchCategory(
        categoryId,
        page: page,
      );
    }
    if (T4HttpSpiderAdapter.supports(site)) {
      return T4HttpSpiderAdapter(_dio).fetchCategory(
        site,
        categoryId,
        page: page,
      );
    }

    // 内置 CCTV 以 key 标识；TVBox type=4 是独立 HTTP Spider 协议，不能占用。
    if (site.key == 'cctv_vod') {
      String channelId = CctvVodAdapter.channelAnimation;
      String category = '动画片';

      if (categoryId.contains('电影')) {
        channelId = CctvVodAdapter.channelMovie;
        category = '电影';
      } else if (categoryId.contains('电视剧') || categoryId.contains('剧场')) {
        channelId = CctvVodAdapter.channelDrama;
        category = '电视剧';
      } else if (categoryId.contains('纪录片')) {
        channelId = CctvVodAdapter.channelDocumentary;
        category = '纪录片';
      } else if (categoryId.contains('特别节目')) {
        channelId = CctvVodAdapter.channelSpecial;
        category = '特别节目';
      }

      try {
        final albums = await _cctvAdapter.fetchAlbumList(
          channelId: channelId,
          firstCategory: category,
          page: page,
          pageSize: pageSize,
        );
        if (albums.isNotEmpty) {
          _recordSourceSuccess(site);
          return albums;
        }
      } catch (e) {
        _recordSourceFailure(site, 'CCTV 专辑', e);
      }

      return const <MediaItem>[];
    }

    // 2. HTTP VOD / MacCMS API Provider (supports type 0, 1, and type 3 HTTP endpoints)
    final httpApi = _effectiveHttpApi(site);
    if (httpApi.isNotEmpty) {
      if (_isSourceCoolingDown(site)) return <MediaItem>[];
      try {
        final query = <String, dynamic>{
          'ac': 'detail',
          'pg': page,
        };
        if (categoryId.isNotEmpty && categoryId != 'default') {
          query['t'] = categoryId;
        }
        final res = await _dio.get<dynamic>(
          httpApi,
          queryParameters: query,
        );
        var list = _parseMacCmsResponse(site, res.data);
        if (list == null) {
          try {
            final directRes = await _dio.get<dynamic>(httpApi);
            list = _parseMacCmsResponse(site, directRes.data);
          } catch (_) {}
        }
        _recordSourceSuccess(site);
        return list ?? <MediaItem>[];
      } catch (error) {
        _recordSourceFailure(site, '目录', error);
      }
      return <MediaItem>[];
    }

    // JS/JAR Spider 必须进入受限运行时；未接入沙箱前返回空结果，禁止伪造内容。
    return <MediaItem>[];
  }

  /// 获取 CMS 分类，使导入后首页能够展示真实导航而非空入口。
  Future<List<TvBoxCategory>> fetchSiteCategories(TvBoxSite site) async {
    if (!site.isRuntimeSupported) return const <TvBoxCategory>[];
    final isCms = site.type == 0 || site.type == 1;
    if (site.categories.isNotEmpty && !isCms) return site.categories;
    if (_isSourceCoolingDown(site)) return site.categories;

    if (LiveToVodSpiderAdapter.supports(site)) {
      try {
        return await LiveToVodSpiderAdapter(_dio).fetchCategories(site);
      } catch (error) {
        _recordSourceFailure(site, 'live2vod 分类', error);
        return const <TvBoxCategory>[];
      }
    }

    if (TuxiaobeiDartSpiderAdapter.supports(site)) {
      return TuxiaobeiDartSpiderAdapter(_dio).fetchCategories();
    }

    if (PythonCompatSpiderAdapter.supports(site)) {
      return _pythonAdapter.fetchCategories(site);
    }
    if (XbpqDartSpiderAdapter.supports(site)) {
      try {
        return await XbpqDartSpiderAdapter(_dio).fetchCategories(site);
      } catch (error) {
        _recordSourceFailure(site, 'Dart XBPQ 分类', error);
        return site.categories;
      }
    }
    if (AppYsV2DartSpiderAdapter.supports(site)) {
      try {
        return await AppYsV2DartSpiderAdapter(_dio).fetchCategories(site);
      } catch (error) {
        _recordSourceFailure(site, 'Dart AppYsV2 分类', error);
        return site.categories;
      }
    }
    if (_dexAdapter.supports(site) && !BilibiliSpiderAdapter.supports(site)) {
      try {
        return await _dexAdapter.fetchCategories(site);
      } catch (error) {
        _recordSourceFailure(site, 'Dex 分类', error);
        return site.categories;
      }
    }
    if (BilibiliSpiderAdapter.supports(site)) {
      try {
        return await BilibiliSpiderAdapter(_dio).fetchCategories(site);
      } catch (error) {
        _recordSourceFailure(site, '分类', error);
        return const <TvBoxCategory>[];
      }
    }
    if (T4HttpSpiderAdapter.supports(site)) {
      try {
        return await T4HttpSpiderAdapter(_dio).fetchCategories(site);
      } catch (error) {
        _recordSourceFailure(site, '分类', error);
        return const <TvBoxCategory>[];
      }
    }
    final httpApi = _effectiveHttpApi(site);
    if (httpApi.isEmpty || site.type == 4) {
      return site.categories;
    }
    if (_isSourceCoolingDown(site)) return site.categories;
    try {
      final response = await _dio.get<dynamic>(
        httpApi,
        queryParameters: const <String, dynamic>{'ac': 'list'},
      );
      final categories = _parseMacCmsCategories(response.data);
      _recordSourceSuccess(site);
      if (categories.isNotEmpty) return categories;
      return site.categories;
    } catch (error) {
      _recordSourceFailure(site, '分类', error);
      return site.categories;
    }
  }

  /// 查询单个真实 CMS 站点；不再为无结果关键字制造伪影片。
  Future<List<MediaItem>> searchSite(TvBoxSite site, String keyword) async {
    if (!site.isRuntimeSupported) return const <MediaItem>[];
    if (_isSourceCoolingDown(site)) return const <MediaItem>[];

    if (LiveToVodSpiderAdapter.supports(site)) {
      return LiveToVodSpiderAdapter(_dio).search(site, keyword);
    }

    if (TuxiaobeiDartSpiderAdapter.supports(site)) {
      if (!site.searchable) return const <MediaItem>[];
      try {
        final items = await TuxiaobeiDartSpiderAdapter(_dio).search(keyword);
        _recordSourceSuccess(site);
        return items;
      } catch (error) {
        _recordSourceFailure(site, '兔小贝搜索', error);
        return const <MediaItem>[];
      }
    }

    if (PythonCompatSpiderAdapter.supports(site)) {
      return const <MediaItem>[];
    }
    if (XbpqDartSpiderAdapter.supports(site)) {
      if (!site.searchable) return const <MediaItem>[];
      try {
        return await XbpqDartSpiderAdapter(_dio).search(site, keyword);
      } catch (error) {
        _recordSourceFailure(site, 'Dart XBPQ 搜索', error);
        return const <MediaItem>[];
      }
    }
    if (AppYsV2DartSpiderAdapter.supports(site)) {
      if (!site.searchable) return const <MediaItem>[];
      try {
        return await AppYsV2DartSpiderAdapter(_dio).search(site, keyword);
      } catch (error) {
        _recordSourceFailure(site, 'Dart AppYsV2 搜索', error);
        return const <MediaItem>[];
      }
    }
    if (_dexAdapter.supports(site) && !BilibiliSpiderAdapter.supports(site)) {
      if (!site.searchable) return const <MediaItem>[];
      try {
        return await _dexAdapter.search(site, keyword);
      } catch (error) {
        _recordSourceFailure(site, 'Dex 搜索', error);
        return const <MediaItem>[];
      }
    }
    if (BilibiliSpiderAdapter.supports(site)) {
      if (!site.searchable) return const <MediaItem>[];
      try {
        return await BilibiliSpiderAdapter(_dio).search(keyword);
      } catch (error) {
        _recordSourceFailure(site, '搜索', error);
        return const <MediaItem>[];
      }
    }
    if (T4HttpSpiderAdapter.supports(site)) {
      if (!site.searchable) return const <MediaItem>[];
      try {
        return await T4HttpSpiderAdapter(_dio).search(site, keyword);
      } catch (error) {
        _recordSourceFailure(site, '搜索', error);
        return const <MediaItem>[];
      }
    }
    final httpApi = _effectiveHttpApi(site);
    if (!site.searchable || httpApi.isEmpty || site.type == 4) {
      return <MediaItem>[];
    }
    if (_isSourceCoolingDown(site)) return <MediaItem>[];
    try {
      final response = await _dio.get<dynamic>(
        httpApi,
        queryParameters: <String, dynamic>{
          'ac': 'detail',
          'wd': keyword,
          'pg': 1,
        },
      );
      var results = _parseMacCmsResponse(site, response.data);
      if (results == null) {
        final searchUrl = httpApi.endsWith('/')
            ? '${httpApi}index.php/vod/search/wd/$keyword.html'
            : '$httpApi/index.php/vod/search/wd/$keyword.html';
        try {
          final searchRes = await _dio.get<dynamic>(searchUrl);
          results = _parseMacCmsResponse(site, searchRes.data);
        } catch (_) {}
      }
      _recordSourceSuccess(site);
      return results ?? const <MediaItem>[];
    } catch (error) {
      _recordSourceFailure(site, '搜索', error);
      return const <MediaItem>[];
    }
  }

  String _effectiveHttpApi(TvBoxSite site) {
    if (!site.isRuntimeSupported) return '';
    return TvBoxSpiderRuntimeCapability.httpCmsApi(
      type: site.type,
      api: site.api,
    );
  }

  /// 解析 CMS JSON/XML 或 HTML 卡片；null 表示协议未识别，空列表表示无结果。
  /// 分类末页与搜索无匹配不能触发首页回退，否则会混入无关影片。
  List<MediaItem>? _parseMacCmsResponse(TvBoxSite site, dynamic data) {
    final results = <MediaItem>[];
    if (data == null) return null;

    try {
      final decoded = data is String && data.trimLeft().startsWith('{')
          ? json.decode(data)
          : data;
      final map = decoded is Map<String, dynamic> ? decoded : null;
      if (map != null && map['list'] is List) {
        final rawList = map['list'] as List;
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            results.add(
              MediaItem(
                id: item['vod_id']?.toString() ?? '',
                title: item['vod_name']?.toString() ?? '未知影片',
                posterUrl: item['vod_pic']?.toString(),
                overview: _cleanText(
                  item['vod_content']?.toString() ??
                      item['vod_blurb']?.toString(),
                ),
                year: item['vod_year']?.toString(),
                rating:
                    double.tryParse(item['vod_score']?.toString() ?? '8.5') ??
                        8.5,
                genres: (item['vod_class']?.toString() ?? '全网聚合')
                    .split(',')
                    .where((s) => s.isNotEmpty)
                    .toList(),
              ),
            );
          }
        }
        final validItems = results.where((item) => item.id.isNotEmpty).toList();
        return rawList.isNotEmpty && validItems.isEmpty ? null : validItems;
      }

      final text = data.toString().trim();
      if (text.startsWith('<?xml') ||
          text.startsWith('<rss') ||
          text.startsWith('<root') ||
          text.startsWith('<videos')) {
        try {
          final document = XmlDocument.parse(text);
          final videos = document.findAllElements('video');
          for (final video in videos) {
            final id = _xmlText(video, 'id');
            final title = _xmlText(video, 'name');
            if (id.isEmpty || title.isEmpty) continue;
            results.add(
              MediaItem(
                id: id,
                title: title,
                posterUrl: _emptyToNull(_xmlText(video, 'pic')),
                overview: _emptyToNull(_xmlText(video, 'des')),
                year: _emptyToNull(_xmlText(video, 'year')),
                rating: double.tryParse(_xmlText(video, 'score')),
                genres: _xmlText(video, 'type')
                    .split(',')
                    .where((value) => value.trim().isNotEmpty)
                    .toList(growable: false),
              ),
            );
          }
          if (results.isNotEmpty ||
              (videos.isEmpty &&
                  (document.findAllElements('list').isNotEmpty ||
                      document.rootElement.name.local == 'videos'))) {
            return results;
          }
        } catch (_) {}
      }

      if (text.contains('<html') ||
          text.contains('<body') ||
          text.contains('<div') ||
          text.contains('<a')) {
        final htmlItems = _parseHtmlMediaItems(site, text);
        if (htmlItems.isNotEmpty) return htmlItems;
      }
    } catch (_) {}
    return null;
  }

  List<MediaItem> _parseHtmlMediaItems(TvBoxSite site, String html) {
    final items = <MediaItem>[];
    final seenIds = <String>{};
    final baseUrl = _effectiveHttpApi(site);

    var blocks = RegExp(
      r'''<li\b[^>]*>[\s\S]*?</li>''',
      caseSensitive: false,
    )
        .allMatches(html)
        .map((m) => m.group(0)!)
        .where((b) => b.contains('<img') && b.contains('href'))
        .toList();

    if (blocks.isEmpty) {
      blocks = RegExp(
        r'''<div\b[^>]*class=["'][^"']*(?:module-item|vodlist__box|stui-vodlist__box|video-card|item|col-|oneVideo|article|post)[^"']*["'][^>]*>[\s\S]*?</div>''',
        caseSensitive: false,
      ).allMatches(html).map((m) => m.group(0)!).toList();
    }

    if (blocks.isEmpty) {
      blocks = RegExp(
        r'''<a\b[^>]*(?:class\s*=\s*["'][^"']*(?:module-item|public-list|video-card|item|vodlist_thumb|pack-ykpack|thumb)[^"']*["'])[^>]*>[\s\S]*?</a>''',
        caseSensitive: false,
      ).allMatches(html).map((m) => m.group(0)!).toList();
    }

    if (blocks.isEmpty) {
      blocks = RegExp(
        r'''<a\b[^>]*href=["']([^"']*(?:movie|vod|detail|v_|play|show|video)[^"']*)["'][^>]*>[\s\S]*?<img\b[^>]*>[\s\S]*?</a>''',
        caseSensitive: false,
      ).allMatches(html).map((m) => m.group(0)!).toList();
    }

    for (final block in blocks) {
      final linkMatch = RegExp(
            r'''href=["']([^"']*(?:movie|vod|detail|v_|play|show|video|\.html)[^"']*)["']''',
            caseSensitive: false,
          ).firstMatch(block) ??
          RegExp(r'''href=["']([^"'#]+)["']''', caseSensitive: false)
              .firstMatch(block);
      final href = linkMatch?.group(1)?.trim() ?? '';

      final titleMatch = RegExp(r'''alt=["']([^"']+)["']''',
                  caseSensitive: false)
              .firstMatch(block) ??
          RegExp(r'''title=["']([^"']+)["']''', caseSensitive: false)
              .firstMatch(block) ??
          RegExp(r'''<h\d[^>]*>(?:<a[^>]*>)?([^<]+)''', caseSensitive: false)
              .firstMatch(block) ??
          RegExp(r'''<span\b[^>]*class=["'][^"']*title[^"']*["'][^>]*>([^<]+)</span>''',
                  caseSensitive: false)
              .firstMatch(block) ??
          RegExp(r'''<div\b[^>]*class=["'][^"']*title[^"']*["'][^>]*>([^<]+)</div>''',
                  caseSensitive: false)
              .firstMatch(block);
      final title = titleMatch?.group(1)?.trim() ?? '';

      final picMatch = RegExp(
            r'''(?:data-original|data-src|data-echo|src)=["']([^"']+\.(?:jpg|jpeg|png|webp|gif)[^"']*)["']''',
            caseSensitive: false,
          ).firstMatch(block) ??
          RegExp(
            r'''(?:data-original|data-src|data-echo|src)=["']([^"']+)["']''',
            caseSensitive: false,
          ).firstMatch(block);
      final pic = picMatch?.group(1)?.trim() ?? '';

      if (href.isEmpty || title.isEmpty || href.startsWith('javascript:')) {
        continue;
      }
      final fullUrl = baseUrl.isNotEmpty
          ? Uri.tryParse(baseUrl)?.resolve(href).toString() ?? href
          : href;
      if (!seenIds.add(fullUrl)) continue;

      final fullPic = pic.isNotEmpty && baseUrl.isNotEmpty
          ? Uri.tryParse(baseUrl)?.resolve(pic).toString() ?? pic
          : pic;

      items.add(
        MediaItem(
          id: fullUrl,
          title: title.replaceAll(RegExp(r'<[^>]+>'), '').trim(),
          posterUrl: fullPic.isNotEmpty ? fullPic : null,
          genres: const <String>['全网聚合'],
        ),
      );
    }

    return items;
  }

  List<TvBoxCategory> _parseMacCmsCategories(dynamic data) {
    if (data is String &&
        RegExp(r'<(?:!doctype\s+html|html|body|script)\b', caseSensitive: false)
            .hasMatch(data)) {
      // 失效域名和风控页常返回 200；它们不能被登记成成功的 CMS 响应。
      throw const FormatException('CMS 分类接口返回了网页');
    }
    try {
      final decoded = data is String && data.trimLeft().startsWith('{')
          ? json.decode(data)
          : data;
      if (decoded is Map<String, dynamic> && decoded['class'] is List) {
        return (decoded['class'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(TvBoxCategory.fromJson)
            .where((category) => category.id.isNotEmpty)
            .toList(growable: false);
      }
      final xmlText = data?.toString().trim() ?? '';
      if (xmlText.startsWith('<?xml') ||
          xmlText.startsWith('<rss') ||
          xmlText.startsWith('<root')) {
        try {
          return XmlDocument.parse(xmlText)
              .findAllElements('ty')
              .map(
                (element) => TvBoxCategory(
                  id: element.getAttribute('id')?.trim() ?? '',
                  name: element.innerText.trim(),
                ),
              )
              .where((category) => category.id.isNotEmpty)
              .toList(growable: false);
        } catch (_) {}
      }
    } catch (_) {}
    return <TvBoxCategory>[];
  }

  /// Fetches media playback candidates and episodes for a media item under a specific site.
  Future<List<PlaybackCandidate>> fetchMediaCandidates(
    TvBoxSite site,
    MediaItem item,
  ) async {
    if (!site.isRuntimeSupported) return const <PlaybackCandidate>[];
    if (_isSourceCoolingDown(site)) return const <PlaybackCandidate>[];

    if (LiveToVodSpiderAdapter.supports(site)) {
      try {
        return await LiveToVodSpiderAdapter(_dio).fetchCandidates(site, item);
      } catch (error) {
        _recordSourceFailure(site, 'live2vod 详情', error);
        return const <PlaybackCandidate>[];
      }
    }

    if (TuxiaobeiDartSpiderAdapter.supports(site)) {
      try {
        return TuxiaobeiDartSpiderAdapter(_dio).fetchCandidates(site, item);
      } catch (error) {
        _recordSourceFailure(site, '兔小贝详情', error);
        return const <PlaybackCandidate>[];
      }
    }

    // 内置 CCTV 只按显式 key/id 分派，标准 type=4 交给 T4 HTTP adapter。
    if (item.id.startsWith('cctv_album_') || site.key == 'cctv_vod') {
      if (PythonCompatSpiderAdapter.supports(site)) {
        return _pythonAdapter.fetchCandidates(item);
      }
      final albumId = item.id.replaceFirst('cctv_album_', '');
      final cctvCandidate = await _cctvAdapter.fetchAlbumEpisodes(albumId);
      if (cctvCandidate != null && cctvCandidate.episodes.isNotEmpty) {
        return <PlaybackCandidate>[cctvCandidate];
      }
      return <PlaybackCandidate>[];
    }

    if (XbpqDartSpiderAdapter.supports(site)) {
      try {
        return await XbpqDartSpiderAdapter(_dio).fetchCandidates(site, item);
      } catch (error) {
        _recordSourceFailure(site, 'Dart XBPQ 详情', error);
        return const <PlaybackCandidate>[];
      }
    }
    if (AppYsV2DartSpiderAdapter.supports(site)) {
      try {
        return await AppYsV2DartSpiderAdapter(_dio).fetchCandidates(site, item);
      } catch (error) {
        _recordSourceFailure(site, 'Dart AppYsV2 详情', error);
        return const <PlaybackCandidate>[];
      }
    }
    if (_dexAdapter.supports(site) && !BilibiliSpiderAdapter.supports(site)) {
      try {
        return await _dexAdapter.fetchCandidates(site, item);
      } catch (error) {
        _recordSourceFailure(site, 'Dex 详情', error);
        return const <PlaybackCandidate>[];
      }
    }

    if (BilibiliSpiderAdapter.supports(site)) {
      try {
        return await BilibiliSpiderAdapter(_dio).fetchCandidates(site, item);
      } catch (error) {
        _recordSourceFailure(site, '详情', error);
        return const <PlaybackCandidate>[];
      }
    }
    if (T4HttpSpiderAdapter.supports(site)) {
      try {
        return await T4HttpSpiderAdapter(_dio).fetchCandidates(site, item);
      } catch (error) {
        _recordSourceFailure(site, '详情', error);
        return const <PlaybackCandidate>[];
      }
    }

    final httpApi = _effectiveHttpApi(site);
    if (httpApi.isEmpty || site.type == 4) {
      return <PlaybackCandidate>[];
    }
    if (_isSourceCoolingDown(site)) return <PlaybackCandidate>[];
    try {
      final targetUrl = item.id.startsWith('http') ? item.id : httpApi;
      final response = await _dio.get<dynamic>(
        targetUrl,
        queryParameters: item.id.startsWith('http')
            ? null
            : <String, dynamic>{
                'ac': 'detail',
                'ids': item.id,
              },
      );
      var candidates = _parseMacCmsCandidates(
        site,
        response.data,
        currentUrl: targetUrl,
      );
      if (candidates.isEmpty && response.data != null) {
        candidates = _parseHtmlCandidates(
          site,
          response.data.toString(),
          targetUrl,
        );
      }
      _recordSourceSuccess(site);
      return candidates;
    } catch (error) {
      _recordSourceFailure(site, '详情', error);
      return <PlaybackCandidate>[];
    }
  }

  @visibleForTesting
  List<PlaybackCandidate> parseMacCmsCandidates(
    TvBoxSite site,
    dynamic data, {
    String currentUrl = '',
  }) =>
      _parseMacCmsCandidates(site, data, currentUrl: currentUrl);

  List<PlaybackCandidate> _parseMacCmsCandidates(
    TvBoxSite site,
    dynamic data, {
    String currentUrl = '',
  }) {
    final records = <Map<String, String>>[];
    try {
      final decoded = data is String && data.trimLeft().startsWith('{')
          ? json.decode(data)
          : data;
      if (decoded is Map<String, dynamic> && decoded['list'] is List) {
        for (final item in decoded['list'] as List<dynamic>) {
          if (item is! Map) continue;
          records.add(<String, String>{
            'from': item['vod_play_from']?.toString() ?? '',
            'url': item['vod_play_url']?.toString() ?? '',
          });
        }
      } else {
        final xmlText = data?.toString().trim() ?? '';
        if (xmlText.startsWith('<?xml') ||
            xmlText.startsWith('<rss') ||
            xmlText.startsWith('<root') ||
            xmlText.startsWith('<videos')) {
          try {
            final document = XmlDocument.parse(xmlText);
            for (final video in document.findAllElements('video')) {
              final dl = video.findElements('dl').firstOrNull;
              if (dl == null) continue;
              final sources = dl.findElements('dd').toList(growable: false);
              records.add(<String, String>{
                'from': sources
                    .map((source) => source.getAttribute('flag') ?? '默认线路')
                    .join(r'$$$'),
                'url': sources.map((source) => source.innerText).join(r'$$$'),
              });
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    final candidates = <PlaybackCandidate>[];
    for (final record in records) {
      final flags = record['from']!.split(r'$$$');
      final groups = record['url']!.split(r'$$$');
      for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        final flag = groupIndex < flags.length && flags[groupIndex].isNotEmpty
            ? flags[groupIndex]
            : '线路 ${groupIndex + 1}';
        final episodes = <PlaybackEpisode>[];
        for (final rawEpisode in groups[groupIndex].split('#')) {
          final separator = rawEpisode.indexOf(r'$');
          final String name;
          final String rawUrl;
          if (separator > 0 && separator < rawEpisode.length - 1) {
            name = rawEpisode.substring(0, separator).trim();
            rawUrl = rawEpisode.substring(separator + 1).trim();
          } else {
            name = '播放';
            rawUrl = rawEpisode.trim();
          }
          if (rawUrl.isEmpty) continue;
          final parsed = _parsePlayableUrl(
            rawUrl,
            baseUrl: currentUrl.isEmpty ? site.api : currentUrl,
          );
          if (parsed == null) continue;
          final original = PlaybackEpisode(
            name: name.isEmpty ? '播放' : name,
            url: parsed.url,
            headers: parsed.headers,
            sortIndex: episodes.length + 1,
          );
          episodes.add(
            PlaybackEpisode(
              name: original.name,
              url: parsed.url,
              headers: parsed.headers,
              sortIndex: original.sortIndex,
              // CMS 线路也可能是网页或 VIP 地址，只在用户选择时解析。
              resolvePlayback: parsed.url.startsWith('http')
                  ? () => resolveSpiderPlayback(
                        site: site,
                        episode: original,
                        response: {'url': original.url, 'flag': flag},
                        dio: _dio,
                      )
                  : null,
            ),
          );
        }
        if (episodes.isEmpty) continue;
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

  List<PlaybackCandidate> _parseHtmlCandidates(
    TvBoxSite site,
    String html,
    String currentUrl,
  ) {
    final episodes = <PlaybackEpisode>[];
    final seenUrls = <String>{};
    final baseUrl =
        currentUrl.isNotEmpty ? currentUrl : _effectiveHttpApi(site);

    final jsDataMatch = RegExp(
      r'''player_aaaa\s*=\s*\{[^}]*["']url["']\s*:\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (jsDataMatch != null) {
      final streamUrl = jsDataMatch.group(1)?.replaceAll(r'\/', '/') ?? '';
      if (streamUrl.startsWith('http')) {
        episodes.add(
          PlaybackEpisode(
            name: '正片',
            url: streamUrl,
            sortIndex: 1,
          ),
        );
      }
    }

    final playlistMatches = RegExp(
      r'''<(?:div|ul)\b[^>]*class=["'][^"']*(?:play|playlist|anthology|sort-list|plays|con_playlist)[^"']*["'][^>]*>([\s\S]*?)</(?:div|ul)>''',
      caseSensitive: false,
    ).allMatches(html).map((m) => m.group(1)!).toList();

    final searchHtml =
        playlistMatches.isNotEmpty ? playlistMatches.join('\n') : html;

    final anchorPattern = RegExp(
      r'''<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    );
    var epIndex = 1;
    for (final match in anchorPattern.allMatches(searchHtml)) {
      final href = match.group(1)?.trim() ?? '';
      final title =
          match.group(2)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
      if (href.isEmpty || href.startsWith('javascript:') || href == '#') {
        continue;
      }
      if (playlistMatches.isEmpty) {
        final lower = href.toLowerCase();
        if (!lower.contains('play') &&
            !lower.contains('vod') &&
            !lower.contains('watch') &&
            !lower.contains('video') &&
            !lower.contains('v_') &&
            !lower.contains('.html')) {
          continue;
        }
      }
      final playUrl = baseUrl.isNotEmpty
          ? Uri.tryParse(baseUrl)?.resolve(href).toString() ?? href
          : href;
      if (seenUrls.add(playUrl)) {
        episodes.add(
          PlaybackEpisode(
            name: title.isNotEmpty ? title : '第 $epIndex 集',
            url: playUrl,
            sortIndex: epIndex++,
          ),
        );
      }
    }

    if (episodes.isEmpty) {
      final mediaMatches = RegExp(
        r'''https?://[^\s"'<>]+\.(?:m3u8|mp4)(?:\?[^\s"'<>]*)?''',
        caseSensitive: false,
      ).allMatches(html);
      for (final match in mediaMatches) {
        final streamUrl = match.group(0)!;
        if (seenUrls.add(streamUrl)) {
          episodes.add(
            PlaybackEpisode(
              name: '播放源 $epIndex',
              url: streamUrl,
              sortIndex: epIndex++,
            ),
          );
        }
      }
    }

    if (episodes.isEmpty) return const <PlaybackCandidate>[];
    return <PlaybackCandidate>[
      PlaybackCandidate(
        sourceKey: site.key,
        sourceName: site.name,
        lineName: '官方直连',
        episodes: episodes,
      ),
    ];
  }

  /// Concurrently performs federated multi-source search across all enabled TVBox sites.
  Future<List<MediaItem>> federatedSearch(
    List<TvBoxSite> sites,
    String keyword,
  ) async {
    final cleanKey = keyword.trim();
    if (cleanKey.isEmpty) return <MediaItem>[];

    final futures = <String, Future<List<MediaItem>>>{};

    if (sites.any((site) =>
        site.key == 'cctv_vod' && site.searchable && site.isRuntimeSupported)) {
      futures['cctv_vod'] = _cctvAdapter
          .fetchAlbumList(
            channelId: CctvVodAdapter.channelAnimation,
            firstCategory: '动画片',
            pageSize: 10,
          )
          .then((list) => list
              .where((item) =>
                  item.title.toLowerCase().contains(cleanKey.toLowerCase()) ||
                  (item.overview
                          ?.toLowerCase()
                          .contains(cleanKey.toLowerCase()) ??
                      false))
              .toList())
          .catchError((_) => <MediaItem>[]);
    }

    // Concurrent supported site queries
    for (final s in sites) {
      if (!s.searchable || !s.isRuntimeSupported || s.key == 'cctv_vod') {
        continue;
      }
      futures[s.key] = searchSite(s, cleanKey);
    }

    final results = await Future.wait(futures.values);

    // 同名翻拍拥有独立 ID；ID 仅在站内唯一，跨站结果不能互相吞掉。
    final unique = <MediaItem>[];
    for (final siteResults in results) {
      final seenIds = <String>{};
      for (final item in siteResults) {
        if (seenIds.add(item.id)) unique.add(item);
      }
    }

    return unique;
  }

  String _xmlText(XmlElement parent, String name) {
    return parent.findElements(name).firstOrNull?.innerText.trim() ?? '';
  }

  String? _emptyToNull(String value) => value.isEmpty ? null : value;

  String? _cleanText(String? value) {
    if (value == null) return null;
    final cleaned = value
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  bool _isSourceCoolingDown(TvBoxSite site) {
    final retryAt = _sourceCooldowns[site.key];
    if (retryAt == null) return false;
    if (DateTime.now().isBefore(retryAt)) return true;
    _sourceCooldowns.remove(site.key);
    return false;
  }

  void _recordSourceSuccess(TvBoxSite site) {
    _sourceCooldowns.remove(site.key);
    _sourceFailureCounts.remove(site.key);
  }

  /// 单源故障熔断该站点（指数退避 1分/3分/10分），避免 TLS/5xx/404 在并发路径中形成请求风暴。
  void _recordSourceFailure(
    TvBoxSite site,
    String operation,
    Object error,
  ) {
    final failCount = (_sourceFailureCounts[site.key] ?? 0) + 1;
    _sourceFailureCounts[site.key] = failCount;
    final cooldownDuration = failCount >= 3
        ? const Duration(minutes: 10)
        : (failCount == 2
            ? const Duration(minutes: 3)
            : const Duration(minutes: 1));

    _sourceCooldowns[site.key] = DateTime.now().add(cooldownDuration);

    var reason = '网络请求失败';
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        reason = 'HTTP $statusCode';
      } else if (error.error != null) {
        reason = error.error.toString().split(RegExp(r'\r?\n')).first;
      } else {
        reason = error.type.name;
      }
    }
    final minutes = cooldownDuration.inMinutes;
    debugPrint(
      '[TVBox][${site.name}] $operation失败(第$failCount次)，$minutes分钟内暂停请求：$reason',
    );
  }

  bool _isDirectPlayableUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        <String>{'http', 'https', 'rtmp', 'rtsp'}.contains(uri.scheme);
  }

  ({String url, Map<String, String>? headers})? _parsePlayableUrl(
    String raw, {
    required String baseUrl,
  }) {
    var url = raw;
    Map<String, String>? headers;
    final jsonHeaderIndex = raw.indexOf('|{');
    final suffixHeaderIndex = raw.indexOf(';{');
    final headerIndex =
        jsonHeaderIndex >= 0 ? jsonHeaderIndex : suffixHeaderIndex;
    if (headerIndex >= 0 && raw.endsWith('}')) {
      url = raw.substring(0, headerIndex).trim();
      final payload = raw.substring(headerIndex + 1);
      try {
        if (jsonHeaderIndex >= 0) {
          final decoded = json.decode(payload);
          if (decoded is Map) {
            headers = decoded.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            );
          }
        } else {
          headers = <String, String>{};
          final content = payload.substring(1, payload.length - 1);
          for (final pair in content.split('&')) {
            final separator = pair.indexOf('=');
            if (separator <= 0) continue;
            headers[pair.substring(0, separator)] =
                Uri.decodeComponent(pair.substring(separator + 1));
          }
        }
      } catch (_) {
        headers = null;
      }
    } else {
      final pipe = raw.indexOf('|');
      if (pipe >= 0) {
        url = raw.substring(0, pipe).trim();
        try {
          headers = Uri.splitQueryString(raw.substring(pipe + 1));
        } on FormatException {
          return null;
        }
      }
    }
    if (url.startsWith('/') || url.startsWith('./') || url.startsWith('../')) {
      url = Uri.parse(baseUrl).resolve(url).toString();
    }
    if (!_isDirectPlayableUrl(url)) return null;
    return (url: url, headers: headers?.isEmpty == true ? null : headers);
  }
}
