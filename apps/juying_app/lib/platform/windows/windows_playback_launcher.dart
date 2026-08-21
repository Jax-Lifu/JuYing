import 'package:flutter/material.dart';

import '../../application/playback/playback_launcher.dart';
import '../../features/player/presentation/native_player_page.dart';
import '../../features/player/presentation/official_web_player_page.dart';

/// Windows 的播放器路由实现。WebView/MediaKit 依赖只在平台组合层出现。
class WindowsPlaybackLauncher implements PlaybackLauncher {
  const WindowsPlaybackLauncher();

  @override
  Future<void> launchNative(
    BuildContext context,
    PlaybackLaunchRequest request,
  ) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NativePlayerPage(
            playback: request.playback,
            episodes: request.episodes,
            resolveEpisode: request.resolveEpisode,
            profileId: request.profileId,
            sourceCapabilities: request.sourceCapabilities,
            childDailyLimitMinutes: request.childDailyLimitMinutes,
          ),
        ),
      );

  @override
  Future<void> launchOfficial(
    BuildContext context,
    PlaybackLaunchRequest request,
  ) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OfficialWebPlayerPage(
            playback: request.playback,
            episodes: request.episodes,
            resolveEpisode: request.resolveEpisode,
            profileId: request.profileId,
            sourceCapabilities: request.sourceCapabilities,
            childDailyLimitMinutes: request.childDailyLimitMinutes,
          ),
        ),
      );
}
