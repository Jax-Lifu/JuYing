import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/proxy/local_proxy_server.dart';

void main() {
  test('loopback proxy serves suffix ranges and clips them to the file',
      () async {
    final proxy = LoopbackStreamProxy();
    addTearDown(proxy.stop);
    expect(await proxy.start(port: 0), isTrue);
    final resolvedRanges = <(int, int?)>[];
    final url = proxy.register(
      ownerId: 'suffix-owner',
      contentLength: 5,
      resolver: (start, end) async {
        resolvedRanges.add((start, end));
        return Stream<List<int>>.value(
          <int>[0, 1, 2, 3, 4].sublist(start, end! + 1),
        );
      },
    );
    final client = HttpClient();
    addTearDown(client.close);

    for (final suffixLength in <int>[2, 5, 10]) {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=-$suffixLength');
      final response = await request.close();
      final expectedStart = suffixLength < 5 ? 5 - suffixLength : 0;
      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes $expectedStart-4/5');
      expect(response.contentLength, 5 - expectedStart);
      expect(
          await response.fold<List<int>>(
            <int>[],
            (all, part) => all..addAll(part),
          ),
          <int>[0, 1, 2, 3, 4].sublist(expectedStart));
    }
    expect(resolvedRanges, <(int, int?)>[(3, 4), (0, 4), (0, 4)]);

    for (final range in <String>['bytes=-0', 'bytes=-', 'bytes=-abc']) {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(
          response.headers.value(HttpHeaders.contentRangeHeader), 'bytes */5');
      await response.drain<void>();
    }
    expect(resolvedRanges, hasLength(3));
  });

  test('HEAD preserves GET metadata without opening the NAS stream', () async {
    final proxy = LoopbackStreamProxy();
    addTearDown(proxy.stop);
    expect(await proxy.start(port: 0), isTrue);
    var openedStreams = 0;
    final url = proxy.register(
      ownerId: 'head-owner',
      contentLength: 5,
      resolver: (start, end) async {
        openedStreams++;
        return Stream<List<int>>.value(<int>[0, 1, 2, 3, 4]);
      },
    );
    final client = HttpClient();
    addTearDown(client.close);
    final getResponse = await (await client.getUrl(Uri.parse(url))).close();
    await getResponse.drain<void>();
    expect(openedStreams, 1);

    for (final range in <String?>[null, 'bytes=-2']) {
      final request = await client.headUrl(Uri.parse(url));
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      for (final header in <String>[
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        expect(
            response.headers.value(header), getResponse.headers.value(header));
      }
      expect(response.headers.value(HttpHeaders.contentRangeHeader), isNull);
      expect(await response.isEmpty, isTrue);
      expect(openedStreams, 1);
    }
  });

  test('loopback proxy uses UUID tokens and validates byte ranges', () async {
    final proxy = LoopbackStreamProxy();
    addTearDown(proxy.stop);
    expect(await proxy.start(port: 0), isTrue);

    final url = proxy.register(
      ownerId: 'test-owner',
      contentLength: 5,
      resolver: (start, end) async => Stream<List<int>>.value(
          <int>[0, 1, 2, 3, 4].sublist(start, end! + 1)),
    );
    expect(
      Uri.parse(url).pathSegments.last,
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-')),
    );

    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=1-3');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.partialContent);
    expect(
        response.headers.value(HttpHeaders.contentRangeHeader), 'bytes 1-3/5');
    expect(
        await response
            .fold<List<int>>(<int>[], (all, part) => all..addAll(part)),
        <int>[1, 2, 3]);

    final invalidRequest = await client.getUrl(Uri.parse(url));
    invalidRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=10-20');
    expect((await invalidRequest.close()).statusCode,
        HttpStatus.requestedRangeNotSatisfiable);
  });

  test('LAN push requires a valid, unexpired pairing session', () async {
    var now = DateTime(2026, 8, 26, 10);
    final gateway = LanGatewayServer(now: () => now);
    addTearDown(gateway.dispose);
    expect(await gateway.start(port: 0), isTrue);
    final base = Uri.parse('http://127.0.0.1:${gateway.port}');
    final client = HttpClient();
    addTearDown(client.close);

    Future<HttpClientResponse> post(
      String path,
      Map<String, Object> body, {
      String? token,
    }) async {
      final request = await client.postUrl(base.resolve(path));
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.write(jsonEncode(body));
      return request.close();
    }

    expect(
      (await post('/api/push_stream',
              <String, Object>{'url': 'https://media.test/a'}))
          .statusCode,
      HttpStatus.unauthorized,
    );
    final pairResponse = await post(
      '/api/pair',
      <String, Object>{'code': gateway.pairingCode!},
    );
    final pairBody = jsonDecode(await utf8.decoder.bind(pairResponse).join())
        as Map<String, dynamic>;
    final token = pairBody['token']! as String;
    expect(
      (await post(
        '/api/push_stream',
        <String, Object>{'url': 'https://media.test/a'},
        token: token,
      ))
          .statusCode,
      HttpStatus.ok,
    );

    now = now.add(const Duration(minutes: 31));
    expect(
      (await post(
        '/api/push_stream',
        <String, Object>{'url': 'https://media.test/b'},
        token: token,
      ))
          .statusCode,
      HttpStatus.unauthorized,
    );
  });
}
