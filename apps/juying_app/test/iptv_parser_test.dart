import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/models/live_channel.dart';
import 'package:juying/features/live/services/iptv_service.dart';

void main() {
  group('IptvService Playlist Parser Tests', () {
    late IptvService service;

    setUp(() {
      service = IptvService();
    });

    test('parses standard M3U playlist with headers and attributes', () {
      const m3u = '''
#EXTM3U x-tvg-url="https://epg.example/guide.xml.gz,https://backup.example/guide.xml"
#EXTINF:-1 tvg-id="cctv1" tvg-name="CCTV-1" tvg-logo="http://logo.png" group-title="央视频道", CCTV-1 综合
#EXTVLCOPT:http-user-agent=JuYing/1.0
http://127.0.0.1/cctv1.m3u8
#EXTINF:-1 tvg-id="cctv2" group-title="央视频道", CCTV-2 财经
http://[2409:8087::1]/cctv2.m3u8
''';

      final channels = service.parseM3u(m3u);
      expect(channels.length, 2);

      expect(channels[0].name, 'CCTV-1 综合');
      expect(channels[0].category, '央视频道');
      expect(channels[0].logoUrl, 'http://logo.png');
      expect(channels[0].routes.length, 1);
      expect(channels[0].routes.first.headers?['User-Agent'], 'JuYing/1.0');
      expect(channels[0].routes.first.isIpv6, false);

      expect(channels[1].name, 'CCTV-2 财经');
      expect(channels[1].routes.first.isIpv6, true);
      expect(service.extractXmlTvUrls(m3u), <String>[
        'https://epg.example/guide.xml.gz',
        'https://backup.example/guide.xml',
      ]);
    });

    test('parses grouped TXT playlist correctly', () {
      const txt = '''
央视频道,#genre#
CCTV-1 综合,http://127.0.0.1/cctv1.m3u8\$线路1
地方卫视,#genre#
浙江卫视 HD,http://127.0.0.1/zjtv.m3u8
''';

      final channels = service.parseTxt(txt);
      expect(channels.length, 2);

      expect(channels[0].name, 'CCTV-1 综合');
      expect(channels[0].category, '央视频道');
      expect(channels[0].routes.first.name, '线路1');

      expect(channels[1].name, '浙江卫视 HD');
      expect(channels[1].category, '地方卫视');
    });

    test('filters satellite channels without falling back to CCTV', () {
      const m3u = '''
#EXTM3U
#EXTINF:-1 group-title="央视频道",CCTV-1综合
http://127.0.0.1/cctv1.m3u8
#EXTINF:-1 group-title="卫视频道",北京卫视
http://127.0.0.1/btv.m3u8
#EXTINF:-1 group-title="地方频道",上海新闻综合
http://127.0.0.1/shanghai.m3u8
''';

      final channels = service.parseM3u(m3u);
      final satellite = service.filterChannelsByCategory(channels, '卫视');

      expect(satellite.map((channel) => channel.name), <String>['北京卫视']);
      expect(
        service.filterChannelsByCategory(
          channels.where((channel) => channel.name != '北京卫视').toList(),
          '卫视',
        ),
        isEmpty,
      );
    });

    test('merges independent playlist routes by canonical channel name',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final route = options.path.endsWith('/primary')
                ? 'http://primary.example/btv.m3u8'
                : 'http://backup.example/btv.m3u8';
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: '#EXTM3U\n'
                    '#EXTINF:-1 group-title="卫视频道",北京卫视 高清\n'
                    '$route\n',
              ),
            );
          },
        ),
      );

      final merged = await IptvService(dio: dio).fetchAndMergePlaylists(
        <String>[
          'https://catalog.example/primary',
          'https://catalog.example/backup'
        ],
      );

      expect(merged, hasLength(1));
      expect(merged.single.routes, hasLength(2));
    });

    test('probes a real HLS segment instead of trusting manifest status',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('.m3u8')) {
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: '#EXTM3U\n#EXTINF:4,\nsegment.ts\n',
                ),
              );
              return;
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 206,
                data: ResponseBody.fromBytes(<int>[0x47, 0, 0], 206),
              ),
            );
          },
        ),
      );

      final route = await IptvService(dio: dio).probeRoute(
        const LiveStreamRoute(
          name: '测试线路',
          url: 'https://stream.example/live/index.m3u8',
        ),
      );

      expect(route.latencyMs, greaterThanOrEqualTo(0));
      expect(route.speedMib, 0,
          reason: 'A first-byte probe is not a speed test.');
    });

    test('rejects an empty HLS segment even when HTTP status is successful',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: options.path.endsWith('.m3u8')
                  ? '#EXTM3U\n#EXTINF:4,\nsegment.ts\n'
                  : ResponseBody.fromBytes(<int>[], 200),
            ),
          ),
        ),
      );

      final route = await IptvService(dio: dio).probeRoute(
        const LiveStreamRoute(
          name: '空分片',
          url: 'https://stream.example/live.m3u8',
        ),
      );

      expect(route.latencyMs, -1);
    });

    test('cancels the segment stream after verifying its first bytes',
        () async {
      var cancelled = false;
      late StreamController<Uint8List> body;
      body = StreamController<Uint8List>(
        onListen: () => body.add(Uint8List.fromList(<int>[0x47, 0, 0])),
        onCancel: () => cancelled = true,
      );
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: options.path.endsWith('.m3u8')
                  ? '#EXTM3U\n#EXTINF:4,\nsegment.ts\n'
                  : ResponseBody(body.stream, 200),
            ),
          ),
        ),
      );

      final route = await IptvService(dio: dio).probeRoute(
        const LiveStreamRoute(
          name: '持续传输分片',
          url: 'https://stream.example/live.m3u8',
        ),
      );

      expect(route.latencyMs, greaterThanOrEqualTo(0));
      expect(cancelled, isTrue);
      await body.close();
    });

    test('times out and cancels a segment that never sends bytes', () async {
      var cancelled = false;
      final body = StreamController<Uint8List>(
        onCancel: () => cancelled = true,
      );
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: options.path.endsWith('.m3u8')
                  ? '#EXTM3U\n#EXTINF:4,\nsegment.ts\n'
                  : ResponseBody(body.stream, 200),
            ),
          ),
        ),
      );

      final route = await IptvService(dio: dio).probeRoute(
        const LiveStreamRoute(
          name: '无数据分片',
          url: 'https://stream.example/live.m3u8',
        ),
        requestTimeout: const Duration(milliseconds: 10),
      );

      expect(route.latencyMs, -1);
      expect(cancelled, isTrue);
      await body.close();
    });

    test('returns the first healthy route without waiting for slow failures',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            if (options.path.contains('slow.example')) {
              await Future<void>.delayed(const Duration(milliseconds: 700));
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                ),
              );
              return;
            }
            if (options.path.endsWith('.m3u8')) {
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: '#EXTM3U\n#EXTINF:4,\nsegment.ts\n',
                ),
              );
              return;
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 206,
                data: ResponseBody.fromBytes(<int>[0x47, 0, 0], 206),
              ),
            );
          },
        ),
      );

      final stopwatch = Stopwatch()..start();
      final route = await IptvService(dio: dio).probeFirstHealthyRoute(
        const <LiveStreamRoute>[
          LiveStreamRoute(
            name: '慢速失效线路',
            url: 'https://slow.example/live/index.m3u8',
          ),
          LiveStreamRoute(
            name: '快速可播线路',
            url: 'https://fast.example/live/index.m3u8',
          ),
        ],
        maxWait: const Duration(seconds: 1),
      );
      stopwatch.stop();

      expect(route?.name, '快速可播线路');
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
    });

    test('reuses a recently verified healthy route', () async {
      var requestCount = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCount++;
            if (options.path.endsWith('.m3u8')) {
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: '#EXTM3U\n#EXTINF:4,\nsegment.ts\n',
                ),
              );
              return;
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 206,
                data: ResponseBody.fromBytes(<int>[0x47, 0, 0], 206),
              ),
            );
          },
        ),
      );
      final service = IptvService(dio: dio);
      const routes = <LiveStreamRoute>[
        LiveStreamRoute(
          name: '缓存线路',
          url: 'https://cache.example/live/index.m3u8',
        ),
      ];

      expect(await service.probeFirstHealthyRoute(routes), isNotNull);
      expect(await service.probeFirstHealthyRoute(routes), isNotNull);
      expect(requestCount, 2);
    });

    test('persists the last successful channel catalog', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = IptvService(dio: Dio());
      await service.cacheCatalog(
        const <LiveChannel>[
          LiveChannel(
            id: 'cctv1',
            name: 'CCTV-1 综合',
            category: '央视频道',
            routes: <LiveStreamRoute>[
              LiveStreamRoute(
                name: '缓存线路',
                url: 'https://cache.example/cctv1/index.m3u8',
                headers: <String, String>{'Referer': 'https://example.com/'},
              ),
            ],
          ),
        ],
      );

      final cached = await service.readCachedCatalog();

      expect(cached, hasLength(1));
      expect(cached.single.name, 'CCTV-1 综合');
      expect(cached.single.routes.single.headers?['Referer'],
          'https://example.com/');
    });

    test('parses XMLTV timezone and applies schedules by id or alias', () {
      const xml = '''
<tv>
  <channel id="cctv1"><display-name>CCTV-1 综合 HD</display-name></channel>
  <channel id="zhejiang"><display-name>浙江卫视</display-name></channel>
  <programme channel="cctv1" start="20260824080000 +0800" stop="20260824090000 +0800">
    <title>朝闻天下</title><desc>早间新闻</desc>
  </programme>
  <programme channel="cctv1" start="20260824090000 +0800" stop="20260824100000 +0800">
    <title>新闻直播间</title>
  </programme>
  <programme channel="zhejiang" start="20260824080000 +0800" stop="20260824090000 +0800">
    <title>浙江新闻</title>
  </programme>
</tv>
''';

      final schedules = service.parseXmlTv(xml);
      final channels = service.applyEpgSchedules(
        const <LiveChannel>[
          LiveChannel(id: 'cctv1', name: '任意名称', category: '央视'),
          LiveChannel(id: 'local-zj', name: '浙江卫视 高清', category: '卫视'),
        ],
        schedules,
        now: DateTime.utc(2026, 8, 24, 0, 30),
      );

      expect(schedules, hasLength(2));
      expect(channels[0].currentProgram?.title, '朝闻天下');
      expect(channels[0].currentProgram?.overview, '早间新闻');
      expect(channels[0].nextProgram?.title, '新闻直播间');
      expect(channels[1].currentProgram?.title, '浙江新闻');
    });

    test('downloads and decodes gzip XMLTV payloads', () async {
      const xml = '''
<tv>
  <channel id="cctv1"><display-name>CCTV-1</display-name></channel>
  <programme channel="cctv1" start="20260824080000 +0800" stop="20260824090000 +0800">
    <title>朝闻天下</title>
  </programme>
</tv>
''';
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              statusCode: 200,
              data: gzip.encode(utf8.encode(xml)),
            ),
          ),
        ),
      );

      final schedules = await IptvService(dio: dio).fetchXmlTv(
        'https://epg.example/guide.xml.gz',
      );

      expect(schedules.single.channelId, 'cctv1');
      expect(schedules.single.programs.single.title, '朝闻天下');
    });

    test('tries the fanmingming com XMLTV mirror before the stale cn host',
        () async {
      const xml = '''
<tv>
  <channel id="cctv1"><display-name>CCTV-1</display-name></channel>
  <programme channel="cctv1" start="20260824080000 +0800" stop="20260824090000 +0800">
    <title>朝闻天下</title>
  </programme>
</tv>
''';
      final requestedUrls = <String>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestedUrls.add(options.uri.toString());
            handler.resolve(
              Response<List<int>>(
                requestOptions: options,
                statusCode: 200,
                data: utf8.encode(xml),
              ),
            );
          },
        ),
      );

      final schedules = await IptvService(dio: dio).fetchFirstAvailableXmlTv(
        const <String>['https://live.fanmingming.cn/e.xml'],
      );

      expect(requestedUrls, <String>['https://live.fanmingming.com/e.xml']);
      expect(schedules.single.channelId, 'cctv1');
    });

    test('interpolates formatted and timestamp catchup templates', () {
      final formatted = service.buildCatchupUri(
        const LiveChannel(
          id: 'cctv1',
          name: 'CCTV-1',
          category: '央视',
          routes: <LiveStreamRoute>[
            LiveStreamRoute(
              name: '直播',
              url: 'https://live.example/cctv1/index.m3u8?token=old',
            ),
          ],
          catchupTemplate:
              r'?playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}',
        ),
        EpgProgram(
          title: '节目',
          startTime: DateTime(2026, 8, 24, 8),
          endTime: DateTime(2026, 8, 24, 9),
        ),
      );
      final timestamp = service.buildCatchupUri(
        const LiveChannel(
          id: 'cctv1',
          name: 'CCTV-1',
          category: '央视',
          routes: <LiveStreamRoute>[
            LiveStreamRoute(
              name: '直播',
              url: 'https://live.example/cctv1/index.m3u8',
            ),
          ],
          catchupTemplate:
              r'/catchup?start=${(b)timestamp}&end=${(e)timestamp}',
        ),
        EpgProgram(
          title: '节目',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000000),
          endTime: DateTime.fromMillisecondsSinceEpoch(2000000),
        ),
      );

      expect(
        formatted.toString(),
        'https://live.example/cctv1/index.m3u8?playseek='
        '20260824080000-20260824090000',
      );
      expect(
        timestamp.toString(),
        'https://live.example/catchup?start=1000&end=2000',
      );
    });

    test(
        'fetchXmlTv handles both raw GZIP bytes and uncompressed XML text bytes gracefully',
        () async {
      const sampleXml = '''<?xml version="1.0" encoding="utf-8" ?>
<tv>
  <channel id="CCTV1"><display-name>CCTV-1</display-name></channel>
  <programme start="20260824080000 +0800" stop="20260824090000 +0800" channel="CCTV1">
    <title>早间新闻</title>
  </programme>
</tv>''';

      // 1. Raw GZIP bytes
      final gzipBytes = gzip.encode(utf8.encode(sampleXml));
      final dioGzip = Dio();
      dioGzip.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<List<int>>(
                requestOptions: options,
                statusCode: 200,
                data: gzipBytes,
              ),
            );
          },
        ),
      );

      final schedulesFromGzip = await IptvService(dio: dioGzip)
          .fetchXmlTv('https://example.com/e.xml.gz');
      expect(schedulesFromGzip.length, 1);
      expect(schedulesFromGzip.first.channelId, 'CCTV1');
      expect(schedulesFromGzip.first.programs.first.title, '早间新闻');

      // 2. Uncompressed bytes with Content-Encoding: gzip header (HttpClient already unzipped)
      final plainBytes = utf8.encode(sampleXml);
      final dioPlainWithGzipHeader = Dio();
      dioPlainWithGzipHeader.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<List<int>>(
                requestOptions: options,
                statusCode: 200,
                headers: Headers.fromMap(<String, List<String>>{
                  'content-encoding': <String>['gzip'],
                }),
                data: plainBytes,
              ),
            );
          },
        ),
      );

      final schedulesFromPlain = await IptvService(dio: dioPlainWithGzipHeader)
          .fetchXmlTv('https://example.com/e.xml');
      expect(schedulesFromPlain.length, 1);
      expect(schedulesFromPlain.first.channelId, 'CCTV1');
      expect(schedulesFromPlain.first.programs.first.title, '早间新闻');
    });

    test(
        'fetchFirstAvailableXmlTv rewrites .cn to .com and skips unreachable mirrors',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('live.fanmingming.com')) {
              handler.resolve(
                Response<List<int>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: utf8.encode('''<?xml version="1.0" encoding="utf-8" ?>
<tv>
  <channel id="CCTV1"><display-name>CCTV-1 综合</display-name></channel>
</tv>'''),
                ),
              );
              return;
            }
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );

      final schedules = await IptvService(dio: dio).fetchFirstAvailableXmlTv(
        <String>['https://live.fanmingming.cn/e.xml'],
      );
      expect(schedules.length, 1);
      expect(schedules.first.channelId, 'CCTV1');
    });
  });
}
