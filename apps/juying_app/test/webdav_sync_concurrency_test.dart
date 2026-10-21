import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/sync/services/webdav_sync_service.dart';

void main() {
  for (final scenario in <String>['changed', 'created', 'unversioned']) {
    final existedAtDownload = scenario != 'created';
    test(
      'preserves a remote replica $scenario after download',
      () async {
        const historyPath = '/dav/JuYing/sync/v1/history.json.gz';
        final files = <String, List<int>>{
          if (existedAtDownload) historyPath: _historyBytes('original'),
        };
        var revision = 1;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          final path = request.uri.path;
          if (request.method == 'PUT') {
            files[path] = await request.fold<List<int>>(
              <int>[],
              (bytes, chunk) => bytes..addAll(chunk),
            );
            request.response.statusCode = HttpStatus.created;
          } else {
            await request.drain<void>();
            switch (request.method) {
              case 'MKCOL':
                request.response.statusCode = HttpStatus.methodNotAllowed;
              case 'GET':
              case 'HEAD':
                final bytes = files[path];
                if (bytes == null) {
                  request.response.statusCode = HttpStatus.notFound;
                } else {
                  if (scenario != 'unversioned') {
                    request.response.headers
                        .set('etag', '"revision-$revision"');
                  }
                  if (request.method == 'GET') request.response.add(bytes);
                }
              case 'MOVE':
                final destination =
                    Uri.parse(request.headers.value('destination')!).path;
                final existing = files.containsKey(destination);
                final condition = request.headers.value('if');
                if ((existing && request.headers.value('overwrite') == 'F') ||
                    (condition != null &&
                        condition !=
                            '<http://127.0.0.1:${server.port}$destination> (["revision-$revision"])')) {
                  request.response.statusCode = HttpStatus.preconditionFailed;
                } else {
                  files[destination] = files.remove(path)!;
                  request.response.statusCode = HttpStatus.created;
                }
              case 'DELETE':
                files.remove(path);
                request.response.statusCode = HttpStatus.noContent;
            }
          }
          await request.response.close();
        });
        final service = WebDavSyncService();
        final baseUrl = 'http://127.0.0.1:${server.port}/dav';
        final downloaded = await service.downloadSyncBundle(
          webDavUrl: baseUrl,
          username: 'reader',
          password: 'secret',
        );

        // A second device publishes data after this device's merge snapshot.
        final concurrentBytes = _historyBytes('concurrent-device-progress');
        files[historyPath] = concurrentBytes;
        revision = 2;
        final uploaded = await service.uploadSyncBundle(
          webDavUrl: baseUrl,
          username: 'reader',
          password: 'secret',
          bundle:
              downloaded ?? const SyncBundle(deviceId: 'local', updatedAtMs: 1),
        );

        expect(uploaded, isFalse);
        expect(files[historyPath], concurrentBytes);
      },
    );
  }
}

List<int> _historyBytes(String id) => gzip.encode(
      utf8.encode(
        jsonEncode(<String, Object>{
          'schemaVersion': 1,
          'deviceId': 'remote',
          'updatedAt': 1000,
          'data': <Map<String, Object>>[
            <String, Object>{'entityId': id, 'updatedAt': 1000},
          ],
        }),
      ),
    );
