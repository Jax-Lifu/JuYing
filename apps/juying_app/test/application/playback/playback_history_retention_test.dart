import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/playback/playback_history_retention.dart';
import 'package:juying/domain/models/playback_history.dart';

void main() {
  test('观看历史保留 60 天内的条目', () {
    final now = DateTime.utc(2026, 8, 20);
    final entries = [
      _entry('current', now.subtract(const Duration(days: 60))),
      _entry('expired', now.subtract(const Duration(days: 61))),
    ];

    final retained = PlaybackHistoryRetention.apply(entries, now: now);

    expect(retained.map((entry) => entry.title), ['current']);
  });
}

PlaybackHistoryEntry _entry(String id, DateTime updatedAt) =>
    PlaybackHistoryEntry(
      profileId: 'profile',
      sourceId: 'source',
      sourceEpisodeId: id,
      title: id,
      officialPageUri: Uri.parse('https://official.example/$id'),
      updatedAt: updatedAt,
    );
