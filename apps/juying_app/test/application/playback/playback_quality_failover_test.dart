import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/playback/playback_quality_failover.dart';
import 'package:juying/domain/models/playable_media.dart';

void main() {
  final qualities = [
    PlaybackQuality(
      id: 'line-1',
      label: '主线',
      streamUri: Uri.parse('https://one.example/live.m3u8'),
    ),
    PlaybackQuality(
      id: 'line-2',
      label: '备用',
      streamUri: Uri.parse('https://two.example/live.m3u8'),
    ),
    PlaybackQuality(
      id: 'line-3',
      label: '备用二',
      streamUri: Uri.parse('https://three.example/live.m3u8'),
    ),
  ];

  test('首线路失败后选择尚未尝试的下一条线路', () {
    final next = nextPlaybackQuality(
      qualities: qualities,
      activeQualityId: 'line-1',
      attemptedQualityIds: {'line-1'},
    );

    expect(next?.id, 'line-2');
  });

  test('跳过已失败线路并在所有线路尝试后停止', () {
    expect(
      nextPlaybackQuality(
        qualities: qualities,
        activeQualityId: 'line-2',
        attemptedQualityIds: {'line-1', 'line-2'},
      )?.id,
      'line-3',
    );
    expect(
      nextPlaybackQuality(
        qualities: qualities,
        activeQualityId: 'line-3',
        attemptedQualityIds: {'line-1', 'line-2', 'line-3'},
      ),
      isNull,
    );
  });
}
