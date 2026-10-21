import 'package:flutter_test/flutter_test.dart';
import 'package:juying/features/metadata/services/media_metadata_service.dart';

void main() {
  group('MediaMetadataService Tests', () {
    test('cleans dirty movie and series titles properly', () {
      expect(
        MediaMetadataService.cleanMediaTitle(
            '【4K.60FPS.杜比视界】庆余年 第二季 S02E01 [国语中字]'),
        '庆余年 第二季',
      );

      expect(
        MediaMetadataService.cleanMediaTitle(
            '繁花.2023.1080p.WEB-DL.H265.AAC-HD'),
        '繁花.2023',
      );

      expect(
        MediaMetadataService.cleanMediaTitle('三体 第01集 [未删减版]'),
        '三体',
      );

      expect(
        MediaMetadataService.cleanMediaTitle('【招募字幕组】火影忍者 全720话 [HEVC]'),
        '火影忍者',
      );
    });
  });
}
