import 'package:flutter/widgets.dart';

import '../../domain/models/media_source.dart';
import '../../domain/models/unified_media.dart';

/// 由平台层实现的播放器路由入口；通用页面不认识原生播放器或 WebView 插件。
abstract interface class PlaybackLauncher {
  Future<void> launchNative(
      BuildContext context, PlaybackLaunchRequest request);
  Future<void> launchOfficial(
      BuildContext context, PlaybackLaunchRequest request);
}

/// 已通过来源适配器和策略校验的播放会话输入。
class PlaybackLaunchRequest {
  const PlaybackLaunchRequest({
    required this.playback,
    required this.episodes,
    required this.resolveEpisode,
    required this.profileId,
    required this.sourceCapabilities,
    this.childDailyLimitMinutes,
  });

  final PlaybackDescriptor playback;
  final List<MediaEpisode> episodes;
  final Future<PlaybackDescriptor> Function(MediaEpisode episode)
      resolveEpisode;
  final String profileId;
  final Set<SourceCapability> sourceCapabilities;
  final int? childDailyLimitMinutes;
}
