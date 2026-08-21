import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/playback/playback_episode_queue.dart';
import 'package:juying/domain/models/unified_media.dart';

void main() {
  final episodes = [
    _episode('one'),
    _episode('two'),
    _episode('three'),
  ];

  test('相邻选集按统一集身份切换', () {
    expect(
      PlaybackEpisodeQueue.previous(episodes, activeEpisodeId: 'source:two')
          ?.id,
      'source:one',
    );
    expect(
      PlaybackEpisodeQueue.next(episodes, activeEpisodeId: 'source:two')?.id,
      'source:three',
    );
  });

  test('边界和未知选集不产生跨来源切换', () {
    expect(
      PlaybackEpisodeQueue.previous(episodes, activeEpisodeId: 'source:one'),
      isNull,
    );
    expect(
      PlaybackEpisodeQueue.next(episodes, activeEpisodeId: 'source:three'),
      isNull,
    );
    expect(
      PlaybackEpisodeQueue.next(episodes, activeEpisodeId: 'other:two'),
      isNull,
    );
  });
}

MediaEpisode _episode(String id) => MediaEpisode(
      sourceId: 'source',
      sourceEpisodeId: id,
      title: id,
      officialPageUri: Uri.parse('https://official.example/$id'),
    );
