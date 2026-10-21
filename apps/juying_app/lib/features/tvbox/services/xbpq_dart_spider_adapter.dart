import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/spider_playback_response.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_runtime_capability.dart';

/// Cross-platform subset of the declarative XBPQ Spider protocol.
///
/// XBPQ is suitable for a shared Dart implementation because its `ext` describes requests and
/// extraction boundaries as data. This adapter intentionally does not emulate arbitrary Java;
/// unsupported rule operators fail closed instead of executing the accompanying Dex package.
class XbpqDartSpiderAdapter {
  XbpqDartSpiderAdapter(this._dio);

  final Dio _dio;
  final Map<String, Map<String, String>> _ruleCache =
      <String, Map<String, String>>{};

  static bool supports(TvBoxSite site) =>
      site.type == 3 &&
      TvBoxSpiderRuntimeCapability.supportsXbpq(api: site.api, ext: site.ext);
  Future<List<TvBoxCategory>> fetchCategories(TvBoxSite site) async {
    final rules = await _loadRules(site);
    final names = _splitCategories(rules['分类'] ?? '');
    final values = _splitCategories(rules['分类值'] ?? '');
    final categories = <TvBoxCategory>[];
    for (var index = 0; index < names.length; index++) {
      final pair = names[index].split(r'$');
      final name = pair.first.trim();
      final id = pair.length > 1
          ? pair.last.trim()
          : index < values.length
              ? values[index].trim()
              : name;
      if (name.isNotEmpty && id.isNotEmpty) {
        categories.add(TvBoxCategory(id: id, name: name));
      }
    }
    return categories;
  }

  Future<List<MediaItem>> fetchCategory(
    TvBoxSite site,
    String categoryId, {
    int page = 1,
  }) async {
    final rules = await _loadRules(site);
    final template = rules['分类url'] ?? rules['分类URL'] ?? '';
    if (template.isEmpty) return const <MediaItem>[];
    final url = _renderUrl(template, categoryId: categoryId, page: page);
    return _fetchAndParseList(site, rules, url, search: false);
  }

  Future<List<MediaItem>> search(
    TvBoxSite site,
    String keyword, {
    int page = 1,
  }) async {
    final rules = await _loadRules(site);
    final template = rules['搜索url'] ?? rules['搜索URL'] ?? '';
    if (template.isEmpty) return const <MediaItem>[];
    final url = _renderUrl(template, keyword: keyword, page: page);
    return _fetchAndParseList(site, rules, url, search: true);
  }

  Future<List<PlaybackCandidate>> fetchCandidates(
    TvBoxSite site,
    MediaItem item,
  ) async {
    final rules = await _loadRules(site);
    PlaybackEpisode episode(String name, String url, int index) {
      final original = PlaybackEpisode(
        name: name,
        url: url,
        headers: _parseHeaders(rules['播放请求头']),
        sortIndex: index,
      );
      return PlaybackEpisode(
        name: name,
        url: url,
        headers: original.headers,
        sortIndex: index,
        resolvePlayback: () => _resolvePlayback(site, original, rules),
      );
    }

    if (rules['直接播放'] == '1' || _isMediaUrl(item.id)) {
      return <PlaybackCandidate>[
        PlaybackCandidate(
          sourceKey: '${site.key}_xbpq_0',
          sourceName: site.name,
          lineName: site.name,
          episodes: <PlaybackEpisode>[episode(item.title, item.id, 1)],
        ),
      ];
    }
    final html = (await _get(item.id, rules)).data?.toString() ?? '';
    final lineRule = rules['线路数组'] ?? '';
    final lineBlocks = _extractBlocks(html, lineRule, filter: false);
    final arrayRule = rules['播放数组'] ?? '';
    var groups = _extractBlocks(html, arrayRule);
    if (groups.isEmpty && arrayRule.isEmpty) groups = <String>[html];
    final candidates = <PlaybackCandidate>[];
    for (var index = 0; index < groups.length; index++) {
      if (index < lineBlocks.length &&
          !_passesFilters(lineBlocks[index], lineRule)) {
        continue;
      }
      final lineName = index < lineBlocks.length
          ? _stripTags(_pick(lineBlocks[index], rules['线路标题'] ?? '>&&<'))
          : '';
      final seen = <String>{};
      final episodes = <PlaybackEpisode>[];
      final blocks = _extractBlocks(groups[index], rules['播放列表'] ?? '<a&&/a>');
      for (final block in blocks) {
        final link = _pick(block, rules['播放链接'] ?? 'href="&&"');
        final name = _stripTags(_pick(block, rules['播放标题'] ?? '>&&<'));
        if (link.isEmpty || name.isEmpty) continue;
        if (arrayRule.isEmpty && !_looksPlayableLink(link)) continue;
        final url = _resolveUrl(
          rules['播放链接前缀'] ?? item.id,
          link,
        );
        if (!_isHttpUrl(url) || !seen.add(url)) continue;
        episodes.add(episode(name, url, episodes.length + 1));
      }
      if (episodes.isEmpty) continue;
      candidates.add(PlaybackCandidate(
        sourceKey: '${site.key}_xbpq_$index',
        sourceName: site.name,
        lineName: lineName.isEmpty ? '线路 ${index + 1}' : lineName,
        episodes: rules['倒序'] == '1' ? episodes.reversed.toList() : episodes,
      ));
    }
    // Some declarative sources link list cards directly to a single player page.
    if (candidates.isEmpty &&
        ((rules['跳转播放链接'] ?? '').isNotEmpty ||
            html.contains('player_') ||
            RegExp(r'<(?:video|audio)\b').hasMatch(html))) {
      candidates.add(PlaybackCandidate(
        sourceKey: '${site.key}_xbpq_0',
        sourceName: site.name,
        lineName: site.name,
        episodes: <PlaybackEpisode>[episode(item.title, item.id, 1)],
      ));
    }
    return candidates;
  }

  Future<List<MediaItem>> _fetchAndParseList(
    TvBoxSite site,
    Map<String, String> rules,
    String url, {
    required bool search,
  }) async {
    Response<dynamic>? response;
    try {
      response = await _get(url, rules, search: search);
    } catch (_) {}

    if (response == null || response.data == null) return const <MediaItem>[];

    final rawData = response.data;
    if ((!search || (rules['搜索数组'] ?? '').isEmpty) &&
        (rawData is Map ||
            (rawData is String && rawData.trimLeft().startsWith('{')))) {
      try {
        final decoded = rawData is String ? json.decode(rawData) : rawData;
        if (decoded is Map<String, dynamic>) {
          final jsonItems = _parseJsonMediaItems(decoded, url);
          if (jsonItems.isNotEmpty) return jsonItems;
        }
      } catch (_) {}
    }

    final html = rawData is Map || rawData is List
        ? json.encode(rawData)
        : rawData.toString();
    final prefix = search ? '搜索' : '';
    String? scopedRule(String suffix) => rules['$prefix$suffix'];
    final arrayRule = scopedRule('数组') ?? rules['数组'] ?? '';
    final scopeRule =
        scopedRule('二次截取') ?? rules['数组二次截取'] ?? rules['二次截取'] ?? '';
    final source = scopeRule.isEmpty ? html : _pick(html, scopeRule);
    var blocks = _extractBlocks(source, arrayRule);
    if (blocks.isEmpty) {
      blocks = RegExp(
        r'''<li\b[^>]*>[\s\S]*?</li>''',
        caseSensitive: false,
      )
          .allMatches(source)
          .map((m) => m.group(0)!)
          .where((b) => b.contains('<img') && b.contains('href'))
          .toList();
    }
    if (blocks.isEmpty) {
      blocks = RegExp(
        r'''<div\b[^>]*class=["'][^"']*(?:module-item|vodlist__box|stui-vodlist__box|video-card|item|col-|oneVideo|article|post)[^"']*["'][^>]*>[\s\S]*?</div>''',
        caseSensitive: false,
      ).allMatches(source).map((m) => m.group(0)!).toList();
    }
    if (blocks.isEmpty) {
      blocks = RegExp(
        r'''<a\b[^>]*(?:class\s*=\s*["'][^"']*(?:module-item|public-list|video-card|item|vodlist_thumb|pack-ykpack|thumb)[^"']*["'])[^>]*>[\s\S]*?</a>''',
        caseSensitive: false,
      ).allMatches(source).map((m) => m.group(0)!).toList();
    }
    if (blocks.isEmpty) {
      blocks = RegExp(
        r'''<a\b[^>]*href=["']([^"']*(?:movie|vod|detail|v_|play|show|video)[^"']*)["'][^>]*>[\s\S]*?<img\b[^>]*>[\s\S]*?</a>''',
        caseSensitive: false,
      ).allMatches(source).map((m) => m.group(0)!).toList();
    }

    final items = <MediaItem>[];
    final seen = <String>{};
    for (final block in blocks) {
      var link = _pick(
        block,
        scopedRule('链接') ?? rules['链接'] ?? 'href="&&"',
      );
      var title = _pick(
        block,
        scopedRule('标题') ?? rules['标题'] ?? 'title="&&"',
      );
      if (link.isEmpty) {
        link = RegExp(
              r'''href=["']([^"']*(?:movie|vod|detail|v_|play|show|video|\.html)[^"']*)["']''',
              caseSensitive: false,
            ).firstMatch(block)?.group(1) ??
            RegExp(r'''href=["']([^"'#]+)["']''', caseSensitive: false)
                .firstMatch(block)
                ?.group(1) ??
            '';
      }
      if (title.isEmpty) {
        title = RegExp(r'''alt=["']([^"']+)["']''', caseSensitive: false)
                .firstMatch(block)
                ?.group(1) ??
            RegExp(r'''title=["']([^"']+)["']''', caseSensitive: false)
                .firstMatch(block)
                ?.group(1) ??
            RegExp(r'''<h\d[^>]*>(?:<a[^>]*>)?([^<]+)''', caseSensitive: false)
                .firstMatch(block)
                ?.group(1) ??
            RegExp(r'''<span\b[^>]*class=["'][^"']*title[^"']*["'][^>]*>([^<]+)</span>''',
                    caseSensitive: false)
                .firstMatch(block)
                ?.group(1) ??
            _stripTags(block);
      }
      if (link.isEmpty || title.isEmpty || link.startsWith('javascript:')) {
        continue;
      }
      final baseUrl = _requestUrl(url, rules);
      final id = _resolveUrl(baseUrl, link);
      if (!seen.add(id)) continue;
      var image = _pick(
        block,
        scopedRule('图片') ?? rules['图片'] ?? 'data-original="&&"',
      );
      if (image.isEmpty) {
        image = RegExp(
              r'''(?:data-original|data-src|data-echo|src)=["']([^"']+\.(?:jpg|jpeg|png|webp|gif)[^"']*)["']''',
              caseSensitive: false,
            ).firstMatch(block)?.group(1) ??
            RegExp(
              r'''(?:data-original|data-src|data-echo|src)=["']([^"']+)["']''',
              caseSensitive: false,
            ).firstMatch(block)?.group(1) ??
            '';
      }
      final remark = _pick(
        block,
        scopedRule('副标题') ?? rules['副标题'] ?? '',
      );
      items.add(
        MediaItem(
          id: id,
          title: _stripTags(title),
          posterUrl: image.isEmpty ? null : _resolveUrl(baseUrl, image),
          overview: remark.isEmpty ? null : _stripTags(remark),
        ),
      );
    }
    return items;
  }

  static List<MediaItem> _parseJsonMediaItems(
    Map<String, dynamic> json,
    String baseUrl,
  ) {
    final list = json['list'] ?? json['data'];
    if (list is! List) return const <MediaItem>[];
    final items = <MediaItem>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final id = (raw['vod_id'] ?? raw['id'] ?? raw['nextlink'] ?? '')
          .toString()
          .trim();
      final title = (raw['vod_name'] ?? raw['name'] ?? raw['title'] ?? '')
          .toString()
          .trim();
      if (id.isEmpty || title.isEmpty) continue;
      final pic =
          (raw['vod_pic'] ?? raw['pic'] ?? raw['img'] ?? '').toString().trim();
      final remark = (raw['vod_remarks'] ?? raw['remarks'] ?? raw['note'] ?? '')
          .toString()
          .trim();
      items.add(
        MediaItem(
          id: id.startsWith('http') ? id : _resolveUrl(baseUrl, id),
          title: title,
          posterUrl: pic.isNotEmpty ? _resolveUrl(baseUrl, pic) : null,
          overview: remark.isNotEmpty ? remark : null,
        ),
      );
    }
    return items;
  }

  Future<Map<String, String>> _loadRules(TvBoxSite site) async {
    final cached = _ruleCache[site.key];
    if (cached != null) return cached;
    Object? source = site.ext;
    if (source is String && _isHttpUrl(source)) {
      final response = await _dio.get<dynamic>(
        source,
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 7),
        ),
      );
      source = response.data;
    }
    final rules = TvBoxSpiderRuntimeCapability.parseXbpqRules(source);
    if (!TvBoxSpiderRuntimeCapability.hasXbpqRules(rules)) {
      throw UnsupportedError('该配置不包含已支持的 XBPQ 规则。');
    }
    // 缺失分类或 URL 规则必须保持缺失，不能编造 MacCMS 页面后伪报源可用。
    _ruleCache[site.key] = rules;
    return rules;
  }

  Future<Response<dynamic>> _get(String url, Map<String, String> rules,
      {bool search = false}) {
    final parts = url.split(RegExp(';post;', caseSensitive: false));
    return _dio.request<dynamic>(
      _requestUrl(parts.first, rules),
      data: parts.length > 1 ? parts.sublist(1).join(';post;') : null,
      options: Options(
        method: parts.length > 1 ? 'POST' : 'GET',
        contentType:
            parts.length > 1 ? Headers.formUrlEncodedContentType : null,
        sendTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 6),
        headers: <String, String>{
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          ...?_parseHeaders(rules['请求头']),
          if (search) ...?_parseHeaders(rules['搜索请求头']),
        },
      ),
    );
  }

  static String _requestUrl(String value, Map<String, String> rules) {
    final url = value.split(';;').first.split(';post;').first;
    return _isHttpUrl(url) ? url : _resolveUrl(rules['主页url'] ?? '', url);
  }

  static List<String> _extractBlocks(String input, String rule,
      {bool filter = true}) {
    if (rule.isEmpty) return const <String>[];
    final cleanRule = rule.replaceAll(RegExp(r'\[[^\]]+\]'), '');
    final parts = cleanRule.split('&&');
    if (parts.length < 2 || parts.first.isEmpty || parts.last.isEmpty) {
      return const <String>[];
    }
    final pattern = RegExp(
      '${_boundary(parts.first)}[\\s\\S]*?${_boundary(parts.last)}',
      caseSensitive: false,
    );
    return pattern
        .allMatches(input)
        .map((match) => match.group(0)!)
        .where((block) => !filter || _passesFilters(block, rule))
        .map((block) => _replace(block, rule))
        .toList();
  }

  static String _pick(String input, String rule) {
    if (rule.isEmpty) return '';
    final clean = rule.replaceAll(RegExp(r'\[[^\]]+\]'), '');
    final result = clean.split('+').map((component) {
      final parts = component.split('&&');
      if (parts.length < 2) return component;
      final pattern = RegExp(
        '${parts.first.isEmpty ? '^' : _boundary(parts.first)}'
        '([\\s\\S]*?)'
        '${parts.last.isEmpty ? r'$' : _boundary(parts.last)}',
        caseSensitive: false,
      );
      return pattern.firstMatch(input)?.group(1) ?? '';
    }).join();
    return _replace(result, rule).trim();
  }

  static String _boundary(String value) =>
      value.split('*').map(RegExp.escape).join(r'[\s\S]*?');

  static bool _passesFilters(String value, String rule) {
    final excluded = RegExp(r'\[不包含:([^\]]+)\]').firstMatch(rule)?.group(1);
    final included = RegExp(r'\[包含:([^\]]+)\]').firstMatch(rule)?.group(1);
    return (excluded == null || !excluded.split('#').any(value.contains)) &&
        (included == null || included.split('#').any(value.contains));
  }

  static String _replace(String value, String rule) {
    for (final match in RegExp(r'\[替换:([^\]]+)\]').allMatches(rule)) {
      for (final pair in match.group(1)!.split('#')) {
        final parts = pair.split('>>');
        if (parts.length == 2) {
          value = value.replaceAll(parts.first, parts.last);
        }
      }
    }
    return value;
  }

  Future<PlaybackEpisode> _resolvePlayback(
    TvBoxSite site,
    PlaybackEpisode episode,
    Map<String, String> rules,
  ) async {
    var url = episode.url;
    var flag = '';
    if (!_isMediaUrl(url)) {
      var data = (await _get(url, rules)).data;
      var text = data is Map ? json.encode(data) : data?.toString() ?? '';
      // These are extraction expressions, never JavaScript execution. The
      // bounded three-hop chain is the one described by the XBPQ contract.
      for (final key in <String>[
        '跳转播放链接',
        '二次跳转播放链接',
        '三次跳转播放链接',
      ]) {
        final rule = rules[key] ?? '';
        if (rule.isEmpty) break;
        var next = _pick(text, rule).replaceAll(r'\/', '/');
        if (next.isEmpty) break;
        final player = _playerData(text);
        if (player != null && next == player['url']?.toString()) {
          // A jump rule may extract the encoded player URL verbatim. Decode
          // it before resolving relative paths or issuing the next request.
          next = _decodePlayerUrl(player);
          flag = player['from']?.toString() ?? '';
        }
        url = _resolveUrl(url, next);
        if (_isMediaUrl(url)) break;
        data = (await _get(url, rules)).data;
        text = data is Map ? json.encode(data) : data?.toString() ?? '';
      }
      if (!_isMediaUrl(url)) {
        final player = _playerData(text);
        if (player != null) {
          final playerUrl = _decodePlayerUrl(player);
          flag = player['from']?.toString() ?? '';
          if (playerUrl.isNotEmpty) url = _resolveUrl(url, playerUrl);
        } else {
          final normalized =
              text.replaceAll(r'\/', '/').replaceAll(r'\u0026', '&');
          for (final match in RegExp(
            r'''https?://[^\s"'<>]+\.(?:m3u8|mp4|mp3|m4a|flv)(?:\?[^\s"'<>]*)?''',
            caseSensitive: false,
          ).allMatches(normalized)) {
            if (_isMediaUrl(match.group(0)!)) {
              url = match.group(0)!;
              break;
            }
          }
        }
      }
    }
    return resolveSpiderPlayback(
      site: site,
      episode: episode,
      response: <String, dynamic>{
        'url': url,
        'parse': _isMediaUrl(url) ? 0 : 1,
        if (flag.isNotEmpty && !_isMediaUrl(url)) 'flag': flag,
      },
      dio: _dio,
    );
  }

  static Map? _playerData(String text) {
    final match = RegExp(
      r'player_\w+\s*=\s*(\{[\s\S]*?\})\s*(?:;|<)',
    ).firstMatch(text);
    return match == null ? null : json.decode(match.group(1)!) as Map;
  }

  static String _decodePlayerUrl(Map player) {
    var url = player['url']?.toString() ?? '';
    if (player['encrypt']?.toString() == '2') {
      url = utf8.decode(base64.decode(base64.normalize(url)));
    }
    return <String>['1', '2'].contains(player['encrypt']?.toString())
        ? Uri.decodeComponent(url)
        : url;
  }

  static String _renderUrl(
    String template, {
    String categoryId = '',
    String keyword = '',
    int page = 1,
  }) {
    return template
        .split(';;')
        .first
        .replaceAll('{cateId}',
            categoryId.split('/').map(Uri.encodeComponent).join('/'))
        .replaceAll('{catePg}', '$page')
        .replaceAll('{pg}', '$page')
        .replaceAll('{page}', '$page')
        .replaceAll('{wd}', Uri.encodeComponent(keyword))
        .replaceAll('{searchKey}', Uri.encodeComponent(keyword))
        .replaceAll('{area}', '')
        .replaceAll('{year}', '')
        .replaceAll('{class}', '')
        .replaceAll('{lang}', '')
        .replaceAll('{letter}', '')
        .replaceAll('{by}', '');
  }

  static List<String> _splitCategories(String value) {
    if (value.contains('#')) return value.split('#');
    return value.split('&');
  }

  static Map<String, String>? _parseHeaders(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final result = <String, String>{};
    for (final entry in value.split('#')) {
      final separator =
          entry.contains(r'$') ? entry.indexOf(r'$') : entry.indexOf('@');
      if (separator <= 0) continue;
      result[entry.substring(0, separator).trim()] = entry
          .substring(separator + 1)
          .trim()
          .replaceAll('MOBILE_UA',
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36')
          .replaceAll('PC_UA',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36');
    }
    return result.isEmpty ? null : result;
  }

  static String _resolveUrl(String base, String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri != null && uri.hasScheme) return uri.toString();
    return Uri.parse(base).resolve(value.trim()).toString();
  }

  static String _stripTags(String value) => value
      .replaceAll(RegExp('<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();

  static bool _looksPlayableLink(String value) {
    final lower = value.toLowerCase();
    return lower.contains('play') ||
        lower.contains('vod') ||
        lower.contains('video') ||
        lower.contains('watch') ||
        lower.contains('show') ||
        lower.contains('view') ||
        lower.contains('.html') ||
        lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        _isMediaUrl(lower);
  }

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        <String>{'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty;
  }

  static bool _isMediaUrl(String value) {
    return _isHttpUrl(value) &&
        RegExp(
          r'\.(m3u8|mp4|mp3|m4a|aac|flac|flv|mpd|mkv|webm|ts)$',
          caseSensitive: false,
        ).hasMatch(Uri.parse(value).path);
  }
}
