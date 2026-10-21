import 'package:test/test.dart';
import 'package:juying_cast_sender/juying_cast_sender.dart';

void main() {
  group('DLNA Media Controller Model Tests (Section 5.7 & CAST-02)', () {
    test('CastTransportState reflects standard UPnP transport states', () {
      expect(CastTransportState.playing, isNotNull);
      expect(CastTransportState.paused, isNotNull);
      expect(CastTransportState.stopped, isNotNull);
      expect(CastTransportState.transitioning, isNotNull);
      expect(CastTransportState.noMediaPresent, isNotNull);
    });
  });
}
