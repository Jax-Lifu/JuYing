import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/infrastructure/tvbox/tvbox_config_parser.dart';
import 'package:juying/infrastructure/tvbox/tvbox_playback_resolver.dart';

void main() {
  test('type=1 JSON 解析器返回原生媒体地址和受限请求头', () async {
    final resolver = TvboxPlaybackResolver(
      client: MockClient((request) async => http.Response.bytes(
            utf8.encode(
              '{"url":"https://media.example/video.m3u8","header":{"Referer":"https://media.example/","Cookie":"secret"}}',
            ),
            200,
          )),
      parsers: const [
        TvboxPlaybackParser(
          name: 'JSON',
          type: 1,
          urlPrefix: 'https://parse.example/?url=',
          flags: {'qq'},
        ),
      ],
    );

    final result = await resolver.resolve(
      Uri.parse('https://page.example/watch/1'),
      flag: 'qq',
      forceParse: true,
    );

    expect(result.streamUri, Uri.parse('https://media.example/video.m3u8'));
    expect(result.httpHeaders, {'Referer': 'https://media.example/'});
  });

  test('type=1 JSON 解析器兼容 data.url 与 headers 嵌套结构', () async {
    final resolver = TvboxPlaybackResolver(
      client: MockClient((request) async => http.Response.bytes(
            utf8.encode(
              '{"code":200,"data":{"url":"https://media.example/stream.mp4","headers":{"User-Agent":"CustomUA"}}}',
            ),
            200,
          )),
      parsers: const [
        TvboxPlaybackParser(
          name: 'JSON2',
          type: 1,
          urlPrefix: 'https://parse2.example/?url=',
        ),
      ],
    );

    final result = await resolver.resolve(
      Uri.parse('https://page.example/video/2'),
      forceParse: true,
    );

    expect(result.streamUri, Uri.parse('https://media.example/stream.mp4'));
    expect(result.httpHeaders, {'User-Agent': 'CustomUA'});
  });

  test('type=0 解析器生成隔离网页播放地址，不冒充原生流', () async {
    final resolver = TvboxPlaybackResolver(
      client: MockClient((_) async => http.Response('', 500)),
      parsers: const [
        TvboxPlaybackParser(
          name: 'Web',
          type: 0,
          urlPrefix: 'https://parse.example/player?url=',
        ),
      ],
    );

    final result = await resolver.resolve(
      Uri.parse('https://page.example/watch?id=1'),
      forceParse: true,
    );

    expect(result.streamUri, isNull);
    expect(result.pageUri.host, 'parse.example');
    expect(result.pageUri.toString(), contains('https%3A%2F%2Fpage.example'));
  });
}
