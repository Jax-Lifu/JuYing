import 'package:test/test.dart';
import 'package:juying_net/juying_net.dart';

void main() {
  group('Network Layer Policy Tests (Section 3.2 & Section 5.2)', () {
    test(
        'NetworkPolicy creates Dio client with default User-Agent and timeouts',
        () {
      const policy = NetworkPolicy();
      final dio = policy.createClient();

      expect(dio.options.connectTimeout, equals(const Duration(seconds: 6)));
      expect(dio.options.receiveTimeout, equals(const Duration(seconds: 10)));
      expect(dio.options.headers['User-Agent'], contains('JuYing'));
    });
  });
}
