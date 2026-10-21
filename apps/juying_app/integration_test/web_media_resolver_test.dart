import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/core/player/player_engine.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';
import 'package:juying/features/player/presentation/web_media_resolver.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/t4_http_spider_adapter.dart';

/// Uses real platform WebViews against local HTTP only. Heartbeats prove completed
/// and cancelled player documents stop executing after the dialog is removed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WebView resolves media and releases success and cancelled pages',
      (tester) async {
    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1100, 760));
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = 'http://127.0.0.1:${server.port}';
    var heartbeats = 0;
    final subscription = server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/heartbeat') {
        heartbeats++;
        response.write('ok');
      } else if (request.uri.path == '/master.m3u8') {
        response.headers.contentType = ContentType('application', 'x-mpegURL');
        response.write('#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-ENDLIST\n');
      } else {
        final resolve = request.uri.path == '/player.html';
        response.headers.contentType = ContentType.html;
        response.write('''<!DOCTYPE html><html><body>
<p>Local player fixture</p><video controls></video>
<script>
setInterval(() => fetch('/heartbeat'), 100);
${resolve ? "setTimeout(() => fetch('/master.m3u8'), 350);" : ''}
</script></body></html>''');
      }
      await response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    Object? result;
    var page = '/player.html';
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: TextButton(
            onPressed: () {
              unawaited(resolveWebMedia(
                context,
                PlaybackEpisode(
                  name: 'Local episode',
                  url: '$origin$page',
                  requiresWebView: true,
                  headers: const {'X-Source': 'fixture'},
                ),
              ).then<void>(
                (value) => result = value,
                onError: (Object error) => result = error,
              ));
            },
            child: const Text('resolve local page'),
          ),
        );
      }),
    ));

    Future<void> waitFor(bool Function() condition, String reason) async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(condition(), isTrue, reason: '$reason; result=$result');
    }

    Future<void> verifyPageReleased() async {
      await tester.pumpAndSettle(const Duration(milliseconds: 50),
          EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('web-media-cancel')), findsNothing);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final stoppedCount = heartbeats;
      await tester.pump(const Duration(milliseconds: 600));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(heartbeats, stoppedCount,
          reason: 'disposed page must stop sending heartbeats');
    }

    await tester.tap(find.text('resolve local page'));
    await waitFor(() => result != null, 'browser discovers HLS request');
    expect(result, isA<PlaybackEpisode>());
    final resolved = result as PlaybackEpisode;
    expect(resolved.url, '$origin/master.m3u8');
    expect(resolved.requiresWebView, isFalse);
    expect(resolved.headers?['X-Source'], 'fixture');
    expect(resolved.headers?['Referer'], '$origin/player.html');
    expect(resolved.headers?['User-Agent'], isNotEmpty);
    expect(heartbeats, greaterThan(0));
    await verifyPageReleased();

    result = null;
    page = '/cancel.html';
    final previousCount = heartbeats;
    await tester.tap(find.text('resolve local page'));
    await waitFor(
        () => heartbeats >= previousCount + 2, 'cancel page starts running');
    await tester.tap(find.byKey(const ValueKey('web-media-cancel')));
    await waitFor(() => result != null, 'cancel completes caller');
    expect(result, isA<WebMediaResolutionCancelled>());
    await verifyPageReleased();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !Platform.isWindows && !Platform.isAndroid);

  const videoPath = String.fromEnvironment('SPIDER_TEST_VIDEO_FILE');
  testWidgets('T4 selected episode resolves through WebView2 into native video',
      (tester) async {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1100, 760));
    final video = await File(videoPath).readAsBytes();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = 'http://127.0.0.1:${server.port}';
    final playerRequests = <String>[];
    final parserRequests = <String>[];
    final parserHeaders = <Map<String, String?>>[];
    final nativeRequests = <Map<String, String?>>[];
    var rejectedRequests = 0;
    var nativeRejectedRequests = 0;
    final subscription = server.listen((request) async {
      final response = request.response;
      final episode = request.uri.queryParameters['episode'] ?? '';
      if (request.uri.path == '/spider') {
        response.headers.contentType = ContentType.json;
        final play = request.uri.queryParameters['play'];
        if (play != null) {
          playerRequests.add(play);
          response.write(jsonEncode({
            'jx': 1,
            'url': '$origin/watch/$play',
            'header': {'X-Source': 'fixture'},
          }));
        } else {
          response.write(jsonEncode({
            'list': [
              {
                'vod_id': 'programme',
                'vod_name': 'Local T4 programme',
                'vod_play_from': 'local',
                'vod_play_url': r'第1集$ep1#第2集$ep2',
              }
            ],
          }));
        }
      } else if (request.uri.path == '/parse') {
        final target = Uri.parse(request.uri.queryParameters['url']!);
        final selected = target.pathSegments.last;
        parserRequests.add(selected);
        parserHeaders.add({
          'parser': request.headers.value('x-parser'),
          'source': request.headers.value('x-source'),
        });
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({
          'parse': 1,
          'url': '$origin/player.html?episode=$selected',
        }));
      } else if (request.uri.path == '/player.html') {
        response.headers.contentType = ContentType.html;
        response.write('''<!DOCTYPE html><html><body><video controls></video>
<script>
fetch('/firstbad.m3u8?episode=$episode')
  .then(() => fetch('/media.mp4?episode=$episode'));
</script></body></html>''');
      } else if (request.uri.path == '/firstbad.m3u8') {
        rejectedRequests++;
        if (request.headers.value('x-source') != null) {
          nativeRejectedRequests++;
        }
        response.statusCode = HttpStatus.forbidden;
        response.headers.contentType = ContentType.html;
        response.write('<html>Try the next URL</html>');
      } else if (request.uri.path == '/media.mp4') {
        final source = request.headers.value('x-source');
        if (source != null) {
          nativeRequests.add({
            'episode': episode,
            'source': source,
            'referer': request.headers.value('referer'),
            'range': request.headers.value('range'),
          });
        }
        response.headers.contentType = ContentType('video', 'mp4');
        response.headers.set('Accept-Ranges', 'bytes');
        final range = RegExp(r'^bytes=(\d+)-(\d*)$')
            .firstMatch(request.headers.value('range') ?? '');
        final start = range == null ? 0 : int.parse(range.group(1)!);
        final requestedEnd = range?.group(2);
        final end = requestedEnd == null || requestedEnd.isEmpty
            ? video.length - 1
            : int.parse(requestedEnd).clamp(0, video.length - 1);
        if (start >= video.length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set('Content-Range', 'bytes */${video.length}');
        } else {
          if (range != null) {
            response.statusCode = HttpStatus.partialContent;
            response.headers
                .set('Content-Range', 'bytes $start-$end/${video.length}');
          }
          response.contentLength = end - start + 1;
          response.add(video.sublist(start, end + 1));
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      try {
        await response.close();
      } on SocketException {
        // Browser disposal intentionally cancels its in-flight media download.
      }
    });
    final dio = Dio();
    addTearDown(() async {
      dio.close(force: true);
      await subscription.cancel();
      await server.close(force: true);
    });
    final candidates = await T4HttpSpiderAdapter(dio).fetchCandidates(
      TvBoxSite(
        key: 'fixture',
        name: 'Local T4',
        type: 4,
        api: '$origin/spider',
        parses: [
          {
            'name': 'Local JSON',
            'type': 1,
            'url': '$origin/parse?url=',
            'ext': {
              'header': {'X-Parser': 'parser-fixture'},
            },
          },
        ],
      ),
      const MediaItem(id: 'programme', title: 'Local T4 programme'),
    );
    expect(candidates.single.episodes, hasLength(2));
    expect(playerRequests, isEmpty,
        reason: 'detail must not pre-resolve either episode');
    expect(parserRequests, isEmpty);
    final errors = <String>[];
    final engine = PlayerEngine(onError: errors.add);
    final player = engine.player;
    final native = player.platform as NativePlayer;
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: 'Local T4 programme',
        currentEpisode: candidates.single.episodes.first,
        candidate: candidates.single,
        playerEngine: engine,
      ),
    ));
    await player.setVolume(0);

    Future<void> waitFor(bool Function() condition, String reason) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(condition(), isTrue,
          reason: '$reason; errors=$errors; player requests=$playerRequests');
    }

    bool playingEpisode(String episode) =>
        player.state.position > const Duration(seconds: 2) &&
        player.state.playing &&
        !player.state.buffering &&
        player.state.playlist.medias.length == 1 &&
        player.state.playlist.medias.single.uri.endsWith('episode=$episode');

    await waitFor(() => playingEpisode('ep1'), 'first native episode advances');
    expect(playerRequests, ['ep1']);
    expect(parserRequests, ['ep1']);
    expect(int.parse(await native.getProperty('width')), 320);
    expect(int.parse(await native.getProperty('height')), 180);
    expect(find.byKey(const ValueKey('web-media-cancel')), findsNothing);
    final selector = find.text('选集');
    if (selector.hitTestable().evaluate().isEmpty) {
      await tester.tapAt(const Offset(500, 300));
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(selector);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('第2集').last);
    await waitFor(
        () => playingEpisode('ep2'), 'second native episode advances');
    expect(playerRequests, ['ep1', 'ep2']);
    expect(parserRequests, ['ep1', 'ep2']);
    expect(parserHeaders,
        everyElement({'parser': 'parser-fixture', 'source': null}));
    expect(rejectedRequests, 2);
    expect(nativeRejectedRequests, 0,
        reason: 'the failed web manifest must never reach mpv');
    for (final episode in ['ep1', 'ep2']) {
      final requests = nativeRequests.where((r) => r['episode'] == episode);
      expect(requests, isNotEmpty);
      expect(requests.every((r) => r['source'] == 'fixture'), isTrue);
      expect(
          requests.every(
              (r) => r['referer'] == '$origin/player.html?episode=$episode'),
          isTrue);
      expect(requests.any((r) => r['range'] != null), isTrue);
    }
    expect(int.parse(await native.getProperty('width')), 320);
    expect(int.parse(await native.getProperty('height')), 180);
    expect(errors, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }, skip: !Platform.isWindows || videoPath.isEmpty);
}
