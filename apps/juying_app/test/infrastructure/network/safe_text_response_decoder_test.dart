import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juying/infrastructure/network/safe_text_response_decoder.dart';

void main() {
  test('自动解码带 GZIP 特征的文本响应', () async {
    final content = await SafeTextResponseDecoder.decode(
      gzip.encode(utf8.encode('<tv>节目单</tv>')),
      maxDecodedBytes: 1024,
    );

    expect(content, '<tv>节目单</tv>');
  });

  test('响应头仍为 gzip 但正文已由 HTTP 客户端解压时不会重复解压', () async {
    final decoded = await SafeTextResponseDecoder.decode(
      utf8.encode('{"sites":[]}'),
      maxDecodedBytes: 1024,
      contentEncoding: 'gzip',
    );

    expect(decoded, '{"sites":[]}');
  });

  test('解码后的响应超过上限时拒绝读取', () async {
    final action = SafeTextResponseDecoder.decode(
      gzip.encode(utf8.encode('节目' * 100)),
      maxDecodedBytes: 64,
      contentEncoding: 'gzip',
    );

    await expectLater(action, throwsFormatException);
  });
}
