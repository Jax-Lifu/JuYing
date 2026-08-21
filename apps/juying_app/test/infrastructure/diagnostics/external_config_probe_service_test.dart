import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/domain/models/external_config_candidate.dart';
import 'package:juying/infrastructure/diagnostics/external_config_probe_service.dart';
import 'package:juying/infrastructure/diagnostics/external_config_candidate_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('打包候选清单只进入隔离检测且包含用户给出的 15 个入口', () async {
    final candidates = await ExternalConfigCandidateLoader.loadBundled();

    expect(candidates, hasLength(15));
    expect(candidates.map((item) => item.id).toSet(), hasLength(15));
    expect(candidates.map((item) => item.name), contains('小盒子'));
    expect(candidates.every((item) => item.uri.userInfo.isEmpty), isTrue);
  });

  test('配置探测不跟随重定向且永远不能直接进入播放', () async {
    final service = ExternalConfigProbeService(
      client: MockClient.streaming((request, _) async {
        expect(request.followRedirects, isFalse);
        expect(request.headers['range'], 'bytes=0-65535');
        return http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {'location': 'https://other.example/config.json'},
        );
      }),
    );

    final result = await service.probe(_candidate('https'));

    expect(result.status, ExternalConfigProbeStatus.redirected);
    expect(result.allowedForPlayback, isFalse);
  });

  test('有界静态扫描识别远程扩展、解析器和授权未知风险', () async {
    final service = ExternalConfigProbeService(
      client: MockClient((_) async => http.Response(
            '{"spider":"https://x.example/a.jar","sites":[],"parses":[],"ext":"https://x.example/rule.js"}',
            200,
            headers: {'content-type': 'application/json'},
          )),
    );

    final result = await service.probe(_candidate('http'));

    expect(result.status, ExternalConfigProbeStatus.reachable);
    expect(result.risks, contains(ExternalConfigRisk.insecureTransport));
    expect(result.risks, contains(ExternalConfigRisk.executableExtension));
    expect(result.risks, contains(ExternalConfigRisk.thirdPartyParser));
    expect(result.risks, contains(ExternalConfigRisk.nestedRemoteConfig));
    expect(result.risks, contains(ExternalConfigRisk.unknownAuthorization));
  });

  test('普通网页响应不会被误判为可导入配置', () async {
    final service = ExternalConfigProbeService(
      client: MockClient((_) async => http.Response(
            '<html><title>toolbox</title></html>',
            200,
            headers: {'content-type': 'text/html'},
          )),
    );

    final result = await service.probe(_candidate('https'));

    expect(result.status, ExternalConfigProbeStatus.invalidResponse);
    expect(result.allowedForPlayback, isFalse);
  });
}

ExternalConfigCandidate _candidate(String scheme) => ExternalConfigCandidate(
      id: 'candidate-test',
      name: '测试',
      uri: Uri.parse('$scheme://config.example/source.json'),
      referenceUri: null,
    );
