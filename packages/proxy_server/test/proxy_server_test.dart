import 'package:test/test.dart';
import 'package:juying_proxy_server/juying_proxy_server.dart';

void main() {
  group('Local Proxy Server Token Lifecycle Tests (ADR-006 & Section 5.4)', () {
    test('StreamRegistration preserves headers and verifies TTL validity', () {
      final activeReg = StreamRegistration(
        token: 'token-12345',
        upstreamUrl: 'http://upstream.example.com/stream.m3u8',
        headers: {'User-Agent': 'JuYing-Player', 'Referer': 'http://cctv.com'},
        createdAt: DateTime.now(),
        ttl: const Duration(minutes: 30),
      );

      expect(activeReg.token, equals('token-12345'));
      expect(activeReg.upstreamUrl, contains('upstream.example.com'));
      expect(activeReg.headers['User-Agent'], equals('JuYing-Player'));
      expect(activeReg.isExpired, isFalse);

      final expiredReg = StreamRegistration(
        token: 'token-expired',
        upstreamUrl: 'http://upstream.example.com/expired.m3u8',
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        ttl: const Duration(hours: 4),
      );

      expect(expiredReg.isExpired, isTrue);
    });
  });
}
