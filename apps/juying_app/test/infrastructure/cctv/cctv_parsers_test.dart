import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:juying/infrastructure/cctv/cctv_exception.dart';
import 'package:juying/infrastructure/cctv/cctv_parsers.dart';
import 'package:juying/infrastructure/cctv/cctv_models.dart';

void main() {
  group('CctvParsers.catalog', () {
    test('parses the public album response', () {
      final body = jsonEncode({
        'data': {
          'total': 1,
          'list': [
            {
              'id': 'album-1',
              'title': '测试节目',
              'url': 'https://tv.cctv.com/2026/01/01/album.shtml',
              'image2': 'https://p1.img.cctvpic.com/poster.jpg',
              'year': '2026',
              'count': '12',
              'video': {
                'title': '第1集',
                'url': 'https://tv.cctv.com/2026/01/01/episode.shtml',
              },
            },
          ],
        },
      });

      final result = CctvParsers.catalog(
        body,
        page: 1,
        category: CctvCatalogCategory.animation,
      );

      expect(result.total, 1);
      expect(result.items.single.title, '测试节目');
      expect(result.items.single.episodeCount, 12);
      expect(result.items.single.episodePageUrl.host, 'tv.cctv.com');
    });

    test('drops entries that point outside the official page host', () {
      final body = jsonEncode({
        'data': {
          'total': 1,
          'list': [
            {
              'id': 'album-1',
              'title': '测试节目',
              'url': 'https://example.com/not-official',
              'video': {'url': 'https://example.com/not-official'},
            },
          ],
        },
      });

      expect(
        CctvParsers.catalog(
          body,
          page: 1,
          category: CctvCatalogCategory.animation,
        ).items,
        isEmpty,
      );
    });
  });

  group('CctvParsers.pageGuid', () {
    test('extracts the guid explicitly exposed by the page', () {
      const guid = 'ba561716b9d44a84b080af3b64bd13c9';
      expect(
          CctvParsers.pageGuid('<script>var guid = "$guid";</script>'), guid);
    });

    test('does not guess a guid from unrelated page content', () {
      expect(
        () =>
            CctvParsers.pageGuid('<div>ba561716b9d44a84b080af3b64bd13c9</div>'),
        throwsA(isA<CctvException>()),
      );
    });
  });

  group('CctvParsers.search', () {
    test('keeps only official result pages and removes markup', () {
      final items = CctvParsers.search(jsonEncode({
        'list': [
          {
            'id': 'video-1',
            'title': '<font color="red">熊出没</font>',
            'all_title': '动画《熊出没》',
            'urllink': 'https://tv.cctv.com/2026/01/01/video.shtml',
            'imglink': 'https://p1.img.cctvpic.com/poster.jpg',
            'channel': 'CCTV 动画片',
          },
          {
            'id': 'other',
            'title': '非官方',
            'urllink': 'https://example.com/video.shtml',
          },
        ],
      }));

      expect(items, hasLength(1));
      expect(items.single.title, '动画《熊出没》');
      expect(items.single.channel, 'CCTV 动画片');
    });
  });

  group('CctvParsers.episodes', () {
    test('parses public episode data without executing page scripts', () {
      const html = '''
        <script>
          var jsonData2=[
            {'title':'测试节目 第1集','img':'https://p1.img.cctvpic.com/one.jpg','url':'https://tv.cctv.com/2026/01/01/one.shtml'},
            {'title':'测试节目 第2集','url':'https://tv.cctv.com/2026/01/02/two.shtml'}
          ];
        </script>
      ''';

      final episodes = CctvParsers.episodes(html, programId: 'album-1');

      expect(episodes, hasLength(2));
      expect(episodes.first.number, 1);
      expect(episodes.last.officialPageUrl.path, '/2026/01/02/two.shtml');
    });

    test('rejects episode URLs outside the official host', () {
      const html =
          '''var jsonData=[{'title':'测试','url':'https://example.com/one.shtml'}];''';
      expect(CctvParsers.episodes(html, programId: 'album-1'), isEmpty);
    });
  });

  group('CctvParsers.playback', () {
    const guid = 'ba561716b9d44a84b080af3b64bd13c9';
    final officialPage = Uri.parse('https://tv.cctv.com/episode.shtml');

    test('accepts a public CCTV HLS URL', () {
      final body = jsonEncode({
        'ack': 'yes',
        'play': '1',
        'is_protected': '0',
        'is_invalid_copyright': '0',
        'title': '第1集',
        'image': 'https://p1.img.cctvpic.com/poster.jpg',
        'hls_url': 'https://hls.cntv.lxdns.com/path/main.m3u8?maxbr=2048',
        'video': {'totalLength': '60.5'},
      });

      final media = CctvParsers.playback(
        body,
        guid: guid,
        officialPageUri: officialPage,
      );

      expect(media.streamUri.host, 'hls.cntv.lxdns.com');
      expect(media.duration, const Duration(milliseconds: 60500));
      expect(media.httpHeaders['Referer'], officialPage.toString());
    });

    test('accepts a public HTTP HLS URL returned by the official metadata', () {
      final body = jsonEncode({
        'ack': 'yes',
        'play': '1',
        'is_protected': '0',
        'hls_url': 'http://hls.cntv.lxdns.com/path/live.m3u8?token=public',
      });

      final media = CctvParsers.playback(
        body,
        guid: guid,
        officialPageUri: officialPage,
      );

      expect(media.streamUri.scheme, 'http');
      expect(media.streamUri.host, 'hls.cntv.lxdns.com');
    });

    test('rejects protected media', () {
      final body = jsonEncode({
        'ack': 'yes',
        'play': '1',
        'is_protected': '1',
        'hls_url': 'https://hls.cntv.lxdns.com/path/main.m3u8',
      });

      expect(
        () => CctvParsers.playback(
          body,
          guid: guid,
          officialPageUri: officialPage,
        ),
        throwsA(isA<CctvException>()),
      );
    });

    test('rejects untrusted stream hosts', () {
      final body = jsonEncode({
        'ack': 'yes',
        'play': '1',
        'is_protected': '0',
        'hls_url': 'https://example.com/path/main.m3u8',
      });

      expect(
        () => CctvParsers.playback(
          body,
          guid: guid,
          officialPageUri: officialPage,
        ),
        throwsA(isA<CctvException>()),
      );
    });

    test('accepts the official qcloud CDN returned by CCTV playback metadata',
        () {
      final body = jsonEncode({
        'ack': 'yes',
        'play': '1',
        'is_protected': '0',
        'hls_url':
            'https://newcntv.qcloudcdn.com/asp/hls/main/example/main.m3u8?maxbr=450',
      });

      final media = CctvParsers.playback(
        body,
        guid: guid,
        officialPageUri: officialPage,
      );

      expect(media.streamUri.host, 'newcntv.qcloudcdn.com');
    });

    test('keeps the native-compatible HLS when an HTML5 playlist is present',
        () {
      final body = jsonEncode({
        'ack': 'yes',
        'play': '1',
        'is_protected': '0',
        'hls_url': 'https://newcntv.qcloudcdn.com/asp/hls/main.m3u8',
        'manifest': {
          'hls_h5e_url':
              'https://dh5wx.cntv.kfcbest.com/asp/h5e/hls/main/example/main.m3u8?maxbr=2048',
        },
      });

      final media = CctvParsers.playback(
        body,
        guid: guid,
        officialPageUri: officialPage,
      );

      expect(media.streamUri.host, 'newcntv.qcloudcdn.com');
    });
  });

  group('CctvParsers.hlsQualities', () {
    test('keeps validated variants declared by a public master playlist', () {
      const masterPlaylist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3600000,RESOLUTION=1920x1080
1080/index.m3u8
''';

      final qualities = CctvParsers.hlsQualities(
        masterPlaylist,
        baseUri: Uri.parse('https://hls.cntv.lxdns.com/live/master.m3u8'),
      );

      expect(qualities.map((quality) => quality.label), ['1080P', '720P']);
      expect(qualities.first.streamUri.path, '/live/1080/index.m3u8');
    });

    test('does not accept untrusted variants', () {
      const masterPlaylist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720
https://example.com/720/index.m3u8
''';

      expect(
        CctvParsers.hlsQualities(
          masterPlaylist,
          baseUri: Uri.parse('https://hls.cntv.lxdns.com/live/master.m3u8'),
        ),
        isEmpty,
      );
    });

    test('keeps variants from the official qcloud CDN', () {
      const masterPlaylist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=460800,RESOLUTION=480x270
/asp/hls/450/example/450.m3u8
''';

      final qualities = CctvParsers.hlsQualities(
        masterPlaylist,
        baseUri: Uri.parse(
          'https://newcntv.qcloudcdn.com/asp/hls/main/example/main.m3u8',
        ),
      );

      expect(qualities.single.label, '270P');
      expect(qualities.single.streamUri.host, 'newcntv.qcloudcdn.com');
    });

    test('maps the CCTV HTML5 master playlist to the four official labels', () {
      const masterPlaylist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=460800,RESOLUTION=480x270
/asp/h5e/hls/450/example/450.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=870400,RESOLUTION=640x360
/asp/h5e/hls/850/example/850.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1228800,RESOLUTION=1280x720
/asp/h5e/hls/1200/example/1200.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2048000,RESOLUTION=1280x720
/asp/h5e/hls/2000/example/2000.m3u8
''';

      final qualities = CctvParsers.hlsQualities(
        masterPlaylist,
        baseUri: Uri.parse(
          'https://dh5wx.cntv.kfcbest.com/asp/h5e/hls/main/example/main.m3u8',
        ),
      );

      expect(
        qualities.map((quality) => quality.label),
        ['超清', '高清', '标清', '流畅'],
      );
      expect(qualities.first.height, 720);
      expect(qualities.first.bandwidth, 2048000);
    });
  });
}
