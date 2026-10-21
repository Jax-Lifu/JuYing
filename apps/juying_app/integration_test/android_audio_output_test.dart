import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:juying/core/player/player_engine.dart';

/// Verifies the production audio backend with AAC without changing Android's
/// system routing or volume. Opt in with SPIDER_TEST_ORIGIN.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const origin = String.fromEnvironment('SPIDER_TEST_ORIGIN');
  testWidgets('Android default player opens AAC audio output', (tester) async {
    MediaKit.ensureInitialized();
    final engine = PlayerEngine();
    final player = engine.player;
    final native = player.platform as NativePlayer;
    final errors = <String>[];
    final errorSubscription = player.stream.error.listen(errors.add);
    addTearDown(() async {
      await errorSubscription.cancel();
      await engine.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: Video(controller: engine.videoController),
    ));
    await player.setVolume(0);
    final results = <Map<String, Object>>[];
    for (var round = 1; round <= 2; round++) {
      var restarted = round == 1;
      final restartSubscription = player.stream.position.listen((position) {
        if (position < const Duration(milliseconds: 500)) restarted = true;
      });
      await engine.openStream('$origin/audio.mp4');
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (
          (!restarted || player.state.position < const Duration(seconds: 2)) &&
              errors.isEmpty &&
              DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await restartSubscription.cancel();
      final result = <String, Object>{
        'round': round,
        'restarted': restarted,
        'ao': await native.getProperty('current-ao'),
        'decoded': await native.getProperty('audio-params/format'),
        'output': await native.getProperty('audio-out-params/format'),
        'sampleRate': await native.getProperty('audio-out-params/samplerate'),
        'channels': await native.getProperty('audio-out-params/channel-count'),
        'positionMs': player.state.position.inMilliseconds,
        'errors': List<String>.of(errors),
      };
      results.add(result);
      debugPrint('ANDROID_DEFAULT_AUDIO_OK ${jsonEncode(result)}');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final result in results) {
      expect(result['restarted'], isTrue);
      expect(result['ao'], isNotEmpty);
      expect(result['output'], isNotEmpty);
      expect(result['positionMs'] as int, greaterThanOrEqualTo(2000));
    }
    expect(errors, isEmpty);
  }, skip: !Platform.isAndroid || origin.isEmpty);
}
