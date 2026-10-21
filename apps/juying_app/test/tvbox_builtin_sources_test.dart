import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

void main() {
  test('built-in Bilibili categories send usable search keywords', () async {
    final site = TvBoxSpiderEngine.defaultPresetSites
        .singleWhere((site) => site.key == 'bilibili_dart');
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.uri.path, '/x/web-interface/search/type');
      expect(request.queryParameters['keyword'],
          isIn(site.categories.map((category) => category.name)));
      expect(request.queryParameters['page'], 2);
      handler.resolve(Response<dynamic>(
        requestOptions: request,
        data: <String, dynamic>{
          'code': 0,
          'data': <String, dynamic>{
            'result': <Map<String, dynamic>>[
              <String, dynamic>{'bvid': 'BV123', 'title': '分类视频'},
            ],
          },
        },
      ));
    }));
    final engine = TvBoxSpiderEngine(dio: dio);
    for (final category in await engine.fetchSiteCategories(site)) {
      final media = await engine.fetchCategoryMedia(site, category.id, page: 2);
      expect(media.single.title, '分类视频');
    }
  });

  test('built-in Tuxiaobei uses the native adapter without rule downloads',
      () async {
    final site = TvBoxSpiderEngine.defaultPresetSites
        .singleWhere((site) => site.key == 'tuxiaobei_dart');
    expect(site.isRuntimeSupported, isTrue);
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    var requests = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests++;
      expect(request.uri.toString(), 'https://www.tuxiaobei.com/play/1037');
      handler.resolve(Response<String>(
        requestOptions: request,
        data: '<mip-search-video id="videoWrap" '
            'video-src="https://resource-cdn.tuxiaobei.com/video/test.mp4">',
      ));
    }));
    final engine = TvBoxSpiderEngine(dio: dio);
    expect(await engine.fetchSiteCategories(site), hasLength(4));
    final candidates = await engine.fetchMediaCandidates(
        site, const MediaItem(id: '1037', title: '数鸭子'));
    expect(requests, 0);
    final playback = await candidates.single.episodes.single.resolvePlayback!();
    expect(playback.url, endsWith('/video/test.mp4'));
    expect(playback.requiresWebView, isFalse);
    expect(requests, 1);
  });
}
