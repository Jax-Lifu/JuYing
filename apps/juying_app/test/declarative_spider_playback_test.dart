import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/app_ys_v2_dart_spider_adapter.dart';
import 'package:juying/features/tvbox/services/xbpq_dart_spider_adapter.dart';

void main() {
  test('XBPQ resolves relative templates and removes trailing rule flags',
      () async {
    final requests = <RequestOptions>[];
    final adapter = XbpqDartSpiderAdapter(_dio(
        requests,
        (_) => '''
      <li><a href="/film/1" title="Film"><img src="/p.jpg"></a></li>
    '''));
    final site = _xbpq(<String, String>{
      '主页url': 'https://video.test/',
      '分类url': '/{cateId}/page/{catePg}?class={class}&lang={lang};;mrc',
      '数组': '<li>&&</li>',
    });
    final items = await adapter.fetchCategory(site, 'movie/series', page: 2);
    expect(requests.single.uri.toString(),
        'https://video.test/movie/series/page/2?class=&lang=');
    expect(items.single.id, 'https://video.test/film/1');
  });

  test('XBPQ POST search and composite extraction follow declared rules',
      () async {
    final requests = <RequestOptions>[];
    final adapter = XbpqDartSpiderAdapter(_dio(
        requests,
        (_) => '''
      prefix <section><article data-id="123"><h2 class="title">A &amp; B</h2>
      <img src="/p.jpg"></article></section> suffix
    '''));
    final site = _xbpq(<String, String>{
      '主页url': 'https://video.test/',
      '搜索url': '/search;post;wd={wd}&page={pg}',
      '搜索二次截取': '<section>&&</section>',
      '搜索数组': '<article&&</article>',
      '搜索标题': '<h*>&&</h',
      '搜索链接': '/detail/+data-id="&&"+.html',
      '搜索图片': 'src="&&"',
    });
    final items = await adapter.search(site, 'A&B', page: 3);
    expect(requests.single.method, 'POST');
    expect(requests.single.uri.toString(), 'https://video.test/search');
    expect(requests.single.data, 'wd=A%26B&page=3');
    expect(items.single.id, 'https://video.test/detail/123.html');
    expect(items.single.title, 'A & B');
  });

  test('XBPQ preserves lines and resolves only the selected encrypted episode',
      () async {
    final requests = <RequestOptions>[];
    final media = base64.encode(utf8
        .encode(Uri.encodeComponent('https://cdn.test/video.m3u8?x=1&y=2')));
    final adapter = XbpqDartSpiderAdapter(_dio(requests, (request) {
      if (request.uri.path == '/detail/1') {
        return '<h3>Line A</h3><h3>Line B</h3>'
            '<ul class="episodes"><a href="/e/1">E1</a><a href="/e/2">E2</a></ul>'
            '<ul class="episodes"><a href="/e/3">E1</a></ul>';
      }
      return '<script>var player_aaaa={"encrypt":2,"url":"$media"};</script>';
    }));
    final site = _xbpq(<String, String>{
      '线路数组': '<h3>&&</h3>',
      '线路标题': '>&&<',
      '播放数组': '<ul class="episodes">&&</ul>',
      '播放列表': '<a&&/a>',
      '播放标题': '>&&<',
      '播放链接': 'href="&&"',
      '播放请求头': r'User-Agent$MOBILE_UA#Referer$https://video.test/',
    });
    final lines = await adapter.fetchCandidates(site,
        const MediaItem(id: 'https://video.test/detail/1', title: 'Film'));
    expect(requests, hasLength(1));
    expect(lines.map((line) => line.lineName), <String>['Line A', 'Line B']);
    expect(lines.first.episodes, hasLength(2));
    final result = await lines.first.episodes[1].resolvePlayback!();
    expect(requests.map((request) => request.uri.path),
        <String>['/detail/1', '/e/2']);
    expect(result.url, 'https://cdn.test/video.m3u8?x=1&y=2');
    expect(result.requiresWebView, isFalse);
    expect(result.headers!['Referer'], 'https://video.test/');
    expect(result.headers!['User-Agent'], contains('Android'));
  });

  test('XBPQ direct playback pages use declared wildcard jump rule', () async {
    final requests = <RequestOptions>[];
    final adapter = XbpqDartSpiderAdapter(_dio(
        requests,
        (_) =>
            '<video controls="true" preload="none" src="/media/clip.mp4"></video>'));
    final lines = await adapter.fetchCandidates(
      _xbpq(<String, String>{
        '直接播放': '1',
        '跳转播放链接': '<video controls="true*src="&&"',
      }),
      const MediaItem(id: 'https://video.test/watch/1', title: 'Clip'),
    );
    expect(requests, isEmpty);
    final resolved = await lines.single.episodes.single.resolvePlayback!();
    expect(requests, hasLength(1));
    expect(resolved.url, 'https://video.test/media/clip.mp4');
    expect(resolved.requiresWebView, isFalse);
  });

  for (final encryption in <int>[1, 2]) {
    test('XBPQ decodes encrypt=$encryption before following player URL rules',
        () async {
      final requests = <RequestOptions>[];
      const mediaUrl = 'https://cdn.test/video.m3u8?x=1&y=2';
      final encoded = Uri.encodeComponent(mediaUrl);
      final playerUrl =
          encryption == 2 ? base64.encode(utf8.encode(encoded)) : encoded;
      final adapter = XbpqDartSpiderAdapter(_dio(requests, (_) {
        return '<script>var player_aaaa=${json.encode({
              'encrypt': encryption,
              'url': playerUrl,
            })};</script>';
      }));
      final lines = await adapter.fetchCandidates(
        _xbpq(<String, String>{
          '直接播放': '1',
          '跳转播放链接': 'var player_*url":"&&"',
        }),
        const MediaItem(id: 'https://video.test/watch/1', title: 'Clip'),
      );
      final resolved = await lines.single.episodes.single.resolvePlayback!();
      expect(requests, hasLength(1));
      expect(resolved.url, mediaUrl);
      expect(resolved.requiresWebView, isFalse);
    });
  }

  test('XBPQ unresolved playback HTML explicitly requests WebView', () async {
    final requests = <RequestOptions>[];
    final adapter = XbpqDartSpiderAdapter(_dio(
        requests,
        (_) =>
            '<iframe src="https://parser.test/page?url=clip.mp4"></iframe>'));
    final lines = await adapter.fetchCandidates(
      _xbpq(<String, String>{'直接播放': '1'}),
      const MediaItem(id: 'https://video.test/watch/1', title: 'Clip'),
    );
    final result = await lines.single.episodes.single.resolvePlayback!();
    expect(result.requiresWebView, isTrue);
    expect(result.url, 'https://video.test/watch/1');
  });

  test(
      'App API retains opaque episode IDs until selected and preserves headers',
      () async {
    final requests = <RequestOptions>[];
    final adapter = AppYsV2DartSpiderAdapter(_dio(requests, (request) {
      if (request.uri.path.endsWith('video_detail')) {
        return <String, dynamic>{
          'data': <String, dynamic>{
            'vod_url_with_player': <Map<String, String>>[
              <String, String>{
                'code': 'test',
                'url': r'E1$opaque1#E2$opaque2',
                'parse_api': 'https://parser.test/?url=',
              },
            ],
          },
        };
      }
      return <String, dynamic>{
        'url': 'https://cdn.test/stream',
        'parse': 0,
        'header': <String, String>{'Referer': 'https://video.test/'},
      };
    }));
    const site = TvBoxSite(
      key: 'app',
      name: 'App',
      api: 'csp_AppYsV2',
      ext: 'https://app.test/api/',
    );
    final lines = await adapter.fetchCandidates(
        site, const MediaItem(id: '1', title: 'Film'));
    expect(requests, hasLength(1));
    expect(lines.single.episodes, hasLength(2));
    final result = await lines.single.episodes[1].resolvePlayback!();
    expect(requests, hasLength(2));
    expect(requests.last.uri.queryParameters['url'], 'opaque2');
    expect(result.url, 'https://cdn.test/stream');
    expect(result.requiresWebView, isFalse);
    expect(result.headers!['Referer'], 'https://video.test/');
  });
}

TvBoxSite _xbpq(Map<String, String> rules) => TvBoxSite(
      key: 'xbpq',
      name: 'XBPQ',
      api: 'csp_XBPQ',
      ext: <String, String>{'分类': r'Film$1', ...rules},
    );

Dio _dio(
    List<RequestOptions> requests, Object Function(RequestOptions) response) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    requests.add(options);
    handler.resolve(Response<dynamic>(
      requestOptions: options,
      statusCode: 200,
      data: response(options),
    ));
  }));
  return dio;
}
