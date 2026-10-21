import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:webview_windows/webview_windows.dart' as win_wv;
import 'package:window_manager/window_manager.dart';

import 'package:juying/core/player/player_engine.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';
import 'package:juying/features/player/presentation/cctv_official_web_player_page.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';

/// Opt-in live Windows acceptance: real VDN/CDN, FFI, HLS proxy and video texture.
/// Run with --dart-define=CCTV_NATIVE_LIVE=true; no media is persisted.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('CCTV_NATIVE_LIVE');
  const wholeEpisode =
      bool.fromEnvironment('CCTV_NATIVE_WHOLE_EPISODE', defaultValue: true);

  testWidgets('Windows CCTV HD whole episode, seek, episode switch and WebView',
      (tester) async {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1280, 720));
    final api = CctvApiService();
    final candidate =
        await api.fetchAlbumEpisodes('VIDA8lgsyrdD1LuVvEdkr2Fd260625');
    expect(candidate, isNotNull);
    expect(candidate!.episodes.length, greaterThanOrEqualTo(2));
    final episodes = candidate.episodes;
    final errors = <String>[];
    final engine = PlayerEngine(onError: errors.add);
    final player = engine.player;
    final native = player.platform as NativePlayer;
    // VideoController initializes after the first frame, before player calls.
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: '小小围棋少年',
        currentEpisode: episodes.first,
        candidate: candidate,
        playerEngine: engine,
        cctvApiService: api,
      ),
    ));
    debugPrint('CCTV_NATIVE page mounted');
    // Keep this unattended check quiet; audio decoding remains enabled.
    await player.setVolume(0).timeout(const Duration(seconds: 15));

    Future<void> waitFor(bool Function() ready, String reason,
        {Duration timeout = const Duration(seconds: 45)}) async {
      final deadline = DateTime.now().add(timeout);
      var nextReport = DateTime.now().add(const Duration(minutes: 1));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (DateTime.now().isAfter(nextReport)) {
          debugPrint('CCTV_NATIVE $reason position=${player.state.position} '
              'playing=${player.state.playing} buffering=${player.state.buffering}');
          nextReport = DateTime.now().add(const Duration(minutes: 1));
        }
      }
      expect(ready(), isTrue,
          reason: '$reason; errors=$errors; position=${player.state.position}');
    }

    await waitFor(
        () => player.state.position > const Duration(seconds: 3), 'HD starts');
    final width = int.parse(await native.getProperty('width'));
    final height = int.parse(await native.getProperty('height'));
    expect(width, greaterThanOrEqualTo(1280));
    expect(height, greaterThanOrEqualTo(720));
    expect(player.state.duration, greaterThan(const Duration(minutes: 5)));
    expect(player.state.playlist.medias.single.uri,
        startsWith('http://127.0.0.1:'));
    final firstSessionUri = player.state.playlist.medias.single.uri;
    debugPrint(
        'CCTV_NATIVE start ${width}x$height duration=${player.state.duration} hwdec=${await native.getProperty('hwdec-current')}');
    // Keep the long unattended run out of the user's foreground workspace.
    if (wholeEpisode) {
      await windowManager.hide();
      await tester.pump(const Duration(milliseconds: 300));
      // The page normally pauses when hidden; explicitly resume this test run.
      await player.play();
    }

    // Keep normal speed for the entire episode, including every TS boundary.
    await waitFor(() => player.state.position > const Duration(seconds: 22),
        'normal playback crosses segments');
    if (wholeEpisode) {
      await waitFor(() => player.state.completed, 'whole episode reaches EOF',
          timeout: const Duration(minutes: 8));
      expect(player.state.position.inSeconds,
          greaterThan(player.state.duration.inSeconds - 3));
      debugPrint(
          'CCTV_NATIVE whole_episode EOF position=${player.state.position} duration=${player.state.duration}');
      await windowManager.show();
      await tester.pump();
    }

    Future<void> showControls(Finder control) async {
      if (control.hitTestable().evaluate().isEmpty) {
        await tester.tapAt(const Offset(600, 300));
        await tester.pump();
      }
      expect(control.hitTestable(), findsOneWidget);
    }

    await showControls(find.byType(Slider));
    var slider = tester.getRect(find.byType(Slider));
    await tester.timedDragFrom(
      Offset(slider.left + slider.width * 0.2, slider.center.dy),
      Offset(slider.width * 0.4, 0),
      const Duration(milliseconds: 600),
    );
    await player.play();
    final forward = player.state.duration.inMilliseconds * 0.6;
    await waitFor(
        () =>
            (player.state.position.inMilliseconds - forward).abs() < 15000 &&
            !player.state.buffering,
        'forward seek resumes');
    final forwardPosition = player.state.position;
    await waitFor(
        () =>
            player.state.position >
            forwardPosition + const Duration(seconds: 2),
        'forward playback advances');
    await showControls(find.byType(Slider));
    slider = tester.getRect(find.byType(Slider));
    await tester.timedDragFrom(
      Offset(slider.left + slider.width * 0.6, slider.center.dy),
      Offset(-slider.width * 0.45, 0),
      const Duration(milliseconds: 600),
    );
    final backward = player.state.duration.inMilliseconds * 0.15;
    await waitFor(
        () =>
            (player.state.position.inMilliseconds - backward).abs() < 15000 &&
            !player.state.buffering,
        'backward seek resumes');
    final backwardPosition = player.state.position;
    await waitFor(
        () =>
            player.state.position >
            backwardPosition + const Duration(seconds: 2),
        'backward playback advances');
    debugPrint(
        'CCTV_NATIVE seek forward=$forwardPosition backward=${player.state.position}');

    // Exercise the actual episode drawer rather than calling a private switch.
    await showControls(find.text('选集'));
    await tester.tap(find.text('选集'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(episodes[1].shortName).last);
    await tester.pump(const Duration(milliseconds: 300));
    await waitFor(
        () =>
            player.state.position > const Duration(seconds: 3) &&
            player.state.position < const Duration(seconds: 12) &&
            player.state.playlist.medias.single.uri != firstSessionUri &&
            player.state.playing &&
            !player.state.buffering,
        'second episode starts at its beginning');
    expect(int.parse(await native.getProperty('height')),
        greaterThanOrEqualTo(720));
    expect(find.byType(CctvOfficialWebPlayerPage), findsNothing);
    debugPrint(
        'CCTV_NATIVE episode_switch position=${player.state.position} height=${await native.getProperty('height')}');
    expect(errors, isEmpty);

    await player.seek(const Duration(seconds: 90));
    await waitFor(
        () =>
            player.state.position > const Duration(seconds: 92) &&
            player.state.position < const Duration(seconds: 100) &&
            !player.state.buffering,
        'second episode advances before fallback');
    final handoffPosition = player.state.position.inMilliseconds / 1000;
    await showControls(find.text('官方播放器'));
    await tester.tap(find.text('官方播放器'));
    await tester.pump(const Duration(milliseconds: 300));
    await waitFor(
        () => find.byType(CctvOfficialWebPlayerPage).evaluate().isNotEmpty,
        'manual WebView fallback');
    final web = tester.widget<CctvOfficialWebPlayerPage>(
        find.byType(CctvOfficialWebPlayerPage));
    expect(web.currentEpisode.url, episodes[1].url);
    expect(web.episodes.length, episodes.length);
    expect((web.initialPosition.inMilliseconds / 1000 - handoffPosition).abs(),
        lessThan(3));
    await waitFor(() => find.byType(win_wv.Webview).evaluate().isNotEmpty,
        'Windows WebView initializes');
    final controller =
        tester.widget<win_wv.Webview>(find.byType(win_wv.Webview)).controller;
    Future<Map<String, dynamic>> readWebVideo() async {
      final value = await controller.executeScript(r'''
(() => {
  const video = Array.from(document.querySelectorAll(
    '#h5player_player, #_video_player_html5_api, video.vjs-tech, video'
  )).find(element => {
    const rect = element.getBoundingClientRect();
    return element instanceof HTMLMediaElement && rect.width > 100 && rect.height > 100;
  });
  return {
    href: location.href,
    guid: typeof window.guid === 'string' ? window.guid : null,
    currentTime: video?.currentTime ?? null,
    duration: video && Number.isFinite(video.duration) ? video.duration : null,
    readyState: video?.readyState ?? null,
    paused: video?.paused ?? null,
    seeking: video?.seeking ?? null,
    width: video?.videoWidth ?? null,
    height: video?.videoHeight ?? null,
    frames: video?.getVideoPlaybackQuality?.().totalVideoFrames ?? null
  };
})()
''');
      return Map<String, dynamic>.from(value as Map);
    }

    Future<Map<String, dynamic>> waitForWeb(
        bool Function(Map<String, dynamic>) ready, String reason) async {
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      var state = <String, dynamic>{};
      var nextReport = DateTime.now();
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        state = await readWebVideo();
        if (ready(state)) return state;
        if (DateTime.now().isAfter(nextReport)) {
          debugPrint('CCTV_WEB waiting $reason $state');
          nextReport = DateTime.now().add(const Duration(seconds: 10));
        }
      }
      fail('$reason; last WebView state=$state');
    }

    bool isPlaying(Map<String, dynamic> state, String episodeUrl) =>
        state['guid'] == episodeUrl.replaceFirst('cctv_guid://', '') &&
        (state['readyState'] as num? ?? 0) >= 2 &&
        state['paused'] == false &&
        state['seeking'] == false;
    final resumed = await waitForWeb(
        (state) =>
            isPlaying(state, episodes[1].url) &&
            ((state['currentTime'] as num? ?? 0) - handoffPosition).abs() < 8,
        'fallback resumes the current episode position');
    expect(Uri.parse(resumed['href'] as String).path,
        Uri.parse(episodes[1].officialPageUrl!).path);
    final advanced = await waitForWeb(
        (state) =>
            isPlaying(state, episodes[1].url) &&
            (state['currentTime'] as num) >
                (resumed['currentTime'] as num) + 2 &&
            (state['frames'] as num) > (resumed['frames'] as num),
        'resumed WebView decodes and advances');
    debugPrint('CCTV_WEB resumed native=$handoffPosition web=$resumed '
        'advanced=$advanced');

    // Use the real seek control: periodic page preparation must not restore again.
    await controller.executeScript(r'''
(() => {
  const progress = document.querySelector('#juying-controls .jy-progress');
  const video = Array.from(document.querySelectorAll('video'))
    .find(element => element.getBoundingClientRect().width > 100);
  progress.value = String(35 / video.duration * 1000);
  progress.dispatchEvent(new Event('input', {bubbles: true}));
})()
''');
    final userSeek = await waitForWeb(
        (state) =>
            isPlaying(state, episodes[1].url) &&
            (state['currentTime'] as num) >= 35 &&
            (state['currentTime'] as num) < 45,
        'WebView user seek stays at the new position');
    await waitForWeb(
        (state) =>
            isPlaying(state, episodes[1].url) &&
            (state['currentTime'] as num) >
                (userSeek['currentTime'] as num) + 8 &&
            (state['currentTime'] as num) < 55,
        'initial resume is applied only once');

    await controller
        .executeScript("document.getElementById('juying-episodes').click()");
    await waitFor(
        () =>
            find.text(episodes.first.name).hitTestable().evaluate().isNotEmpty,
        'WebView episode drawer finishes opening');
    await tester.tap(find.text(episodes.first.name).hitTestable().last);
    final nextEpisode = await waitForWeb(
        (state) =>
            isPlaying(state, episodes.first.url) &&
            (state['currentTime'] as num) > 2 &&
            (state['currentTime'] as num) < 12,
        'WebView episode selection starts at zero');
    expect(Uri.parse(nextEpisode['href'] as String).path,
        Uri.parse(episodes.first.officialPageUrl!).path);
    debugPrint(
        'CCTV_WEB user_seek=$userSeek new_episode=$nextEpisode; retained ${web.episodes.length} episodes');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 11)));
}
