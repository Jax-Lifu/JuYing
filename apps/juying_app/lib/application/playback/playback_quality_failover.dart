import '../../domain/models/playable_media.dart';

/// 返回尚未尝试的下一条播放线路；所有来源共享同一故障转移规则。
PlaybackQuality? nextPlaybackQuality({
  required List<PlaybackQuality> qualities,
  required String? activeQualityId,
  required Set<String> attemptedQualityIds,
}) {
  if (qualities.isEmpty) return null;
  final activeIndex = qualities.indexWhere(
    (quality) => quality.id == activeQualityId,
  );
  for (var offset = 1; offset <= qualities.length; offset++) {
    final index = (activeIndex + offset) % qualities.length;
    final candidate = qualities[index];
    if (!attemptedQualityIds.contains(candidate.id)) return candidate;
  }
  return null;
}
