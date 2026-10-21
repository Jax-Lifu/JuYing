import 'package:test/test.dart';
import 'package:juying_player_engine/juying_player_engine.dart';

void main() {
  group('PlayerEngine Dual-Engine & Capability Tests (ADR-002 & PLY-13)', () {
    test('MpvEngine initializes with default capabilities and emits state',
        () async {
      final engine = MpvEngine();
      expect(engine.name, equals('libmpv'));
      expect(engine.capabilities.supports4K, isTrue);
      expect(engine.capabilities.supportsDolbyVision, isFalse);

      final states = <EnginePlayerState>[];
      final subscription = engine.state.listen(states.add);

      await engine
          .open(const PlayableOption(url: 'https://example.com/test.m3u8'));
      await engine.pause();
      await engine.play();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(states.length, greaterThanOrEqualTo(2));
      expect(states.last.isPlaying, isTrue);

      await subscription.cancel();
      await engine.dispose();
    });

    test(
        'Media3Engine supports Dolby Vision and Audio Passthrough on Android TV',
        () async {
      final engine = Media3Engine();
      expect(engine.name, equals('media3'));
      expect(engine.capabilities.supportsDolbyVision, isTrue);
      expect(engine.capabilities.supportsDolbyAudioPassthrough, isTrue);

      await engine.dispose();
    });

    test(
        'DualEngineDispatcher dispatches Dolby & Live to Media3 on Android TV and Mpv elsewhere',
        () {
      final mpv = MpvEngine();
      final media3 = Media3Engine();
      final dispatcher =
          DualEngineDispatcher(mpvEngine: mpv, media3Engine: media3);

      // On Desktop / Mobile: always Mpv
      final desktopResult = dispatcher.dispatch(
        isAndroidTv: false,
        option: const PlayableOption(
          url: 'http://example.com/stream',
          isLive: true,
          requiresDolbyVision: true,
        ),
      );
      expect(desktopResult.name, equals('libmpv'));

      // On Android TV with Dolby Vision: dispatches to Media3
      final tvDolbyResult = dispatcher.dispatch(
        isAndroidTv: true,
        option: const PlayableOption(
          url: 'http://example.com/stream',
          requiresDolbyVision: true,
        ),
      );
      expect(tvDolbyResult.name, equals('media3'));

      // On Android TV with Live: dispatches to Media3 (OwnTV pattern)
      final tvLiveResult = dispatcher.dispatch(
        isAndroidTv: true,
        option: const PlayableOption(
          url: 'http://example.com/cctv.m3u8',
          isLive: true,
        ),
      );
      expect(tvLiveResult.name, equals('media3'));

      // On Android TV with standard VOD: dispatches to Mpv
      final tvVodResult = dispatcher.dispatch(
        isAndroidTv: true,
        option: const PlayableOption(
          url: 'http://example.com/movie.mp4',
          isLive: false,
        ),
      );
      expect(tvVodResult.name, equals('libmpv'));
    });
  });
}
