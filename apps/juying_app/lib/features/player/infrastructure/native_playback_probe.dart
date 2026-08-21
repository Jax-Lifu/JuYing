import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'native_player_backend.dart';

/// Debug 构建的真实后端探针；用于验证 FFmpeg 已经开始推进媒体时间轴。
Future<bool> probeNativePlayback(Uri uri) async {
  final player = createNativePlayer();
  final outcome = Completer<bool>();
  late final StreamSubscription<Duration> positionSubscription;
  late final StreamSubscription<String> errorSubscription;
  positionSubscription = player.stream.position.listen((position) {
    if (position >= const Duration(milliseconds: 500) && !outcome.isCompleted) {
      outcome.complete(true);
    }
  });
  errorSubscription = player.stream.error.listen((error) {
    if (error.trim().isNotEmpty && !outcome.isCompleted) {
      outcome.complete(false);
    }
  });
  try {
    await player.open(Media(uri.toString()), play: true);
    return await outcome.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => false,
    );
  } finally {
    await positionSubscription.cancel();
    await errorSubscription.cancel();
    await player.dispose();
  }
}
