import 'package:test/test.dart';
import 'package:juying_discovery/juying_discovery.dart';

void main() {
  group('Service Discovery Model Tests (Section 5.7 & CAST-01)', () {
    test('DiscoveredEndpoint model preserves service location and port', () {
      const endpoint = DiscoveredEndpoint(
        serviceType: 'urn:schemas-upnp-org:device:MediaRenderer:1',
        location: 'http://192.168.1.50:8080/description.xml',
        host: '192.168.1.50',
        port: 8080,
      );

      expect(endpoint.host, equals('192.168.1.50'));
      expect(endpoint.port, equals(8080));
      expect(endpoint.location, contains('description.xml'));
      expect(endpoint.serviceType, contains('MediaRenderer'));
    });
  });
}
