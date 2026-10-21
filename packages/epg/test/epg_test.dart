import 'package:test/test.dart';
import 'package:juying_epg/juying_epg.dart';

void main() {
  group('EPG Channel Name Normalization Tests (Section 5.6 & LIVE-06)', () {
    test('ChannelNameNormalizer normalizes variations of CCTV-1 and CCTV-2',
        () {
      expect(ChannelNameNormalizer.normalize('CCTV-1 综合 高清'), equals('CCTV1'));
      expect(ChannelNameNormalizer.normalize('央视一套 (HD)'), equals('CCTV1'));
      expect(ChannelNameNormalizer.normalize('cctv1'), equals('CCTV1'));
      expect(ChannelNameNormalizer.normalize('央视二套 4K'), equals('CCTV2'));
      expect(ChannelNameNormalizer.normalize('CCTV-2 财经'), equals('CCTV2财经'));
    });
  });
}
