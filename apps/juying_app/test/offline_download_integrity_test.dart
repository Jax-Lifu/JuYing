import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/download/services/offline_download_manager.dart';

void main() {
  for (final unsupportedTag in <String>[
    '#EXT-X-MAP:URI="init.mp4"',
    '#EXT-X-BYTERANGE:2@1',
  ]) {
    test('rejects $unsupportedTag before publishing an offline file', () async {
      var rejectLayout = true;
      final requestedPaths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requestedPaths.add(request.uri.path);
        if (request.uri.path == '/playlist.m3u8') {
          request.response.write(
            '#EXTM3U\n'
            '${rejectLayout ? '$unsupportedTag\n' : ''}'
            'segment.ts\n#EXT-X-ENDLIST\n',
          );
        } else {
          request.response.write('COMPLETE');
        }
        await request.response.close();
      });
      final target = await Directory.systemTemp.createTemp('juying-layout-');
      final manager = OfflineDownloadManager();
      addTearDown(() async {
        await manager.dispose();
        await server.close(force: true);
        await target.delete(recursive: true);
      });

      DownloadTask enqueue() => manager.enqueueTask(
            id: 'layout',
            title: '离线布局',
            episodeName: '第1集',
            m3u8Url: 'http://127.0.0.1:${server.port}/playlist.m3u8',
            targetDirectory: target.path,
          );
      final task = enqueue();
      await manager.waitForTask(task.id);

      expect(task.status, DownloadTaskStatus.failed);
      expect(task.failureReason, 'unsupported_hls_layout');
      expect(task.outputFilePath, isNull);
      expect(requestedPaths, <String>['/playlist.m3u8']);
      expect(await target.list().isEmpty, isTrue);

      // A changed playlist can be retried; stale failure text must not survive.
      rejectLayout = false;
      expect(enqueue(), same(task));
      await manager.waitForTask(task.id);
      expect(task.status, DownloadTaskStatus.completed);
      expect(task.failureReason, isNull);
      expect(await File(task.outputFilePath!).readAsString(), 'COMPLETE');
    });
  }

  test('an interrupted segment is never exposed as a complete resume cache',
      () async {
    final partialSent = Completer<void>();
    final releasePartial = Completer<void>();
    var segmentRequests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        if (request.uri.path == '/playlist.m3u8') {
          request.response.write('#EXTM3U\n/segment.ts\n');
        } else if (++segmentRequests == 1) {
          request.response.contentLength = 8;
          request.response.write('PART');
          await request.response.flush();
          partialSent.complete();
          await releasePartial.future;
          request.response.write('TAIL');
        } else {
          request.response.write('COMPLETE');
        }
        await request.response.close();
      } on Object {
        // Cancelling a download closes its still-streaming HTTP response.
      }
    });
    final target = await Directory.systemTemp.createTemp('juying-partial-');
    final taskDirectory = Directory('${target.path}/partial');
    final manager = OfflineDownloadManager();
    addTearDown(() async {
      if (!releasePartial.isCompleted) releasePartial.complete();
      await manager.dispose();
      await server.close(force: true);
      await target.delete(recursive: true);
    });

    final task = manager.enqueueTask(
      id: 'partial',
      title: '中断恢复',
      episodeName: '第1集',
      m3u8Url: 'http://127.0.0.1:${server.port}/playlist.m3u8',
      targetDirectory: target.path,
    );
    await partialSent.future;
    final writingDeadline = DateTime.now().add(const Duration(seconds: 2));
    while (await taskDirectory.list().isEmpty &&
        DateTime.now().isBefore(writingDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await taskDirectory.list().isEmpty, isFalse);
    expect(await File('${taskDirectory.path}/seg_0.ts').exists(), isFalse);

    manager.pauseTask(task.id);
    releasePartial.complete();
    await manager.waitForTask(task.id);
    expect(task.status, DownloadTaskStatus.paused);
    expect(await File('${taskDirectory.path}/seg_0.ts').exists(), isFalse);

    // A process exit can leave the staging file behind; it is never resumable.
    await File('${taskDirectory.path}/seg_0.ts.tmp').writeAsString('PART');
    manager.resumeTask(task.id);
    await manager.waitForTask(task.id);
    expect(task.status, DownloadTaskStatus.completed);
    expect(segmentRequests, 2);
    expect(await File(task.outputFilePath!).readAsString(), 'COMPLETE');
    expect(await File('${taskDirectory.path}/seg_0.ts.tmp').exists(), isFalse);
  });

  test('resume during concatenation cannot publish the cancelled output',
      () async {
    final concatenationStarted = Completer<void>();
    final releaseConcatenation = Completer<void>();
    final secondPlaylistStarted = Completer<void>();
    final releaseSecondPlaylist = Completer<void>();
    var playlistRequests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/playlist.m3u8') {
        if (++playlistRequests == 2) {
          secondPlaylistStarted.complete();
          await releaseSecondPlaylist.future;
        }
        request.response.write('#EXTM3U\n/segment.ts\n');
      } else {
        request.response.write('COMPLETE');
      }
      await request.response.close();
    });
    final target = await Directory.systemTemp.createTemp('juying-concat-');
    final segment = File('${target.path}/concat/seg_0.ts');
    await segment.parent.create();
    await segment.writeAsString('COMPLETE');
    final manager = OfflineDownloadManager();
    addTearDown(() async {
      if (!releaseConcatenation.isCompleted) releaseConcatenation.complete();
      if (!releaseSecondPlaylist.isCompleted) releaseSecondPlaylist.complete();
      await manager.dispose();
      await server.close(force: true);
      await target.delete(recursive: true);
    });

    await IOOverrides.runWithIOOverrides(() async {
      final task = manager.enqueueTask(
        id: 'concat',
        title: '拼接暂停',
        episodeName: '第1集',
        m3u8Url: 'http://127.0.0.1:${server.port}/playlist.m3u8',
        targetDirectory: target.path,
      );
      await concatenationStarted.future;
      manager.pauseTask(task.id);
      manager.resumeTask(task.id);
      releaseConcatenation.complete();
      await secondPlaylistStarted.future;

      expect(task.status, DownloadTaskStatus.downloading);
      expect(task.outputFilePath, isNull);
      manager.pauseTask(task.id);
      releaseSecondPlaylist.complete();
      await manager.waitForTask(task.id);
    }, _GatedSegmentReads(segment, concatenationStarted, releaseConcatenation));
  });

  test('pause immediately after resume still cancels the replacement run',
      () async {
    final firstSegmentStarted = Completer<void>();
    final secondPlaylistStarted = Completer<void>();
    final releaseResponses = Completer<void>();
    var playlistRequests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/race.m3u8') {
        playlistRequests++;
        if (playlistRequests == 2) {
          secondPlaylistStarted.complete();
          await releaseResponses.future;
        }
        request.response.write('#EXTM3U\n/segment.ts\n');
      } else {
        if (!firstSegmentStarted.isCompleted) firstSegmentStarted.complete();
        await releaseResponses.future;
        request.response.write('COMPLETE');
      }
      await request.response.close();
    });
    final target = await Directory.systemTemp.createTemp('juying-pause-');
    final manager = OfflineDownloadManager();
    addTearDown(() async {
      if (!releaseResponses.isCompleted) releaseResponses.complete();
      await manager.dispose();
      await server.close(force: true);
      await target.delete(recursive: true);
    });
    final task = manager.enqueueTask(
      id: 'race',
      title: '暂停恢复',
      episodeName: '第1集',
      m3u8Url: 'http://127.0.0.1:${server.port}/race.m3u8',
      targetDirectory: target.path,
    );
    await firstSegmentStarted.future;
    manager.pauseTask(task.id);
    manager.resumeTask(task.id);
    await secondPlaylistStarted.future;
    manager.pauseTask(task.id);
    releaseResponses.complete();
    await manager.waitForTask(task.id);

    expect(task.status, DownloadTaskStatus.paused);
    expect(task.outputFilePath, isNull);
  });

  test(
      'completed download contains every non-empty segment and keeps TS suffix',
      () async {
    final server = await _playlistServer();
    final target = await Directory.systemTemp.createTemp('juying-download-');
    final manager = OfflineDownloadManager();
    addTearDown(() async {
      await manager.dispose();
      await server.close(force: true);
      await target.delete(recursive: true);
    });

    final task = manager.enqueueTask(
      id: 'ok',
      title: '测试',
      episodeName: '第1集',
      m3u8Url: 'http://127.0.0.1:${server.port}/ok.m3u8',
      targetDirectory: target.path,
    );
    await manager.waitForTask(task.id);

    expect(task.status, DownloadTaskStatus.completed);
    expect(task.outputFilePath, endsWith('.ts'));
    expect(await File(task.outputFilePath!).readAsBytes(), utf8.encode('AABB'));
  });

  test('missing segment retries three times and never becomes completed',
      () async {
    var failedRequests = 0;
    final server = await _playlistServer(
      onFailedSegment: () => failedRequests++,
    );
    final target = await Directory.systemTemp.createTemp('juying-download-');
    final manager = OfflineDownloadManager();
    addTearDown(() async {
      await manager.dispose();
      await server.close(force: true);
      await target.delete(recursive: true);
    });

    final task = manager.enqueueTask(
      id: 'failed',
      title: '测试',
      episodeName: '第2集',
      m3u8Url: 'http://127.0.0.1:${server.port}/failed.m3u8',
      targetDirectory: target.path,
    );
    await manager.waitForTask(task.id);

    expect(failedRequests, 3);
    expect(task.status, DownloadTaskStatus.failed);
    expect(task.outputFilePath, isNull);
    expect(File('${target.path}/failed/failed.ts').existsSync(), isFalse);
  });

  test('selects highest bandwidth variant and decrypts AES-128 segments',
      () async {
    final key = Uint8List.fromList(List<int>.generate(16, (index) => index));
    final iv = Uint8List.fromList(
      List<int>.generate(16, (index) => index == 15 ? 1 : 0),
    );
    final encrypted = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc),
    ).encryptBytes(utf8.encode('HIGH'), iv: encrypt.IV(iv)).bytes;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      switch (request.uri.path) {
        case '/master.m3u8':
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1000\nlow/index.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=9000\nhigh/index.m3u8\n',
          );
        case '/low/index.m3u8':
          request.response.write('#EXTM3U\nlow.ts\n');
        case '/high/index.m3u8':
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-MEDIA-SEQUENCE:1\n'
            '#EXT-X-KEY:METHOD=AES-128,URI="key.bin",'
            'IV=0x00000000000000000000000000000001\n'
            'high.ts\n',
          );
        case '/high/key.bin':
          request.response.add(key);
        case '/high/high.ts':
          request.response.add(encrypted);
        case '/low/low.ts':
          request.response.add(utf8.encode('LOW'));
      }
      await request.response.close();
    });
    final target = await Directory.systemTemp.createTemp('juying-aes-');
    final manager = OfflineDownloadManager();
    addTearDown(() async {
      await manager.dispose();
      await server.close(force: true);
      await target.delete(recursive: true);
    });

    final task = manager.enqueueTask(
      id: 'aes',
      title: '加密视频',
      episodeName: '第1集',
      m3u8Url: 'http://127.0.0.1:${server.port}/master.m3u8',
      targetDirectory: target.path,
    );
    await manager.waitForTask(task.id);

    expect(task.status, DownloadTaskStatus.completed);
    expect(await File(task.outputFilePath!).readAsString(), 'HIGH');
  });

  test('resume reuses complete segment files instead of downloading again',
      () async {
    var cachedSegmentRequests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      switch (request.uri.path) {
        case '/resume.m3u8':
          request.response.write('#EXTM3U\n/cached.ts\n/fresh.ts\n');
        case '/cached.ts':
          cachedSegmentRequests++;
          request.response.add(utf8.encode('NETWORK'));
        case '/fresh.ts':
          request.response.add(utf8.encode('FRESH'));
      }
      await request.response.close();
    });
    final target = await Directory.systemTemp.createTemp('juying-resume-');
    final taskDirectory = Directory('${target.path}${Platform.pathSeparator}r');
    await taskDirectory.create(recursive: true);
    await File('${taskDirectory.path}${Platform.pathSeparator}seg_0.ts')
        .writeAsString('CACHED');
    final manager = OfflineDownloadManager();
    addTearDown(() async {
      await manager.dispose();
      await server.close(force: true);
      await target.delete(recursive: true);
    });

    final task = manager.enqueueTask(
      id: 'r',
      title: '断点续传',
      episodeName: '第1集',
      m3u8Url: 'http://127.0.0.1:${server.port}/resume.m3u8',
      targetDirectory: target.path,
    );
    await manager.waitForTask(task.id);

    expect(task.status, DownloadTaskStatus.completed);
    expect(cachedSegmentRequests, 0);
    expect(await File(task.outputFilePath!).readAsString(), 'CACHEDFRESH');
  });

  test('HLS propagates auth headers and isolates AES keys between tasks',
      () async {
    final requests = <String, Set<String>>{};
    final keys = <String, Uint8List>{
      for (var index = 1; index <= 2; index++)
        'Bearer test-$index': Uint8List(16)..fillRange(0, 16, index),
    };
    final iv = Uint8List(16)..[15] = 1;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final authorization = request.headers.value('Authorization') ?? '';
      final key = keys[authorization];
      if (key == null ||
          request.headers.value('Referer') != 'https://player.test/') {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      requests
          .putIfAbsent(authorization, () => <String>{})
          .add(request.uri.path);
      switch (request.uri.path) {
        case '/master.m3u8':
          request.response
              .write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nmedia.m3u8\n');
        case '/media.m3u8':
          request.response.write(
            '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:1\n'
            '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
            'encrypted.ts\n#EXT-X-KEY:METHOD=NONE\nplain.ts\n',
          );
        case '/key.bin':
          request.response.add(key);
        case '/encrypted.ts':
          request.response.add(
            encrypt.Encrypter(
              encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc),
            )
                .encryptBytes(utf8.encode(authorization), iv: encrypt.IV(iv))
                .bytes,
          );
        case '/plain.ts':
          request.response.write('-TAIL');
      }
      await request.response.close();
    });
    final target = await Directory.systemTemp.createTemp('juying-auth-hls-');
    final manager = OfflineDownloadManager();
    addTearDown(() async {
      await manager.dispose();
      await server.close(force: true);
      await target.delete(recursive: true);
    });

    for (var index = 1; index <= 2; index++) {
      final authorization = 'Bearer test-$index';
      final task = manager.enqueueTask(
        id: 'auth-$index',
        title: '授权加密视频',
        episodeName: '第$index集',
        m3u8Url: 'http://127.0.0.1:${server.port}/master.m3u8',
        targetDirectory: target.path,
        headers: <String, String>{
          'Referer': 'https://player.test/',
          'Authorization': authorization,
        },
      );
      await manager.waitForTask(task.id);

      expect(task.status, DownloadTaskStatus.completed);
      expect(await File(task.outputFilePath!).readAsString(),
          '$authorization-TAIL');
      expect(requests[authorization], <String>{
        '/master.m3u8',
        '/media.m3u8',
        '/key.bin',
        '/encrypted.ts',
        '/plain.ts',
      });
    }
  });
}

Future<HttpServer> _playlistServer({void Function()? onFailedSegment}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    switch (request.uri.path) {
      case '/ok.m3u8':
        request.response.write('#EXTM3U\n/a.ts\n/b.ts\n');
        break;
      case '/failed.m3u8':
        request.response.write('#EXTM3U\n/a.ts\n/missing.ts\n');
        break;
      case '/a.ts':
        request.response.add(utf8.encode('AA'));
        break;
      case '/b.ts':
        request.response.add(utf8.encode('BB'));
        break;
      case '/missing.ts':
        onFailedSegment?.call();
        request.response.statusCode = HttpStatus.internalServerError;
        break;
      default:
        request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return server;
}

final class _GatedSegmentReads extends IOOverrides {
  _GatedSegmentReads(this.segment, this.started, this.release);

  final File segment;
  final Completer<void> started;
  final Completer<void> release;

  @override
  File createFile(String path) =>
      path.replaceAll('\\', '/') == segment.path.replaceAll('\\', '/')
          ? _GatedSegmentFile(segment, started, release)
          : super.createFile(path);
}

class _GatedSegmentFile extends Fake implements File {
  _GatedSegmentFile(this.file, this.started, this.release);

  final File file;
  final Completer<void> started;
  final Completer<void> release;

  @override
  String get path => file.path;

  @override
  Future<bool> exists() => file.exists();

  @override
  Future<int> length() => file.length();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      file.open(mode: mode);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    if (!started.isCompleted) started.complete();
    await release.future;
    yield* file.openRead(start, end);
  }
}
