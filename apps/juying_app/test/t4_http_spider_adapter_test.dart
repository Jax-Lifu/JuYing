import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/t4_http_spider_adapter.dart';

void main() {
  test('HTTP episode pages still call player with flag and extend', () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        handler.resolve(
          Response<dynamic>(
            requestOptions: request,
            statusCode: 200,
            data: request.queryParameters.containsKey('play')
                ? <String, dynamic>{
                    'parse': 0,
                    'url': 'https://cdn.test/media.m3u8',
                    'header': <String, String>{
                      'Referer': 'https://site.test/',
                    },
                  }
                : <String, dynamic>{
                    'list': <Map<String, String>>[
                      <String, String>{
                        'vod_play_from': 'main',
                        'vod_play_url':
                            r'Episode$https://site.test/watch/1.html',
                      },
                    ],
                  },
          ),
        );
      }),
    );
    final adapter = T4HttpSpiderAdapter(dio);
    const site = TvBoxSite(
      key: 'remote',
      name: 'Remote Spider',
      type: 4,
      api: 'https://spider.test/api',
      ext: <String, String>{'route': 'main'},
    );

    final candidates = await adapter.fetchCandidates(
      site,
      const MediaItem(id: '1', title: 'Example'),
    );

    expect(requests, hasLength(1));
    final playback = await candidates.single.episodes.single.resolvePlayback!();
    expect(requests, hasLength(2));
    expect(requests.last.queryParameters['play'],
        'https://site.test/watch/1.html');
    expect(requests.last.queryParameters['flag'], 'main');
    expect(requests.last.queryParameters['extend'], '{"route":"main"}');
    expect(playback.url, 'https://cdn.test/media.m3u8');
    expect(playback.headers?['Referer'], 'https://site.test/');
    expect(playback.resolvePlayback, isNull);
    expect(playback.requiresWebView, isFalse);
  });

  test(
      'selected T4 flag reaches the configured JSON parser without eager calls',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: request.uri.host == 'parser.test'
              ? {'url': 'https://cdn.test/final.m3u8'}
              : request.queryParameters.containsKey('play')
                  ? {'parse': 0, 'url': 'https://video.test/watch.html'}
                  : {
                      'list': [
                        {
                          'vod_play_from': 'qq',
                          'vod_play_url': r'Episode$opaque-id',
                        },
                      ],
                    },
        ));
      }));
    final adapter = T4HttpSpiderAdapter(dio);
    const site = TvBoxSite(
      key: 'remote',
      name: 'Remote',
      type: 4,
      api: 'https://spider.test/api',
      flags: ['qq'],
      parses: [
        {
          'name': 'Configured JSON',
          'type': 1,
          'url': 'https://parser.test/?url='
        },
      ],
    );
    final candidates = await adapter.fetchCandidates(
      site,
      const MediaItem(id: '1', title: 'Example'),
    );
    expect(requests, hasLength(1));
    final resolved = await candidates.single.episodes.single.resolvePlayback!();
    expect(requests, hasLength(3));
    expect(requests.last.uri.toString(),
        'https://parser.test/?url=https://video.test/watch.html');
    expect(resolved.url, 'https://cdn.test/final.m3u8');
    expect(resolved.requiresWebView, isFalse);
  });

  test('a non-object HTTP response is a protocol error, not an empty catalog',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: '[]',
        ));
      }));
    await expectLater(
        T4HttpSpiderAdapter(dio).fetchCategories(const TvBoxSite(
          key: 'remote',
          name: 'Remote',
          type: 4,
          api: 'https://spider.test/api',
        )),
        throwsFormatException);
  });

  test('invalid JSON MIME responses report a protocol error after HTTP success',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType =
          ContentType('text', 'json', charset: 'utf-8');
      request.response.write('service unavailable');
      await request.response.close();
    });
    final statuses = <int?>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onResponse: (response, handler) {
        statuses.add(response.statusCode);
        handler.next(response);
      }));
    addTearDown(() => dio.close(force: true));
    await expectLater(
      T4HttpSpiderAdapter(dio).fetchCategories(TvBoxSite(
        key: 'remote',
        name: 'Remote',
        type: 4,
        api: 'http://127.0.0.1:${server.port}/api',
      )),
      throwsFormatException,
    );
    expect(statuses, [200]);
  });
}
