import '../../domain/models/playback_history.dart';

abstract final class PlaybackHistoryRetention {
  static const retention = Duration(days: 60);

  static List<PlaybackHistoryEntry> apply(
    Iterable<PlaybackHistoryEntry> entries, {
    required DateTime now,
  }) {
    final cutoff = now.subtract(retention);
    return entries
        .where((entry) => !entry.updatedAt.isBefore(cutoff))
        .toList(growable: false);
  }
}
