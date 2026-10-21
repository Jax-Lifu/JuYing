import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

const _site = TvBoxSite(
  key: 'tuxiaobei_rule',
  name: '兔小贝',
  api: 'https://rules.test/drpy2.min.js',
  ext: 'https://rules.test/js/%E5%85%94%E5%B0%8F%E8%B4%9D.js',
);

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('known Tuxiaobei rule uses Dart without enabling other remote scripts',
      () {
    expect(_site.isRuntimeSupported, isTrue);
    expect(_site.spiderRuntimeCapability.runtimeAvailable, isTrue);
    expect(
      const TvBoxSite(
        key: 'other',
        name: '兔小贝',
        api: 'https://rules.test/drpy2.min.js',
        ext: 'https://rules.test/other.js',
      ).isRuntimeSupported,
      isFalse,
    );
  });

  test(
      'categories and JSONP pages use the official API and preserve pagination',
      () async {
    final requests = <RequestOptions>[];
    final engine = _engine(requests, (request) {
      expect(request.uri.host, 'www.tuxiaobei.com');
      expect(request.uri.path, '/list/mip-data');
      expect(request.queryParameters['typeId'], '2');
      expect(request.queryParameters['page'], '3');
      return '(${json.encode(<String, dynamic>{
            'status': 0,
            'data': <String, dynamic>{
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'video_id': 1037,
                  'name': '数鸭子',
                  'image': 'https://resource-cdn.tuxiaobei.com/cover.png',
                  'duration_string': '01:22',
                },
              ],
            },
          })});';
    });
    final categories = await engine.fetchSiteCategories(_site);
    expect(categories.map((category) => category.id),
        <String>['2', '3', '4', '25']);
    expect(requests, isEmpty);
    final items = await engine.fetchCategoryMedia(_site, '2', page: 3);
    expect(items.single.id, 'https://www.tuxiaobei.com/play/1037');
    expect(items.single.title, '数鸭子');
    expect(items.single.overview, '01:22');
    expect(requests, hasLength(1));
  });

  test('search extracts official play links and decodes HTML text', () async {
    final requests = <RequestOptions>[];
    final engine = _engine(requests, (request) {
      expect(request.uri.pathSegments, <String>['search', '小燕子 & 小鸭']);
      expect(request.queryParameters, isEmpty);
      return '''
<div class="list-con"><div class="items">
 <div class="pic"><a href="/play/1032"><mip-img src="https://cdn.test/cover.png"></a></div>
 <div class="text"><a href="/play/1032"><p class="title">小燕子 &amp; 小鸭</p>
 <p class="data"><span class="time">02:08</span></p></a></div>
</div><!--items end--></div>
''';
    });
    final items = await engine.searchSite(_site, '小燕子 & 小鸭');
    expect(items.single.id, 'https://www.tuxiaobei.com/play/1032');
    expect(items.single.title, '小燕子 & 小鸭');
    expect(items.single.posterUrl, 'https://cdn.test/cover.png');
    expect(items.single.overview, '02:08');
  });

  test(
      'detail defers media lookup until selection and preserves playback headers',
      () async {
    final requests = <RequestOptions>[];
    final engine = _engine(requests, (request) {
      expect(request.uri.toString(), 'https://www.tuxiaobei.com/play/1037');
      expect(request.headers['User-Agent'], contains('iPhone'));
      return '<mip-search-video video-src="https://cdn.test/video.mp4?x=1&amp;y=2" id="videoWrap">';
    });
    final candidates = await engine.fetchMediaCandidates(
      _site,
      const MediaItem(id: 'https://www.tuxiaobei.com/play/1037', title: '数鸭子'),
    );
    expect(requests, isEmpty);
    final episode = candidates.single.episodes.single;
    expect(episode.resolvePlayback, isNotNull);
    final playback = await episode.resolvePlayback!();
    expect(playback.url, 'https://cdn.test/video.mp4?x=1&y=2');
    expect(playback.requiresWebView, isFalse);
    expect(playback.headers?['Referer'], 'https://www.tuxiaobei.com/play/1037');
    expect(playback.headers?['User-Agent'], contains('iPhone'));
    expect(requests, hasLength(1));
    await episode.resolvePlayback!();
    expect(requests, hasLength(2),
        reason: 'Expired URLs must be fetched again on retry');
  });

  test('missing or non-media video attributes fail instead of opening HTML',
      () async {
    for (final html in <String>[
      '<html><a href="https://cdn.test/ad.mp4">advertisement</a></html>',
      '<mip-search-video id="videoWrap" video-src="https://video.test/watch.html">',
    ]) {
      final engine = _engine(<RequestOptions>[], (_) => html);
      final candidates = await engine.fetchMediaCandidates(
        _site,
        const MediaItem(id: '1037', title: '数鸭子'),
      );
      expect(candidates.single.episodes.single.resolvePlayback!(),
          throwsA(isA<FormatException>()));
    }
  });

  test('foreign detail links never become arbitrary page requests', () async {
    final requests = <RequestOptions>[];
    final engine = _engine(requests, (_) => '');
    expect(
      await engine.fetchMediaCandidates(
        _site,
        const MediaItem(id: 'https://other.test/play/1037', title: 'Foreign'),
      ),
      isEmpty,
    );
    expect(requests, isEmpty);
  });

  test('live official catalog search detail and native media probe', () async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ));
    addTearDown(() => dio.close(force: true));
    final engine = TvBoxSpiderEngine(dio: dio);
    final site = TvBoxSpiderEngine.defaultPresetSites
        .singleWhere((site) => site.key == 'tuxiaobei_dart');
    final categories = await engine.fetchSiteCategories(site);
    expect(categories, hasLength(4));
    final firstPage = await engine.fetchCategoryMedia(site, '2');
    final secondPage = await engine.fetchCategoryMedia(site, '2', page: 2);
    expect(firstPage, isNotEmpty);
    expect(secondPage, isNotEmpty);
    expect(secondPage.first.id, isNot(firstPage.first.id));
    for (final category in categories.where((category) => category.id != '2')) {
      final items = await engine.fetchCategoryMedia(site, category.id);
      expect(items, isNotEmpty, reason: category.name);
    }
    final matches = await engine.searchSite(site, '小燕子');
    expect(matches.any((item) => item.title.contains('小燕子')), isTrue);
    for (final item in <MediaItem>[firstPage.first, matches.first]) {
      final candidates = await engine.fetchMediaCandidates(site, item);
      final playback =
          await candidates.single.episodes.single.resolvePlayback!();
      expect(playback.requiresWebView, isFalse);
      final response = await dio.get<ResponseBody>(playback.url,
          options: Options(
            responseType: ResponseType.stream,
            headers: <String, String>{
              ...?playback.headers,
              'Range': 'bytes=0-1023',
            },
          ));
      expect(response.statusCode, 206);
      final chunk = await response.data!.stream.first;
      expect(ascii.decode(chunk.sublist(4, 8)), 'ftyp');
      // ignore: avoid_print
      print('TUXIAOBEI_NATIVE ${json.encode(<String, Object>{
            'title': item.title,
            'url': playback.url,
            'status': response.statusCode!,
            'firstChunkBytes': chunk.length,
          })}');
    }
    // ignore: avoid_print
    print('TUXIAOBEI_CATALOG categories=${categories.length} '
        'page1=${firstPage.length} page2=${secondPage.length} search=${matches.length}');
  }, skip: !const bool.fromEnvironment('JUYING_LIVE_TUXIAOBEI'));
}

TvBoxSpiderEngine _engine(
  List<RequestOptions> requests,
  String Function(RequestOptions) response,
) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    requests.add(options);
    handler.resolve(Response<String>(
      requestOptions: options,
      statusCode: 200,
      data: response(options),
    ));
  }));
  return TvBoxSpiderEngine(dio: dio);
}
