import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/external_config_candidate.dart';

/// 对已打包候选地址做有界、无重定向、无执行的静态探测。
class ExternalConfigProbeService {
  ExternalConfigProbeService({required http.Client client}) : _client = client;

  static const maxProbeBytes = 64 * 1024;
  final http.Client _client;

  Future<ExternalConfigProbeResult> probe(
    ExternalConfigCandidate candidate,
  ) async {
    final baseRisks = <ExternalConfigRisk>{
      ExternalConfigRisk.unknownAuthorization,
      if (candidate.uri.scheme != 'https') ExternalConfigRisk.insecureTransport,
    };
    final request = http.Request('GET', candidate.uri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['Range'] = 'bytes=0-${maxProbeBytes - 1}'
      ..headers['Accept'] =
          'application/json, text/plain, application/octet-stream;q=0.5';
    try {
      final response =
          await _client.send(request).timeout(const Duration(seconds: 8));
      final statusCode = response.statusCode;
      final contentType = response.headers['content-type'];
      if (statusCode >= 300 && statusCode < 400) {
        await response.stream.listen((_) {}).cancel();
        return ExternalConfigProbeResult(
          status: ExternalConfigProbeStatus.redirected,
          checkedAt: DateTime.now(),
          httpStatus: statusCode,
          contentType: contentType,
          risks: baseRisks,
        );
      }
      if (statusCode < 200 || statusCode >= 300) {
        await response.stream.listen((_) {}).cancel();
        return ExternalConfigProbeResult(
          status: ExternalConfigProbeStatus.httpError,
          checkedAt: DateTime.now(),
          httpStatus: statusCode,
          contentType: contentType,
          risks: baseRisks,
        );
      }
      final iterator = StreamIterator<List<int>>(response.stream);
      final bytes = <int>[];
      while (bytes.length < maxProbeBytes && await iterator.moveNext()) {
        final remaining = maxProbeBytes - bytes.length;
        bytes.addAll(iterator.current.take(remaining));
      }
      await iterator.cancel();
      final sample = utf8.decode(bytes, allowMalformed: true).toLowerCase();
      final risks = {...baseRisks, ..._inspect(sample)};
      final looksLikeConfig = sample.contains('"sites"') ||
          sample.contains('"urls"') ||
          sample.contains('#extm3u') ||
          sample.contains('"lives"');
      return ExternalConfigProbeResult(
        status: looksLikeConfig
            ? ExternalConfigProbeStatus.reachable
            : ExternalConfigProbeStatus.invalidResponse,
        checkedAt: DateTime.now(),
        httpStatus: statusCode,
        contentType: contentType,
        risks: risks,
      );
    } catch (_) {
      return ExternalConfigProbeResult(
        status: ExternalConfigProbeStatus.unreachable,
        checkedAt: DateTime.now(),
        risks: baseRisks,
      );
    }
  }

  Set<ExternalConfigRisk> _inspect(String sample) => {
        if (RegExp(r'\.jar|\.js|\.py|"spider"|"api"\s*:\s*"csp_')
            .hasMatch(sample))
          ExternalConfigRisk.executableExtension,
        if (sample.contains('"parses"') ||
            sample.contains('"parse"') ||
            sample.contains('webview') ||
            sample.contains('嗅探'))
          ExternalConfigRisk.thirdPartyParser,
        if (sample.contains('token') ||
            sample.contains('cookie') ||
            sample.contains('authorization'))
          ExternalConfigRisk.embeddedCredentialMarker,
        if (sample.contains('"urls"') ||
            sample.contains('"stores"') ||
            sample.contains('"ext"'))
          ExternalConfigRisk.nestedRemoteConfig,
      };
}
