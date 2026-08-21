import 'dart:async';
import 'package:http/http.dart' as http;

class StreamProbeResult {
  const StreamProbeResult({
    required this.targetUri,
    required this.isAvailable,
    required this.latencyMs,
    this.httpStatus,
    this.contentType,
    this.finalUri,
    this.errorMessage,
  });

  final Uri targetUri;
  final bool isAvailable;
  final int latencyMs;
  final int? httpStatus;
  final String? contentType;
  final Uri? finalUri;
  final String? errorMessage;

  bool get isHls =>
      contentType?.contains('mpegurl') == true ||
      targetUri.path.toLowerCase().endsWith('.m3u8') ||
      finalUri?.path.toLowerCase().endsWith('.m3u8') == true;

  bool get isFlv =>
      contentType?.contains('flv') == true ||
      targetUri.path.toLowerCase().endsWith('.flv') ||
      finalUri?.path.toLowerCase().endsWith('.flv') == true;

  bool get isMp4 =>
      contentType?.contains('mp4') == true ||
      targetUri.path.toLowerCase().endsWith('.mp4') ||
      finalUri?.path.toLowerCase().endsWith('.mp4') == true;

  bool get isTs =>
      contentType?.contains('mp2t') == true ||
      targetUri.path.toLowerCase().endsWith('.ts') ||
      finalUri?.path.toLowerCase().endsWith('.ts') == true;
}

/// 探测直播流与点播流的可用性、延迟和媒体格式。
class StreamProbeService {
  StreamProbeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 单流轻量探测：发送带 Range 的 GET 请求以测试连通性、响应延迟与媒体类型。
  Future<StreamProbeResult> probe(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers.addAll({
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Range': 'bytes=0-1024',
          ...headers,
        });

      final streamedResponse = await _client.send(request).timeout(timeout);
      stopwatch.stop();

      final statusCode = streamedResponse.statusCode;
      final contentType = streamedResponse.headers['content-type']?.toLowerCase();
      final finalUrl = streamedResponse.headers['location'];
      final finalUri = finalUrl != null ? Uri.tryParse(finalUrl) : null;

      // 及时取消流读取，避免传输过多媒体数据
      unawaited(streamedResponse.stream.listen((_) {}).cancel());

      final isSuccess = statusCode >= 200 && statusCode < 400;
      return StreamProbeResult(
        targetUri: uri,
        isAvailable: isSuccess,
        latencyMs: stopwatch.elapsedMilliseconds,
        httpStatus: statusCode,
        contentType: contentType,
        finalUri: finalUri,
      );
    } catch (e) {
      stopwatch.stop();
      return StreamProbeResult(
        targetUri: uri,
        isAvailable: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
    }
  }

  /// 批量并发探测多个流，并按延迟和可用性排序（最快且可用的排在前面）。
  Future<List<StreamProbeResult>> probeAll(
    Iterable<Uri> uris, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 4),
    int concurrency = 4,
  }) async {
    final list = uris.toList(growable: false);
    if (list.isEmpty) return const [];

    final results = <StreamProbeResult>[];
    for (var i = 0; i < list.length; i += concurrency) {
      final end = (i + concurrency).clamp(0, list.length);
      final batch = list.sublist(i, end);
      final batchResults = await Future.wait(
        batch.map((u) => probe(u, headers: headers, timeout: timeout)),
      );
      results.addAll(batchResults);
    }

    results.sort((a, b) {
      if (a.isAvailable && !b.isAvailable) return -1;
      if (!a.isAvailable && b.isAvailable) return 1;
      return a.latencyMs.compareTo(b.latencyMs);
    });

    return results;
  }
}
