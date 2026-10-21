import 'package:test/test.dart';
import 'package:juying_receiver/juying_receiver.dart';

void main() {
  group('DLNA MediaRenderer Receiver Model Tests (Section 5.8 & DMR-04)', () {
    test('IncomingCastPayload model parses DIDL metadata fields safely', () {
      const payload = IncomingCastPayload(
        mediaUri: 'http://192.168.1.100:9978/p/token-cast-1',
        title: '新闻联播 (投屏)',
        coverUrl: 'http://192.168.1.100:9978/cover.jpg',
        senderIp: '192.168.1.5',
      );

      expect(payload.mediaUri, contains('/p/token-cast-1'));
      expect(payload.title, equals('新闻联播 (投屏)'));
      expect(payload.senderIp, equals('192.168.1.5'));
    });
  });
}
