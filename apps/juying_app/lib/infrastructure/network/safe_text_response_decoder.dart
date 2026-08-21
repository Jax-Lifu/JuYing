import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract final class SafeTextResponseDecoder {
  static Future<String> decode(
    List<int> bytes, {
    required int maxDecodedBytes,
    String? contentEncoding,
  }) async {
    // package:http 在桌面端可能已经自动解压 body，但仍保留 gzip 响应头。
    // 只相信负载魔数，避免对已解压内容再次执行 gzip.decoder。
    final shouldDecodeGzip = _hasGzipHeader(bytes);
    final stream = shouldDecodeGzip
        ? gzip.decoder.bind(Stream<List<int>>.value(bytes))
        : Stream<List<int>>.value(bytes);
    final chunks = <List<int>>[];
    var decodedBytes = 0;
    await for (final chunk in stream) {
      decodedBytes += chunk.length;
      if (decodedBytes > maxDecodedBytes) {
        throw const FormatException('响应解码后超过安全上限');
      }
      chunks.add(chunk);
    }
    return utf8.decode(
      chunks.expand((chunk) => chunk).toList(growable: false),
      allowMalformed: true,
    );
  }

  static bool _hasGzipHeader(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
}
