import 'package:media_kit/media_kit.dart';

const nativePlaybackProtocolWhitelist = <String>[
  'udp',
  'rtp',
  'tcp',
  'tls',
  'data',
  'file',
  'http',
  'https',
  'httpproxy',
  'crypto',
  'hls',
  'applehttp',
  'rtmp',
  'rtmps',
  'subfile',
  'async',
  'cache',
  'concat',
  'pipe',
  'smb',
  'nfs',
];

Player createNativePlayer() => Player(
      configuration: const PlayerConfiguration(
        // FFmpeg 将系统 HTTP(S)_PROXY 映射为 httpproxy 协议。media_kit 默认
        // 白名单不含该协议，会导致所有经代理的 HLS 在 Windows 上启动失败。
        protocolWhitelist: nativePlaybackProtocolWhitelist,
      ),
    );
