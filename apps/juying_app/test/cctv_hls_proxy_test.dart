import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/cctv/services/cctv_hls_proxy.dart';

void main() {
  late HttpServer upstream;
  late HttpClient client;
  late CctvHlsProxy proxy;
  late String origin;
  late List<String> received;
  late List<int> decoded;
  late List<Object> errors;
  Completer<void>? stalled;

  String playlist(String first) => '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:10,
$first
#EXTINF:10,
2.ts?token=second
#EXTINF:9.5,
3.ts
#EXT-X-ENDLIST
''';

  Future<({int status, Uint8List body, HttpHeaders headers})> read(
    String url, {
    String method = 'GET',
    String? range,
  }) async {
    final request = await client.openUrl(method, Uri.parse(url));
    if (range != null) request.headers.set('Range', range);
    final response = await request.close();
    final data = BytesBuilder(copy: false);
    await for (final chunk in response) {
      data.add(chunk);
    }
    return (
      status: response.statusCode,
      body: data.takeBytes(),
      headers: response.headers
    );
  }

  List<String> segments(Uint8List body) => utf8
      .decode(body)
      .split('\n')
      .where((line) => line.startsWith('http://'))
      .toList();

  setUp(() async {
    received = <String>[];
    decoded = <int>[];
    errors = <Object>[];
    stalled = null;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = 'http://127.0.0.1:${upstream.port}';
    upstream.listen((request) async {
      received.add(request.uri.toString());
      try {
        switch (request.uri.path) {
          case '/redirect.m3u8':
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set('Location', '/vod/index.m3u8');
          case '/vod/index.m3u8':
            expect(request.headers.value('Referer'), 'https://tv.cctv.com/');
            request.response.write(playlist('1.ts?token=first'));
          case '/slow.m3u8':
            await stalled!.future;
            request.response.write(playlist('/vod/1.ts'));
          case '/invalid.m3u8':
            request.response.write(
                '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXT-X-ENDLIST');
          case '/fail.m3u8':
            request.response.write(playlist('/missing.ts'));
          case '/vod/1.ts':
          case '/vod/2.ts':
          case '/vod/3.ts':
            request.response.add(<int>[
              int.parse(request.uri.path.split('/').last[0]),
              10,
              20,
              30
            ]);
          default:
            request.response.statusCode = 404;
        }
        await request.response.close();
      } on Object {
        // A cancelled session intentionally closes in-flight upstream requests.
      }
    });
    client = HttpClient();
    proxy = CctvHlsProxy(
      onError: errors.add,
      decodeSegment: (bytes) async {
        decoded.add(bytes.first);
        return Uint8List.fromList(<int>[...bytes, 99]);
      },
    );
  });

  tearDown(() async {
    if (stalled != null && !stalled!.isCompleted) stalled!.complete();
    await proxy.dispose();
    client.close(force: true);
    await upstream.close(force: true);
  });

  Future<String> open() => proxy.open('$origin/vod/index.m3u8',
      headers: const <String, String>{'Referer': 'https://tv.cctv.com/'});

  test('keeps the whole VOD timeline and supports random segment access',
      () async {
    final local = await open();
    final manifest = await read(local);
    final text = utf8.decode(manifest.body);
    expect(text, contains('#EXTINF:9.5,'));
    expect(text, contains('#EXT-X-ENDLIST'));
    expect(text, isNot(contains('token=')));
    final urls = segments(manifest.body);
    expect(urls, hasLength(3));
    expect((await read(urls[2])).body, <int>[3, 10, 20, 30, 99]);
    expect((await read(urls[0])).body, <int>[1, 10, 20, 30, 99]);
    expect((await read(urls[2])).body.last, 99);
    expect(decoded, <int>[3, 1]);
    expect(received, contains('/vod/1.ts?token=first'));
    expect(errors, isEmpty);
  });

  test('ranges and HEAD operate on the processed bytes', () async {
    final urls = segments((await read(await open())).body);
    final part = await read(urls.first, range: 'bytes=1-3');
    expect(part.status, 206);
    expect(part.headers.value('Content-Range'), 'bytes 1-3/5');
    expect(part.body, <int>[10, 20, 30]);
    expect((await read(urls.first, range: 'bytes=-2')).body, <int>[30, 99]);
    expect((await read(urls.first, range: 'bytes=50-')).status, 416);
    final head = await read(urls.first, method: 'HEAD');
    expect(head.status, 200);
    expect(head.headers.contentLength, 5);
    expect(head.body, isEmpty);
    expect(decoded, <int>[1]);
  });

  test('switching episodes invalidates old URLs without decoder errors',
      () async {
    final old = await open();
    final oldSegments = segments((await read(old)).body);
    final current = await open();
    expect(current, isNot(old));
    expect((await read(oldSegments.first)).status, 404);
    expect((await read(current)).status, 200);
    expect(errors, isEmpty);
  });

  test('relative segments use the final redirected playlist directory',
      () async {
    final local = await proxy.open('$origin/redirect.m3u8',
        headers: const <String, String>{'Referer': 'https://tv.cctv.com/'});
    final urls = segments((await read(local)).body);
    expect((await read(urls.first)).status, 200);
    expect(received, contains('/vod/1.ts?token=first'));
    expect(errors, isEmpty);
  });

  test('a late old open cannot replace the new episode', () async {
    stalled = Completer<void>();
    final old = proxy.open('$origin/slow.m3u8');
    final cancelled = expectLater(old, throwsA(isA<Object>()));
    while (!received.contains('/slow.m3u8')) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final current = await open();
    stalled!.complete();
    await cancelled;
    expect((await read(current)).status, 200);
    expect(errors, isEmpty);
  });

  test('upstream failure reports once and never serves unprocessed bytes',
      () async {
    final local = await proxy.open('$origin/fail.m3u8');
    final urls = segments((await read(local)).body);
    expect((await read(urls.first)).status, 502);
    expect((await read(urls.first)).status, 502);
    expect(errors, hasLength(1));
    expect(decoded, isEmpty);
  });

  test('rejects unsupported manifests and closes an in-flight open', () async {
    await expectLater(
        proxy.open('$origin/invalid.m3u8'), throwsFormatException);
    stalled = Completer<void>();
    final pending = proxy.open('$origin/slow.m3u8');
    final cancelled = expectLater(pending, throwsA(isA<Object>()));
    while (!received.contains('/slow.m3u8')) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await proxy.dispose();
    stalled!.complete();
    await cancelled;
    await expectLater(open(), throwsStateError);
    expect(errors, isEmpty);
  });
}
