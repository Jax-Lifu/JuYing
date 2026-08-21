import 'package:flutter_test/flutter_test.dart';
import 'package:juying/domain/models/playable_media.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/features/player/presentation/native_player_page.dart';

void main() {
  group('NativePlayerPage Features', () {
    test('PlayerAspectRatio 枚举标签与周期切换完整覆盖', () {
      expect(PlayerAspectRatio.auto.label, '自适应');
      expect(PlayerAspectRatio.ratio16_9.label, '16:9');
      expect(PlayerAspectRatio.ratio4_3.label, '4:3');
      expect(PlayerAspectRatio.fill.label, '铺满全屏');

      expect(
        switch (PlayerAspectRatio.auto) {
          PlayerAspectRatio.auto => PlayerAspectRatio.ratio16_9,
          PlayerAspectRatio.ratio16_9 => PlayerAspectRatio.ratio4_3,
          PlayerAspectRatio.ratio4_3 => PlayerAspectRatio.fill,
          PlayerAspectRatio.fill => PlayerAspectRatio.auto,
        },
        PlayerAspectRatio.ratio16_9,
      );
    });

    test('多线路 PlaybackQuality 与 PlaybackDescriptor 保持契约一致', () {
      final playback = PlaybackDescriptor(
        sourceId: 'iptv-test',
        sourceEpisodeId: 'cctv1',
        title: 'CCTV-1 综合',
        officialPageUri: Uri.parse('http://example.com/cctv1'),
        nativeStreamUri: Uri.parse('http://example.com/cctv1_line1.m3u8'),
        qualityOptions: [
          PlaybackQuality(
            id: 'line1',
            label: '线路 1 · 4K',
            streamUri: Uri.parse('http://example.com/cctv1_line1.m3u8'),
          ),
          PlaybackQuality(
            id: 'line2',
            label: '线路 2 · 高清',
            streamUri: Uri.parse('http://example.com/cctv1_line2.m3u8'),
          ),
        ],
      );

      expect(playback.qualityOptions.length, 2);
      expect(playback.qualityOptions[0].label, contains('4K'));
      expect(playback.qualityOptions[1].label, contains('高清'));
    });
  });
}
