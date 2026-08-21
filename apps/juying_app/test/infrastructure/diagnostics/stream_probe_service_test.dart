import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/infrastructure/diagnostics/stream_probe_service.dart';

void main() {
  group('StreamProbeService', () {
    test('正确探测可达的 HLS 直播流并返回格式信息', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('.m3u8')) {
          return http.Response(
            '#EXTM3U\n#EXT-X-VERSION:3\n',
            200,
            headers: {'content-type': 'application/vnd.apple.mpegurl'},
          );
        }
        return http.Response('Not found', 404);
      });

      final service = StreamProbeService(client: client);
      final result = await service.probe(
        Uri.parse('https://example.com/live/cctv1.m3u8'),
      );

      expect(result.isAvailable, isTrue);
      expect(result.httpStatus, 200);
      expect(result.isHls, isTrue);
      expect(result.isMp4, isFalse);
      expect(result.latencyMs, greaterThanOrEqualTo(0));
    });

    test('对不可达流返回失败状态和错误信息', () async {
      final client = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final service = StreamProbeService(client: client);
      final result = await service.probe(
        Uri.parse('https://example.com/broken/stream.m3u8'),
      );

      expect(result.isAvailable, isFalse);
      expect(result.httpStatus, 500);
    });

    test('批量探测时按可用性和延迟升序排序', () async {
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.contains('fast')) {
          return http.Response('OK', 200,
              headers: {'content-type': 'application/vnd.apple.mpegurl'});
        } else if (path.contains('slow')) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response('OK', 200,
              headers: {'content-type': 'application/vnd.apple.mpegurl'});
        } else {
          return http.Response('Error', 404);
        }
      });

      final service = StreamProbeService(client: client);
      final uris = [
        Uri.parse('https://example.com/dead.m3u8'),
        Uri.parse('https://example.com/slow.m3u8'),
        Uri.parse('https://example.com/fast.m3u8'),
      ];

      final results = await service.probeAll(uris);
      expect(results.length, 3);
      expect(results[0].targetUri.path, contains('fast'));
      expect(results[1].targetUri.path, contains('slow'));
      expect(results[2].isAvailable, isFalse);
    });
  });
}
