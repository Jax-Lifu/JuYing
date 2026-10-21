import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/live_to_vod_spider_adapter.dart';

const _site = TvBoxSite(
    key: 'live',
    name: '直播',
    type: 3,
    api: 'https://config.test/scripts/live2vod.js',
    ext: 'https://config.test/lists/index.json');

void main() {
  test('known live2vod identity does not enable other JavaScript', () {
    expect(LiveToVodSpiderAdapter.supports(_site), isTrue);
    expect(
        LiveToVodSpiderAdapter.supportsConfig(
            api: 'https://config.test/unknown.js', ext: _site.ext),
        isFalse);
  });

  test(
      'directory, grouped M3U and alternate routes reach playback with headers',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          handler.resolve(Response(
              requestOptions: request,
              statusCode: 200,
              data: request.uri.path.endsWith('index.json')
                  ? jsonEncode([
                      {
                        'name': '官方!!',
                        'url': 'live.m3u|Referer=https%3A%2F%2Fwatch.test%2F'
                      }
                    ])
                  : '#EXTM3U\n'
                      '#EXTINF:-1 group-title="新闻" tvg-logo="https://img.test/one.png",第一台\n'
                      'https://cdn.test/one.m3u8\n'
                      '#EXTINF:-1 group-title="新闻",第一台\n'
                      'https://backup.test/one.m3u8\n'
                      '#EXTINF:-1 group-title="新闻",第二台\n'
                      'https://cdn.test/two.m3u8\n'));
        },
      ));
    final adapter = LiveToVodSpiderAdapter(dio);
    final categories = await adapter.fetchCategories(_site);
    expect(categories.single.name, '官方');
    final media = await adapter.fetchCategory(_site, categories.single.id);
    expect(media.single.title, '新闻');
    expect(media.single.totalEpisodes, 2);
    final candidates = await adapter.fetchCandidates(_site, media.single);
    expect(candidates, hasLength(2));
    expect(candidates.first.episodes.map((e) => e.name), ['第一台', '第二台']);
    expect(candidates.last.episodes.first.url, 'https://backup.test/one.m3u8');
    expect(candidates.last.episodes[1].name, '第二台');
    expect(candidates.last.episodes[1].url, 'https://cdn.test/two.m3u8');
    expect(candidates.first.episodes.first.headers!['Referer'],
        'https://watch.test/');
    expect(requests[1].uri.path, '/lists/live.m3u');
    expect(requests[1].headers['Referer'], 'https://watch.test/');
    final count = requests.length;
    expect(await adapter.fetchCategory(_site, categories.single.id, page: 2),
        isEmpty);
    expect(await adapter.search(_site, '新闻'), isEmpty);
    expect(requests.length, count);
  });

  for (final format in ['txt', 'fongmi', 'lu']) {
    test('inline list preserves $format groups and rejects non-media rows',
        () async {
      final content = switch (format) {
        'txt' => '少儿\n动画,http://cdn.test/cartoon.m3u8\n伪地址,not-a-url',
        'fongmi' => jsonEncode([
            {
              'name': '少儿',
              'channel': [
                {
                  'name': '动画',
                  'urls': ['http://cdn.test/cartoon.m3u8']
                },
              ]
            }
          ]),
        _ => jsonEncode({
            'data': {
              'datalist': [
                {
                  'prov': '少儿',
                  'list': [
                    {
                      'name': '动画',
                      'urls': [
                        {'line': '主线', 'url': 'http://cdn.test/cartoon.m3u8'},
                      ]
                    }
                  ]
                },
              ]
            }
          }),
      };
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (request, handler) => handler.resolve(Response(
              requestOptions: request, statusCode: 200, data: content)),
        ));
      final adapter = LiveToVodSpiderAdapter(dio);
      const site = TvBoxSite(
          key: 'live',
          name: '直播',
          type: 3,
          api: 'https://config.test/live2vod.js',
          ext: r'http://lists.test/$$$我的频道$children.txt');
      final category = (await adapter.fetchCategories(site)).single;
      expect(jsonDecode(category.id)['url'], 'http://lists.test/children.txt');
      final media = (await adapter.fetchCategory(site, category.id)).single;
      expect(media.title, '少儿');
      final candidates = await adapter.fetchCandidates(site, media);
      expect(candidates.single.episodes.single.url,
          'http://cdn.test/cartoon.m3u8');
    });
  }

  test(
      'HTML and failed remote requests are errors, never fake empty categories',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
        onRequest: (request, handler) => handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: '<html>service unavailable</html>')),
      ));
    final adapter = LiveToVodSpiderAdapter(dio);
    await expectLater(adapter.fetchCategories(_site), throwsFormatException);
    const inline = TvBoxSite(
        key: 'live',
        name: '直播',
        type: 3,
        api: 'https://config.test/live2vod.js',
        ext: r'列表$https://config.test/list');
    final category = (await adapter.fetchCategories(inline)).single;
    await expectLater(
        adapter.fetchCategory(inline, category.id), throwsFormatException);
  });
}
