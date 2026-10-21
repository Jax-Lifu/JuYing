import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/cctv/services/cctv_api_service.dart';

void main() {
  test('HD variants keep advertised resolution and sort by quality', () async {
    final fixture = _fixture('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=640x360
/sd.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720
/720-high.m3u8?token=child
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
../1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720
720-low.m3u8
''');

    final playback =
        await fixture.service.resolveCctvGuidHdPlayback(' cctv_guid://guid ');

    expect(playback, isNotNull);
    expect(playback!.duration, const Duration(milliseconds: 632280));
    expect(playback.variants.map((variant) => variant.resolution),
        <String>['1080p', '720p', '720p']);
    expect(playback.variants.map((variant) => variant.bitrateKbps),
        <int>[5000, 2000, 1200]);
    expect(playback.variants.every((variant) => variant.isH5e), isTrue);
    expect(playback.variants.map((variant) => variant.url), <String>[
      'https://cdn.example/h5e/1080.m3u8',
      'https://cdn.example/720-high.m3u8?token=child',
      'https://cdn.example/h5e/master/720-low.m3u8',
    ]);
    expect(fixture.requests, hasLength(2));
    expect(fixture.requests.first.queryParameters,
        <String, dynamic>{'pid': 'guid', 'tz': -8, 'from': '000news'});
    expect(fixture.requests.last.uri.queryParameters['token'], 'master');
    for (final request in fixture.requests) {
      expect(request.headers['User-Agent'], 'CCTV test agent');
      expect(request.headers['Referer'], 'https://tv.cctv.com/');
    }
  });

  test('relative HD URLs use the redirected master location', () async {
    final fixture = _fixture(
      '\uFEFF#EXTM3U\r\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\r\n'
      '# child playlist\r\n'
      'video/720.m3u8?token=variant&quality=hd\r\n',
      redirect: Uri.parse('https://edge.example/final/main.m3u8'),
    );

    final playback = await fixture.service.resolveCctvGuidHdPlayback('guid');

    expect(playback!.variants.single.url,
        'https://edge.example/final/video/720.m3u8?token=variant&quality=hd');
  });

  for (final codec in <String>[
    'hvc1.1.6.L153',
    'av01.0.08M.08',
    'vp09.00.40'
  ]) {
    test('highest $codec rendition returns fallback instead of lower HD',
        () async {
      final fixture = _fixture('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
/720.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="$codec,mp4a.40.2"
/1080.m3u8
''');

      expect(await fixture.service.resolveCctvGuidHdPlayback('guid'), isNull);
    });
  }

  test('unsupported higher bandwidth at the same resolution also falls back',
      () async {
    final fixture = _fixture('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720,CODECS="avc1.64001f"
/720-low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1280x720,CODECS="hvc1.1.6.L120"
/720-high.m3u8
''');

    expect(await fixture.service.resolveCctvGuidHdPlayback('guid'), isNull);
  });

  test('lower unsupported rendition cannot replace the highest supported HD',
      () async {
    final fixture = _fixture('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1920x1080,CODECS="avc3.640028,mp4a.40.2"
/1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1280x720,CODECS="hvc1.1.6.L120"
/720.m3u8
''');

    final playback = await fixture.service.resolveCctvGuidHdPlayback('guid');

    expect(playback!.variants.single.resolution, '1080p');
  });

  final invalidManifests = <String, String>{
    'SD only': '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=850000,RESOLUTION=640x360\n/sd.m3u8',
    'unknown resolution': '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=9000000\n/unknown.m3u8',
    'media playlist without resolution':
        '#EXTM3U\n#EXTINF:10.0,\n0.ts\n#EXT-X-ENDLIST',
    'HTML error page': '<html>Forbidden</html>',
    'invalid header': '#EXT-X-STREAM-INF:BANDWIDTH=2000000,'
        'RESOLUTION=1280x720\n/hd.m3u8',
    'missing bandwidth':
        '#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=1280x720\n/hd.m3u8',
    'zero bandwidth': '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=0,'
        'RESOLUTION=1280x720\n/hd.m3u8',
    'missing URI before another variant': '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\n/720.m3u8',
    'local URI': '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,'
        'RESOLUTION=1280x720\nfile:///video.m3u8',
    'empty codecs': '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,'
        'RESOLUTION=1280x720,CODECS=""\n/hd.m3u8',
    'unquoted codecs': '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,'
        'RESOLUTION=1280x720,CODECS=avc1.64001f\n/hd.m3u8',
    'audio only': '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,'
        'RESOLUTION=1280x720,CODECS="mp4a.40.2"\n/hd.m3u8',
  };
  for (final entry in invalidManifests.entries) {
    test('${entry.key} does not masquerade as native HD', () async {
      final fixture = _fixture(entry.value);

      expect(await fixture.service.resolveCctvGuidHdPlayback('guid'), isNull);
    });
  }

  test('missing H5E manifest never falls back to the clear SD URL', () async {
    final fixture = _fixture(_hdMaster, h5eUrl: null);

    expect(await fixture.service.resolveCctvGuidHdPlayback('guid'), isNull);
    expect(fixture.requests, hasLength(1));
  });

  test('non-HTTP H5E manifest is rejected before fetching it', () async {
    final fixture = _fixture(_hdMaster, h5eUrl: 'file:///main.m3u8');

    expect(await fixture.service.resolveCctvGuidHdPlayback('guid'), isNull);
    expect(fixture.requests, hasLength(1));
  });

  test('failed master response cannot become a playable HD variant', () async {
    final fixture = _fixture(_hdMaster, masterStatus: 403);

    expect(await fixture.service.resolveCctvGuidHdPlayback('guid'), isNull);
  });

  test('invalid duration does not discard a valid HD manifest', () async {
    final fixture = _fixture(_hdMaster, duration: 'NaN');

    final playback = await fixture.service.resolveCctvGuidHdPlayback('guid');

    expect(playback!.duration, Duration.zero);
    expect(playback.variants.single.resolution, '720p');
  });

  test('existing clear variants do not opt into H5E preprocessing', () {
    const variant = CctvStreamVariant(
      id: 'std',
      label: '标清',
      resolution: '360p',
      bitrateKbps: 850,
      url: 'https://cdn.example/850.m3u8',
    );

    expect(variant.isH5e, isFalse);
  });
}

const _hdMaster = '#EXTM3U\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\n/hd.m3u8';

/// Keeps the resolver tests offline while recording the outgoing URL and headers.
({CctvApiService service, List<RequestOptions> requests}) _fixture(
  String master, {
  String? h5eUrl = 'https://cdn.example/h5e/master/main.m3u8?token=master',
  Uri? redirect,
  int masterStatus = 200,
  String duration = '632.28',
}) {
  final requests = <RequestOptions>[];
  final dio = Dio(BaseOptions(headers: <String, dynamic>{
    'User-Agent': 'CCTV test agent',
    'Referer': 'https://tv.cctv.com/',
  }));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    requests.add(options);
    if (options.uri.host == 'vdn.apps.cntv.cn') {
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'hls_url': 'https://clear.example/sd/main.m3u8',
          'video': <String, dynamic>{'totalLength': duration},
          'manifest': <String, dynamic>{'hls_h5e_url': h5eUrl},
        },
      ));
      return;
    }
    handler.resolve(Response<String>(
      requestOptions: options,
      statusCode: masterStatus,
      data: master,
      redirects: <RedirectRecord>[
        if (redirect != null) RedirectRecord(302, 'GET', redirect),
      ],
    ));
  }));
  return (service: CctvApiService(dio: dio), requests: requests);
}
