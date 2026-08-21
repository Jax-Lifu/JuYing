import 'package:flutter_test/flutter_test.dart';
import 'package:juying/features/player/infrastructure/native_player_backend.dart';

void main() {
  test('Windows 原生播放器允许 FFmpeg 使用系统 HTTP 代理协议', () {
    expect(
        nativePlaybackProtocolWhitelist,
        containsAll([
          'http',
          'https',
          'httpproxy',
          'crypto',
        ]));
  });
}
