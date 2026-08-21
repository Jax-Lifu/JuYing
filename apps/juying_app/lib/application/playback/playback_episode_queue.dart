import '../../domain/models/unified_media.dart';

abstract final class PlaybackEpisodeQueue {
  static MediaEpisode? previous(
    List<MediaEpisode> episodes, {
    required String activeEpisodeId,
  }) =>
      _adjacent(episodes, activeEpisodeId: activeEpisodeId, offset: -1);

  static MediaEpisode? next(
    List<MediaEpisode> episodes, {
    required String activeEpisodeId,
  }) =>
      _adjacent(episodes, activeEpisodeId: activeEpisodeId, offset: 1);

  static MediaEpisode? _adjacent(
    List<MediaEpisode> episodes, {
    required String activeEpisodeId,
    required int offset,
  }) {
    final index =
        episodes.indexWhere((episode) => episode.id == activeEpisodeId);
    final adjacentIndex = index + offset;
    if (index < 0 || adjacentIndex < 0 || adjacentIndex >= episodes.length) {
      return null;
    }
    return episodes[adjacentIndex];
  }
}
