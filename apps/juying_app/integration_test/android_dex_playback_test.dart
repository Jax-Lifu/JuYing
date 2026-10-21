import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/player/player_engine.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/android_dex_spider_adapter.dart';

/// Run against a real Android device. The host origin serves only the locally
/// compiled fixture.jar and generated media.mp4, reached with adb reverse.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixtureOrigin = String.fromEnvironment('SPIDER_TEST_ORIGIN');
  const channel = MethodChannel('com.flytech.juying/tvbox_dex');

  testWidgets('Android Dex lifecycle and selected episodes reach native video',
      (tester) async {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final dio = Dio();
    final video = (await dio.get<List<int>>('$fixtureOrigin/media.mp4',
            options: Options(responseType: ResponseType.bytes)))
        .data!;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = 'http://127.0.0.1:${server.port}';
    final webRequests = <String>[];
    final nativeRequests = <Map<String, String?>>[];
    var rejectedRequests = 0;
    final subscription = server.listen((request) async {
      final response = request.response;
      final episode = request.uri.queryParameters['episode'] ?? '';
      if (request.uri.path == '/player.html') {
        webRequests.add(episode);
        response.headers.contentType = ContentType.html;
        response.write('''<!DOCTYPE html><html><body><video controls></video>
<script>setTimeout(() => fetch('/firstbad.m3u8?episode=$episode')
  .then(() => fetch('/media.mp4?episode=$episode')), 500);</script>
</body></html>''');
      } else if (request.uri.path == '/firstbad.m3u8') {
        rejectedRequests++;
        response.statusCode = HttpStatus.forbidden;
        response.headers.contentType = ContentType.html;
        response.write('<html>Try the next media URL</html>');
      } else if (request.uri.path == '/media.mp4') {
        if (request.headers.value('x-source') != null) {
          nativeRequests.add({
            'episode': episode,
            'source': request.headers.value('x-source'),
            'flags': request.headers.value('x-vip-flags'),
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
        // Closing the parsing WebView cancels its media fetch intentionally.
      }
    });
    addTearDown(() async {
      await channel.invokeMethod<void>('disposeAll');
      dio.close(force: true);
      await subscription.cancel();
      await server.close(force: true);
    });

    final adapter = AndroidDexSpiderAdapter(dio: dio);
    var site = TvBoxSite(
      key: 'android-fixture',
      name: 'Local Android fixture',
      api: 'csp_Fixture',
      jar: '$fixtureOrigin/fixture.jar',
      ext: {'origin': origin, 'label': 'initial'},
      flags: const ['vip-a', 'vip-b'],
    );
    final categories = await Future.wait([
      adapter.fetchCategories(site),
      adapter.fetchCategories(site.copyWith(key: 'android-fixture-concurrent')),
    ]);
    expect(categories.every((list) => list.single.name == 'initial'), isTrue);
    site = site.copyWith(ext: {'origin': origin, 'label': 'refreshed'});
    expect((await adapter.fetchCategories(site)).single.name, 'refreshed');
    expect((await adapter.search(site, 'legacy-search')).single.title,
        'legacy-search');
    expect((await adapter.fetchCategory(site, 'fixture')).single.title,
        'refreshed');
    await expectLater(
      adapter.fetchCategories(site.copyWith(jar: '${site.jar};md5;00000000')),
      throwsA(isA<PlatformException>()),
    );

    final candidates = await adapter.fetchCandidates(
      site,
      const MediaItem(id: 'fixture-vod', title: 'Android Dex fixture'),
    );
    expect(candidates.single.episodes, hasLength(2));
    expect(webRequests, isEmpty);
    final errors = <String>[];
    final engine = PlayerEngine(onError: errors.add);
    final player = engine.player;
    final native = player.platform as NativePlayer;
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: 'Android Dex fixture',
        currentEpisode: candidates.single.episodes.first,
        candidate: candidates.single,
        playerEngine: engine,
      ),
    ));
    await player.setVolume(0);

    Future<void> waitForEpisode(String episode) async {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      bool playing() =>
          player.state.position > const Duration(seconds: 2) &&
          player.state.playing &&
          !player.state.buffering &&
          player.state.playlist.medias.length == 1 &&
          player.state.playlist.medias.single.uri.endsWith('episode=$episode');
      while (!playing() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(playing(), isTrue,
          reason: '$episode must advance; errors=$errors; pages=$webRequests');
      expect(int.parse(await native.getProperty('width')), 320);
      expect(int.parse(await native.getProperty('height')), 180);
      debugPrint('ANDROID_DEX_NATIVE_OK episode=$episode size=320x180 '
          'position=${player.state.position.inMilliseconds}ms');
    }

    await waitForEpisode('ep1');
    expect(webRequests, ['ep1']);
    final selector = find.text('选集');
    if (selector.hitTestable().evaluate().isEmpty) {
      await tester.tapAt(tester.getCenter(find.byType(VideoPlayerPage)));
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(selector);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('第2集').last);
    await waitForEpisode('ep2');
    expect(webRequests, ['ep1', 'ep2']);
    expect(rejectedRequests, 2);
    for (final episode in ['ep1', 'ep2']) {
      final requests = nativeRequests.where((r) => r['episode'] == episode);
      expect(requests, isNotEmpty);
      expect(requests.every((r) => r['source'] == 'refreshed'), isTrue);
      expect(requests.every((r) => r['flags'] == 'vip-a,vip-b'), isTrue);
      expect(
          requests.every(
              (r) => r['referer'] == '$origin/player.html?episode=$episode'),
          isTrue);
      expect(requests.any((r) => r['range'] != null), isTrue);
    }
    expect(errors, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }, skip: !Platform.isAndroid || fixtureOrigin.isEmpty);
}
