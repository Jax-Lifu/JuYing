import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/nas/models/nas_server_config.dart';
import 'package:juying/features/nas/services/webdav_client.dart';

void main() {
  for (final responseCase in <({String name, int status, String? range})>[
    (name: 'ignores Range', status: HttpStatus.ok, range: null),
    (name: 'returns an error page', status: HttpStatus.notFound, range: null),
    (
      name: 'omits Content-Range',
      status: HttpStatus.partialContent,
      range: null
    ),
    (
      name: 'returns the wrong offset',
      status: HttpStatus.partialContent,
      range: 'bytes 0-2/5',
    ),
    (
      name: 'returns the wrong end',
      status: HttpStatus.partialContent,
      range: 'bytes 1-2/5',
    ),
  ]) {
    test('rejects an upstream that ${responseCase.name}', () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      upstream.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = responseCase.status;
        if (responseCase.range != null) {
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            responseCase.range!,
          );
        }
        request.response.add(<int>[0, 1, 2]);
        await request.response.close();
      });
      final httpClient = HttpClient();
      addTearDown(() => httpClient.close(force: true));
      final client = WebDavClient(httpClient: httpClient);

      await expectLater(
        client.openRangeStream(
          server: _server(upstream.port),
          filePath: '/video.mp4',
          start: 1,
          end: 3,
        ),
        throwsA(isA<HttpException>()),
      );
    });
  }

  test('forwards exact Range bytes and basic authorization', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => upstream.close(force: true));
    upstream.listen((request) async {
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=1-3');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Basic ${base64Encode(utf8.encode('reader:secret'))}',
      );
      await request.drain<void>();
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers
          .set(HttpHeaders.contentRangeHeader, 'bytes 1-3/5');
      request.response.contentLength = 3;
      request.response.add(<int>[1, 2, 3]);
      await request.response.close();
    });
    final httpClient = HttpClient();
    addTearDown(() => httpClient.close(force: true));
    final client = WebDavClient(httpClient: httpClient);

    final stream = await client.openRangeStream(
      server: _server(upstream.port),
      filePath: '/video.mp4',
      start: 1,
      end: 3,
    );
    expect(await stream.expand((chunk) => chunk).toList(), <int>[1, 2, 3]);
  });

  test('browses and opens returned WebDAV paths with the share prefix once',
      () async {
    final paths = <String>[];
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => upstream.close(force: true));
    upstream.listen((request) async {
      paths.add(request.uri.path);
      await request.drain<void>();
      if (request.method == 'PROPFIND') {
        request.response.statusCode = HttpStatus.multiStatus;
        request.response.write('''
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/video.mp4</D:href>
    <D:propstat><D:prop><D:getcontentlength>5</D:getcontentlength></D:prop></D:propstat>
  </D:response>
</D:multistatus>''');
      } else {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes 1-3/5');
        request.response.add(<int>[1, 2, 3]);
      }
      await request.response.close();
    });
    final httpClient = HttpClient();
    addTearDown(() => httpClient.close(force: true));
    final client = WebDavClient(httpClient: httpClient);
    final server = _server(upstream.port).copyWith(shareName: 'dav');

    final items = await client.listDirectory(server, '/');
    final file = items.firstWhere((item) => !item.isDirectory);
    final stream = await client.openRangeStream(
      server: server,
      filePath: file.path,
      start: 1,
      end: 3,
    );
    await stream.drain<void>();

    expect(paths, <String>['/dav/', '/dav/video.mp4']);
    expect(items, hasLength(1));
  });
}

NasServerConfig _server(int port) => NasServerConfig(
      id: 'webdav-test',
      name: 'WebDAV test',
      protocol: NasProtocol.webdav,
      host: '127.0.0.1',
      port: port,
      username: 'reader',
      password: 'secret',
    );
