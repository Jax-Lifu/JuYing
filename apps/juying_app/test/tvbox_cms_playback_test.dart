import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

void main() {
  const site = TvBoxSite(
    key: 'cms',
    name: 'CMS',
    type: 1,
    api: 'https://cms.example/api',
  );

  test('HTML at a CMS API cannot fabricate categories or reset its cooldown',
      () async {
    var requests = 0;
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      handler.resolve(Response<String>(
        requestOptions: options,
        statusCode: 200,
        data: '<html><body>Site unavailable</body></html>',
      ));
    }));
    final engine = TvBoxSpiderEngine(dio: dio);
    expect(await engine.fetchSiteCategories(site), isEmpty);
    expect(await engine.fetchSiteCategories(site), isEmpty);
    expect(requests, 1);
  });

  test('CMS pages resolve through WebView while direct streams stay native',
      () async {
    final engine = TvBoxSpiderEngine(dio: Dio());
    final candidates = engine.parseMacCmsCandidates(site, {
      'list': [
        {
          'vod_play_from': 'line',
          'vod_play_url':
              r'页面$https://cms.example/watch/1#直连$https://media.example/2.m3u8',
        },
      ],
    });
    final episodes = candidates.single.episodes;
    expect(episodes[0].resolvePlayback, isNotNull);
    expect((await episodes[0].resolvePlayback!()).requiresWebView, isTrue);
    expect((await episodes[1].resolvePlayback!()).requiresWebView, isFalse);
  });

  test('CMS preserves relative episodes and standard pipe request headers',
      () async {
    final engine = TvBoxSpiderEngine(dio: Dio());
    final candidates = engine.parseMacCmsCandidates(
        site,
        {
          'list': [
            {
              'vod_play_from': 'line',
              'vod_play_url':
                  r'第1集$/media/1.mp4|User-Agent=Test%20Player&Referer=https%3A%2F%2Fcms.example%2F',
            },
          ],
        },
        currentUrl: site.api);
    expect(candidates, hasLength(1));
    final episode = await candidates.single.episodes.single.resolvePlayback!();
    expect(episode.url, 'https://cms.example/media/1.mp4');
    expect(episode.headers, {
      'User-Agent': 'Test Player',
      'Referer': 'https://cms.example/',
    });
    expect(episode.requiresWebView, isFalse);
  });

  test('CMS only calls the warehouse parser for the selected VIP episode',
      () async {
    final requests = <String>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.uri.toString());
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: {'url': 'https://media.example/selected.m3u8'},
      ));
    }));
    final engine = TvBoxSpiderEngine(dio: dio);
    final candidates = engine.parseMacCmsCandidates(
      site.copyWith(flags: [
        'vip'
      ], parses: [
        {'name': 'json', 'type': 1, 'url': 'https://parser.example/?url='},
      ]),
      {
        'list': [
          {
            'vod_play_from': 'vip',
            'vod_play_url':
                r'第1集$https://cms.example/watch/1#第2集$https://cms.example/watch/2',
          },
        ],
      },
    );
    expect(requests, isEmpty);
    final selected = await candidates.single.episodes[1].resolvePlayback!();
    expect(requests, hasLength(1));
    expect(Uri.parse(requests.single).queryParameters['url'],
        'https://cms.example/watch/2');
    expect(selected.url, 'https://media.example/selected.m3u8');
    expect(selected.sortIndex, 2);
  });
}
