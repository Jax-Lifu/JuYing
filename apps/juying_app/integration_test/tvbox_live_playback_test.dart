import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/player/player_engine.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

/// Opt-in live acceptance uses public catalogue data and the actual platform
/// texture/decoder. Upstream failures remain failures, never skipped successes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _liveCase(const TvBoxSite(
    key: 'tuxiaobei_acceptance',
    name: '兔小贝官方',
    api: 'https://example.invalid/drpy.js',
    ext: 'https://example.invalid/兔小贝.js',
  ));
  _liveCase(
    const TvBoxSite(
      key: 'cms_acceptance',
      name: '索尼 CMS',
      type: 1,
      api: 'https://suoniapi.com/api.php/provide/vod/',
    ),
    item: const MediaItem(id: '155702', title: '慢投垒球'),
  );
}

void _liveCase(TvBoxSite site, {MediaItem? item}) {
  const enabled = bool.fromEnvironment('JUYING_LIVE_PLAYBACK');
  testWidgets('${site.name} plays, seeks and resumes on the real device',
      (tester) async {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1100, 760));
    }
    final spider = TvBoxSpiderEngine();
    final categories = await spider.fetchSiteCategories(site);
    expect(categories, isNotEmpty);
    final items = item == null
        ? await spider.fetchCategoryMedia(site, categories.first.id)
        : [item];
    expect(items, isNotEmpty);
    final candidate =
        (await spider.fetchMediaCandidates(site, items.first)).single;
    expect(candidate.episodes.first.resolvePlayback, isNotNull);
    final errors = <String>[];
    var circuitTrips = 0;
    final engine = PlayerEngine(
      onError: errors.add,
      onCircuitBreakerTrip: () => circuitTrips++,
    );
    final player = engine.player;
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: items.first.title,
        currentEpisode: candidate.episodes.first,
        candidate: candidate,
        playerEngine: engine,
      ),
    ));
    await player.setVolume(0);
    Future<void> waitFor(bool Function() condition, String reason) async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(condition(), isTrue, reason: '$reason; errors=$errors');
    }

    await waitFor(
        () =>
            player.state.playing &&
            !player.state.buffering &&
            player.state.position > const Duration(seconds: 5),
        'native video advances');
    final native = player.platform as NativePlayer;
    final width = int.parse(await native.getProperty('width'));
    final height = int.parse(await native.getProperty('height'));
    expect(width, greaterThan(0));
    expect(height, greaterThan(0));
    await player.seek(const Duration(seconds: 30));
    await waitFor(() => player.state.position > const Duration(seconds: 31),
        'native seek completes and playback continues');
    await player.pause();
    await waitFor(() => !player.state.playing, 'pause takes effect');
    final paused = player.state.position;
    await player.play();
    await waitFor(
        () => player.state.position > paused + const Duration(seconds: 2),
        'resume advances');
    expect(errors, isEmpty);
    debugPrint('LIVE_TVBOX_ACCEPTANCE platform=${Platform.operatingSystem} '
        'title=${items.first.title} size=${width}x$height '
        'position=${player.state.position.inSeconds}s seek=ok resume=ok '
        'watchdogTrips=$circuitTrips');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }, skip: !enabled || (!Platform.isWindows && !Platform.isAndroid));
}
