import 'unified_media.dart';

/// 持久化观看记录仅保存来源内身份和用户可见元数据，绝不保存播放流地址。
class PlaybackHistoryEntry {
  const PlaybackHistoryEntry({
    required this.profileId,
    required this.sourceId,
    required this.sourceEpisodeId,
    required this.title,
    required this.officialPageUri,
    required this.updatedAt,
    this.posterUri,
    this.position = Duration.zero,
    this.duration,
  });

  final String profileId;
  final String sourceId;
  final String sourceEpisodeId;
  final String title;
  final Uri officialPageUri;
  final Uri? posterUri;
  final Duration position;
  final Duration? duration;
  final DateTime updatedAt;

  String get id => '$profileId:$sourceId:$sourceEpisodeId';

  PlaybackHistoryEntry copyWith({
    Duration? position,
    Duration? duration,
    DateTime? updatedAt,
  }) =>
      PlaybackHistoryEntry(
        profileId: profileId,
        sourceId: sourceId,
        sourceEpisodeId: sourceEpisodeId,
        title: title,
        officialPageUri: officialPageUri,
        posterUri: posterUri,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory PlaybackHistoryEntry.fromPlayback({
    required String profileId,
    required PlaybackDescriptor playback,
    Duration position = Duration.zero,
    Duration? duration,
    DateTime? updatedAt,
  }) =>
      PlaybackHistoryEntry(
        profileId: profileId,
        sourceId: playback.sourceId,
        sourceEpisodeId: playback.sourceEpisodeId,
        title: playback.title,
        officialPageUri: playback.officialPageUri,
        posterUri: playback.posterUri,
        position: position,
        duration: duration ?? playback.duration,
        updatedAt: updatedAt ?? DateTime.now(),
      );
}
