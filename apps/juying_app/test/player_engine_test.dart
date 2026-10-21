import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:juying/core/player/player_engine.dart';

void main() {
  testWidgets('play request keeps the initial connection grace period',
      (tester) async {
    final platform = _TestPlayer();
    var trips = 0;
    final engine = PlayerEngine.forTesting(
      Player(platformPlayer: platform),
      onCircuitBreakerTrip: () => trips++,
    );
    addTearDown(engine.dispose);

    platform.emitPlaying();
    platform.emitBuffering();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(engine.hasStartedPlaying, isFalse);
    expect(trips, 0);
    await tester.pump(const Duration(seconds: 26));
    expect(trips, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(trips, 1, reason: 'A stalled initial connection still times out.');
    await tester.runAsync(engine.dispose);
  });

  testWidgets(
      'buffering after position advances still trips after three seconds',
      (tester) async {
    final platform = _TestPlayer();
    var trips = 0;
    final engine = PlayerEngine.forTesting(
      Player(platformPlayer: platform),
      onCircuitBreakerTrip: () => trips++,
    );
    addTearDown(engine.dispose);

    platform.emitPlaying();
    platform.emitPosition(const Duration(seconds: 1));
    platform.emitBuffering();
    await tester.pump();
    expect(engine.hasStartedPlaying, isTrue);
    await tester.pump(const Duration(milliseconds: 2500));
    expect(trips, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(trips, 1);
    await tester.runAsync(engine.dispose);
  });

  testWidgets('resume offset alone does not count as playback progress',
      (tester) async {
    final platform = _TestPlayer(failOpen: false);
    var trips = 0;
    final engine = PlayerEngine.forTesting(
      Player(platformPlayer: platform),
      onCircuitBreakerTrip: () => trips++,
    );
    addTearDown(engine.dispose);

    await engine.openStream('https://example.com/video.m3u8',
        startPosition: const Duration(seconds: 90));
    platform.emitPlaying();
    platform.emitPosition(const Duration(seconds: 90));
    platform.emitBuffering();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(engine.hasStartedPlaying, isFalse);
    expect(trips, 0);

    platform.emitPosition(const Duration(milliseconds: 90200));
    await tester.pump();
    expect(engine.hasStartedPlaying, isTrue);
    await tester.runAsync(engine.dispose);
  });

  testWidgets('pausing during initial loading suspends the watchdog',
      (tester) async {
    final platform = _TestPlayer();
    var trips = 0;
    final engine = PlayerEngine.forTesting(
      Player(platformPlayer: platform),
      onCircuitBreakerTrip: () => trips++,
    );
    addTearDown(engine.dispose);

    platform.emitPlaying();
    platform.emitBuffering();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    platform.emitPlaying(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(trips, 0);

    platform.emitPlaying();
    await tester.pump();
    await tester.pump(const Duration(seconds: 29));
    expect(trips, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(trips, 1);
    await tester.runAsync(engine.dispose);
  });

  test('network error events notify one recovery path only', () async {
    final platform = _TestPlayer();
    var trips = 0;
    final errors = <String>[];
    final engine = PlayerEngine.forTesting(
      Player(platformPlayer: platform),
      onCircuitBreakerTrip: () => trips++,
      onError: errors.add,
    );
    addTearDown(engine.dispose);

    platform.emitError('HTTP 403 connection failed');
    await Future<void>.delayed(Duration.zero);

    expect(errors, <String>['HTTP 403 connection failed']);
    expect(trips, 0, reason: 'The error callback already switches the route.');
  });

  test('network events still trip when no error callback is supplied',
      () async {
    final platform = _TestPlayer();
    var trips = 0;
    final engine = PlayerEngine.forTesting(
      Player(platformPlayer: platform),
      onCircuitBreakerTrip: () => trips++,
    );
    addTearDown(engine.dispose);

    platform.emitError('HTTP 403 connection failed');
    await Future<void>.delayed(Duration.zero);

    expect(trips, 1);
  });

  test('failed open does not switch routes before its caller handles it',
      () async {
    final platform = _TestPlayer();
    var trips = 0;
    final engine = PlayerEngine.forTesting(
      Player(platformPlayer: platform),
      onCircuitBreakerTrip: () => trips++,
    );
    addTearDown(engine.dispose);

    await expectLater(
      engine.openStream('https://example.com/live.m3u8'),
      throwsA(isA<StateError>()),
    );

    expect(trips, 0, reason: 'The rejected future already reaches recovery.');
  });

  group('PlayerEngine error classification', () {
    test('classifies network, decoder and manifest failures independently', () {
      expect(
        PlayerEngine.classifyFailure('HTTP 403 connection failed'),
        PlaybackFailureKind.network,
      );
      expect(
        PlayerEngine.classifyFailure('D3D11 texture decoder init failed'),
        PlaybackFailureKind.decoder,
      );
      expect(
        PlayerEngine.classifyFailure('invalid M3U8 manifest'),
        PlaybackFailureKind.manifest,
      );
    });

    test('treats non-seekable mpv advice as a recoverable warning', () {
      expect(
        PlayerEngine.isRecoverablePlaybackWarning(
          "You can force it with '--force-seekable=yes'.",
        ),
        isTrue,
      );
    });

    test('treats audio device init warning as recoverable', () {
      expect(
        PlayerEngine.isRecoverablePlaybackWarning(
          'Could not open/initialize audio device -> no sound.',
        ),
        isTrue,
      );
    });

    test('keeps decoder and network failures fatal', () {
      expect(
        PlayerEngine.isRecoverablePlaybackWarning('Failed to open stream'),
        isFalse,
      );
    });
  });
}

class _TestPlayer extends PlatformPlayer {
  _TestPlayer({this.failOpen = true})
      : super(configuration: const PlayerConfiguration());

  final bool failOpen;

  void emitError(String error) => errorController.add(error);

  void emitPosition(Duration position) => positionController.add(position);

  void emitPlaying([bool playing = true]) {
    state = state.copyWith(playing: playing);
    playingController.add(playing);
  }

  void emitBuffering() {
    state = state.copyWith(buffering: true);
    bufferingController.add(true);
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (failOpen) throw StateError('HTTP 403 connection failed');
  }
}
