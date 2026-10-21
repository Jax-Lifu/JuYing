import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juying/features/sync/services/webdav_sync_service.dart';

void main() {
  for (final payload in <Object?>[
    null,
    <String, Object>{},
    <String, Object>{'data': 'invalid'},
    <String, Object>{
      'data': <Object?>[null]
    },
  ]) {
    test('rejects unreadable remote payload: ${jsonEncode(payload)}', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        if (payload != null) {
          request.response.add(gzip.encode(utf8.encode(jsonEncode(payload))));
        }
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      await expectLater(
        WebDavSyncService().downloadSyncBundle(
          webDavUrl: 'http://127.0.0.1:${server.port}/dav',
          username: 'user',
          password: 'password',
        ),
        throwsFormatException,
      );
    });
  }

  test('uses split gzip files and atomic MOVE, then downloads them', () async {
    final files = <String, List<int>>{};
    final methods = <String>[];
    final moveHeaders = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.forEach((request) async {
      methods.add('${request.method} ${request.uri.path}');
      switch (request.method) {
        case 'MKCOL':
          request.response.statusCode = HttpStatus.created;
        case 'HEAD':
          if (files.containsKey(request.uri.path)) {
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.set('etag', '"revision-1"');
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
        case 'PUT':
          files[request.uri.path] = await request.fold<List<int>>(
            <int>[],
            (bytes, chunk) => bytes..addAll(chunk),
          );
          request.response.statusCode = HttpStatus.created;
        case 'MOVE':
          final destination = request.headers.value('destination')!;
          final destinationPath = Uri.parse(destination).path;
          moveHeaders.add(request.headers.value('if') ?? '');
          files[destinationPath] = files.remove(request.uri.path)!;
          request.response.statusCode = HttpStatus.created;
        case 'DELETE':
          files.remove(request.uri.path);
          request.response.statusCode = HttpStatus.noContent;
        case 'GET':
          final bytes = files[request.uri.path];
          if (bytes == null) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.statusCode = HttpStatus.ok;
            request.response.add(bytes);
          }
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await serving;
    });
    final service = WebDavSyncService();
    final baseUrl = 'http://127.0.0.1:${server.port}/dav';
    const original = SyncBundle(
      deviceId: 'windows-device',
      updatedAtMs: 1234,
      history: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'movie_1', 'progress': 0.5},
      ],
      favorites: <Map<String, dynamic>>[
        <String, dynamic>{'entityId': 'movie_1', 'title': '聚映'},
      ],
      subscriptions: <Map<String, dynamic>>[
        <String, dynamic>{
          'entityId': 'source_1',
          'url': 'https://example.test'
        },
      ],
      settings: <String, dynamic>{'theme': 'dark'},
    );

    expect(
      await service.uploadSyncBundle(
        webDavUrl: baseUrl,
        username: 'user',
        password: 'app-password',
        bundle: original,
      ),
      isTrue,
    );

    for (final name in <String>[
      'history',
      'favorites',
      'subscriptions',
      'settings',
    ]) {
      final path = '/dav/JuYing/sync/v1/$name.json.gz';
      expect(files, contains(path));
      final payload = jsonDecode(utf8.decode(gzip.decode(files[path]!)));
      expect(payload['schemaVersion'], 1);
      expect(
          methods.any((value) => value.startsWith('MOVE $path.tmp-')), isTrue);
    }

    final downloaded = await service.downloadSyncBundle(
      webDavUrl: baseUrl,
      username: 'user',
      password: 'app-password',
    );
    expect(downloaded, isNotNull);
    expect(downloaded!.history.single['entityId'], 'movie_1');
    expect(downloaded.history.single['updatedAt'], 1234);
    expect(downloaded.settings['theme'], 'dark');
    expect(moveHeaders, everyElement(isEmpty));
  });

  test('uses destination ETag as MOVE precondition', () async {
    final files = <String, List<int>>{};
    String? condition;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.forEach((request) async {
      if (request.method == 'MKCOL') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      } else if (request.method == 'HEAD') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set('etag', '"revision-2"');
      } else if (request.method == 'PUT') {
        files[request.uri.path] = await request.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'MOVE') {
        condition = request.headers.value('if');
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'DELETE') {
        request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await serving;
    });

    final ok = await WebDavSyncService().uploadSyncBundle(
      webDavUrl: 'http://127.0.0.1:${server.port}/dav',
      username: 'user',
      password: 'password',
      bundle: const SyncBundle(deviceId: 'pc', updatedAtMs: 10),
    );

    expect(ok, isTrue);
    expect(condition, contains('(["revision-2"])'));
  });
}
