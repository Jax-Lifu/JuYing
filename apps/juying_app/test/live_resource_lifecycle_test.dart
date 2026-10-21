import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/models/live_channel.dart';
import 'package:juying/features/live/presentation/live_page.dart';
import 'package:juying/features/live/services/iptv_service.dart';
import 'package:juying/features/player/presentation/cctv_official_web_player_page.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';

class _LiveRouteObserver extends NavigatorObserver {
  Widget? destination;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null && route is MaterialPageRoute) {
      // Inspect navigation without mounting a platform player or decoder.
      destination = route.builder(navigator!.context);
    }
  }
}

void main() {
  test('invalid playlist text does not suppress the backup catalog', () async {
    final requested = <String>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requested.add(options.uri.toString());
      handler.resolve(Response<String>(
        requestOptions: options,
        statusCode: 200,
        data: requested.length == 1
            ? '<html>Service unavailable, please retry later</html>'
            : 'CCTV-1,http://media.example/live.m3u8',
      ));
    }));

    final catalog = await IptvService(dio: dio).fetchFirstAvailableCatalog([
      'https://playlist.example/broken.txt',
      'https://playlist.example/backup.txt',
    ]);

    expect(requested, hasLength(2));
    expect(catalog.channels.single.name, 'CCTV-1');
  });

  test('invalid M3U stream text is discarded without leaking metadata', () {
    final channels = IptvService().parseM3u('''
#EXTM3U
#EXTINF:-1 tvg-id="invalid",Unavailable
#EXTVLCOPT:http-user-agent=Discarded
Service unavailable
#EXTINF:-1,Working channel
https://media.example/live.m3u8
''');

    expect(channels, hasLength(1));
    expect(channels.single.name, 'Working channel');
    expect(channels.single.routes.single.headers, isNull);
  });

  test('playlist validation preserves standard IPTV transports', () {
    final service = IptvService();
    for (final url in <String>[
      'http://media.example/live.m3u8?parts=1,2',
      'https://[2409:8087::1]/live.m3u8',
      'rtsp://media.example/live',
      'rtmp://media.example/live',
      'udp://@239.0.0.1:1234',
      'rtp://239.0.0.1:1234',
    ]) {
      expect(service.parseTxt('Channel,$url').single.routes.single.url, url);
      expect(
        service
            .parseM3u('#EXTM3U\n#EXTINF:-1,Channel\n$url')
            .single
            .routes
            .single
            .url,
        url,
      );
    }
  });

  for (final routeCount in <int>[2, 7]) {
    test('probe failure requires all $routeCount HLS candidates to be checked',
        () async {
      var requests = 0;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests++;
        handler.resolve(Response<String>(
          requestOptions: options,
          statusCode: 503,
          data: 'Unavailable',
        ));
      }));
      final result = await IptvService(dio: dio).probeRoutes(<LiveStreamRoute>[
        for (var index = 0; index < routeCount; index++)
          LiveStreamRoute(
            name: '$index',
            url: 'https://media.example/$index.m3u8',
          ),
      ]);

      expect(requests, routeCount == 2 ? 2 : 6);
      expect(result.healthyRoute, isNull);
      expect(result.allRoutesFailed, routeCount == 2);
    });
  }

  test('an expired probe budget leaves pending HLS routes unknown', () async {
    final requests = <(RequestOptions, RequestInterceptorHandler)>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add((options, handler));
    }));
    final result = await IptvService(dio: dio).probeRoutes(
      const <LiveStreamRoute>[
        LiveStreamRoute(
            name: 'Pending', url: 'https://media.example/live.m3u8'),
      ],
      maxWait: const Duration(milliseconds: 20),
    );
    for (final (options, handler) in requests) {
      handler.resolve(Response<String>(
        requestOptions: options,
        statusCode: 503,
        data: 'Late failure',
      ));
    }
    await Future<void>.delayed(Duration.zero);

    expect(requests, hasLength(1));
    expect(result.healthyRoute, isNull);
    expect(result.allRoutesFailed, isFalse);
  });

  for (final failure in <DioExceptionType>[
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.cancel,
  ]) {
    test('a $failure does not conclusively fail an HLS route', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.reject(DioException(requestOptions: options, type: failure));
      }));
      final result = await IptvService(dio: dio).probeRoutes(
        const <LiveStreamRoute>[
          LiveStreamRoute(name: 'Slow', url: 'https://media.example/live.m3u8'),
        ],
      );

      expect(result.healthyRoute, isNull);
      expect(result.allRoutesFailed, isFalse);
    });
  }

  test('HLS probes resolve relative media against the redirected manifest',
      () async {
    final requested = <String>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requested.add(options.uri.toString());
      if (requested.length == 1) {
        handler.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          redirects: <RedirectRecord>[
            RedirectRecord(
              302,
              'GET',
              Uri.parse('https://cdn.example/actual/live.m3u8'),
            ),
          ],
          data: '#EXTM3U\n#EXTINF:4,\nsegment.ts\n',
        ));
      } else {
        final status =
            options.uri.toString() == 'https://cdn.example/actual/segment.ts'
                ? 206
                : 404;
        handler.resolve(Response<ResponseBody>(
          requestOptions: options,
          statusCode: status,
          data: ResponseBody.fromBytes(<int>[0x47, 0, 0], status),
        ));
      }
    }));
    final result = await IptvService(dio: dio).probeRoutes(
      const <LiveStreamRoute>[
        LiveStreamRoute(
            name: 'Redirect', url: 'https://media.example/live.m3u8'),
      ],
    );

    expect(requested.last, 'https://cdn.example/actual/segment.ts');
    expect(result.healthyRoute, isNotNull);
    expect(result.allRoutesFailed, isFalse);
  });

  for (final url in <String>[
    'https://media.example/live.m3u8',
    'rtsp://media.example/live',
    'rtmp://media.example/live',
    'udp://@239.0.0.1:1234',
    'rtp://239.0.0.1:1234',
    'https://media.example/live.ts',
    'https://media.example/live.flv',
    'https://media.example/stream?id=1',
  ]) {
    testWidgets('official live fallback respects the probe support for $url',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await IptvService().cacheCatalog(<LiveChannel>[
        LiveChannel(
          id: 'cctv1',
          name: 'CCTV-1 综合',
          category: '央视频道',
          routes: <LiveStreamRoute>[LiveStreamRoute(name: '测试线路', url: url)],
        ),
      ]);
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final observer = _LiveRouteObserver();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: const LivePage(),
      ));
      // Flutter's test HttpClient returns 400 for every request. No external
      // playlist, image, manifest, or media request reaches the network.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('全屏播放'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      final destination = observer.destination;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      if (url.endsWith('.m3u8')) {
        expect(destination, isA<CctvOfficialWebPlayerPage>());
        expect((destination as CctvOfficialWebPlayerPage).isLive, isTrue);
      } else {
        expect(destination, isA<VideoPlayerPage>());
        expect((destination as VideoPlayerPage).currentEpisode.url, url);
      }
    }, skip: !Platform.isWindows);
  }
}
