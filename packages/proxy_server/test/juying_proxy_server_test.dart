import 'dart:convert';
import 'dart:io';

import 'package:juying_proxy_server/juying_proxy_server.dart';
import 'package:test/test.dart';

void main() {
  group('LoopbackStreamProxy Tests', () {
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
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes $expectedStart-4/5',
        );
        expect(response.contentLength, 5 - expectedStart);
        expect(
          await response.fold<List<int>>(
            <int>[],
            (all, part) => all..addAll(part),
          ),
          <int>[0, 1, 2, 3, 4].sublist(expectedStart),
        );
      }
      expect(resolvedRanges, <(int, int?)>[(3, 4), (0, 4), (0, 4)]);

      for (final range in <String>['bytes=-0', 'bytes=-', 'bytes=-abc']) {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(HttpHeaders.rangeHeader, range);
        final response = await request.close();
        expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes */5',
        );
        await response.drain<void>();
      }
      expect(resolvedRanges, hasLength(3));
    });

    test('HEAD preserves GET metadata without opening the stream', () async {
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
            response.headers.value(header),
            getResponse.headers.value(header),
          );
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
        ownerId: 'range-owner',
        contentLength: 10,
        resolver: (start, end) async => Stream<List<int>>.value(
          <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9].sublist(start, end! + 1),
        ),
      );

      final uri = Uri.parse(url);
      final token = uri.pathSegments.last;
      expect(proxy.containsToken(token), isTrue);
      expect(
        RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(token),
        isTrue,
        reason: 'Token 必须为 UUID v4 格式以防止路径枚举',
      );

      final client = HttpClient();
      addTearDown(client.close);

      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.partialContent);
      expect(
          resp.headers.value(HttpHeaders.contentRangeHeader), 'bytes 2-5/10');
      expect(resp.contentLength, 4);
      expect(
        await resp.fold<List<int>>(<int>[], (all, part) => all..addAll(part)),
        <int>[2, 3, 4, 5],
      );
    });
  });

  group('LanGatewayServer Tests', () {
    test('requires pairing code and issues Bearer session token', () async {
      final gateway = LanGatewayServer();
      addTearDown(gateway.dispose);
      expect(await gateway.start(port: 0), isTrue);
      final code = gateway.pairingCode;
      expect(code, isNotNull);
      expect(code!.length, 6);

      final client = HttpClient();
      addTearDown(client.close);

      // 1. Wrong code rejected
      final wrongReq = await client.postUrl(
        Uri.parse('http://127.0.0.1:${gateway.port}/api/pair'),
      );
      wrongReq.headers.contentType = ContentType.json;
      wrongReq.write(jsonEncode(<String, dynamic>{'code': '000000'}));
      final wrongResp = await wrongReq.close();
      expect(wrongResp.statusCode, HttpStatus.unauthorized);
      await wrongResp.drain<void>();

      // 2. Correct code accepted
      final pairReq = await client.postUrl(
        Uri.parse('http://127.0.0.1:${gateway.port}/api/pair'),
      );
      pairReq.headers.contentType = ContentType.json;
      pairReq.write(jsonEncode(<String, dynamic>{'code': code}));
      final pairResp = await pairReq.close();
      expect(pairResp.statusCode, HttpStatus.ok);
      final pairJson = jsonDecode(await pairResp.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      expect(pairJson['success'], isTrue);
      final token = pairJson['token'] as String;
      expect(token, isNotEmpty);

      // 3. Authorized push succeeds
      final pushReq = await client.postUrl(
        Uri.parse('http://127.0.0.1:${gateway.port}/api/push_config'),
      );
      pushReq.headers.contentType = ContentType.json;
      pushReq.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      pushReq.write(
        jsonEncode(<String, dynamic>{'url': 'https://example.com/tvbox.json'}),
      );
      final pushResp = await pushReq.close();
      expect(pushResp.statusCode, HttpStatus.ok);
      final pushJson = jsonDecode(await pushResp.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      expect(pushJson['success'], isTrue);
    });
  });
}
