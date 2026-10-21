import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/spider_playback_response.dart';

const _episode = PlaybackEpisode(
  name: 'Episode 3',
  url: 'https://video.test/watch/3.html',
  sortIndex: 3,
  duration: Duration(minutes: 12),
  headers: {'User-Agent': 'Source UA', 'Referer': 'https://video.test/'},
);

void main() {
  test('direct media does not contact configured parsers', () async {
    final requests = <RequestOptions>[];
    final result = await resolveSpiderPlayback(
      site: _site(),
      episode: _episode,
      response: {'parse': 0, 'url': 'https://cdn.test/stream.m3u8'},
      dio: _dio(requests, {}),
    );
    expect(result.url, 'https://cdn.test/stream.m3u8');
    expect(result.requiresWebView, isFalse);
    expect(requests, isEmpty);
  });

  test('jx uses the first supported configured parser matching the flag',
      () async {
    final requests = <RequestOptions>[];
    final result = await resolveSpiderPlayback(
      site: _site(parses: [
        {'name': 'Native extension', 'type': 3, 'url': 'native'},
        {
          'name': 'Other platform',
          'type': 0,
          'url': 'https://other.test/?url=',
          'ext': {
            'flag': ['other']
          },
        },
        {
          'name': 'Configured web',
          'type': 0,
          'url': 'https://parser.test/?url=',
          'ext': {
            'flag': ['qq'],
            'header': {'referer': 'https://parser.test/'},
          },
        },
      ]),
      episode: _episode,
      response: {'jx': 1, 'flag': 'qq', 'url': _episode.url},
      dio: _dio(requests, {}),
    );
    expect(result.url, 'https://parser.test/?url=${_episode.url}');
    expect(result.requiresWebView, isTrue);
    expect(result.headers, _episode.headers);
    expect(result.webHeaders, {'referer': 'https://parser.test/'});
    expect(requests, isEmpty);
  });

  test('warehouse flags trigger parsing even when the Spider says parse zero',
      () async {
    final result = await resolveSpiderPlayback(
      site: _site(flags: ['qq']),
      episode: _episode,
      response: {'parse': 0, 'flag': 'qq', 'url': _episode.url},
      dio: _dio([], {}),
    );
    expect(result.url, 'https://default.test/?url=${_episode.url}');
    expect(result.requiresWebView, isTrue);
  });

  for (final parse in [0, 1]) {
    test('flags without configured parsers preserve parse=$parse', () async {
      final requests = <RequestOptions>[];
      final result = await resolveSpiderPlayback(
        site: _site(parses: [], flags: ['qq']),
        episode: _episode,
        response: {
          'parse': parse,
          'flag': 'qq',
          'url': 'https://cdn.test/stream.m3u8',
        },
        dio: _dio(requests, {}),
      );
      expect(result.url, 'https://cdn.test/stream.m3u8');
      expect(result.requiresWebView, parse == 1);
      expect(requests, isEmpty);
    });
  }

  test('a named parser is selected exactly within the current site', () async {
    final requests = <RequestOptions>[];
    final result = await resolveSpiderPlayback(
      site: _site(parses: [
        {'name': 'Not selected', 'type': 0, 'url': 'https://wrong.test/?url='},
        {'name': 'Chosen', 'type': '1', 'url': 'https://json.test/?url='},
      ]),
      episode: _episode,
      response: {'playUrl': 'parse:Chosen', 'url': _episode.url},
      dio: _dio(requests, {'url': 'https://cdn.test/movie.mp4'}),
    );
    expect(requests.single.uri.toString(),
        'https://json.test/?url=${_episode.url}');
    expect(result.url, 'https://cdn.test/movie.mp4');
    expect(result.requiresWebView, isFalse);
  });

  test('json prefix supports nested data and response header aliases',
      () async {
    final requests = <RequestOptions>[];
    final result = await resolveSpiderPlayback(
      site: _site(),
      episode: _episode,
      response: {
        'playUrl': 'json:https://json.test/?url=',
        'url': _episode.url,
        'header': {'Origin': 'https://video.test'},
      },
      dio: _dio(
          requests,
          '{"data":{"url":"https://cdn.test/signed-stream","header":{"Cookie":"media-cookie"}},'
          '"ua":"Media UA","referer":"https://media.test/"}'),
    );
    expect(requests.single.headers['Origin'], isNull);
    expect(result.url, 'https://cdn.test/signed-stream');
    expect(result.requiresWebView, isFalse);
    expect(result.name, _episode.name);
    expect(result.sortIndex, 3);
    expect(result.duration, _episode.duration);
    expect(result.headers, {
      'Origin': 'https://video.test',
      'Cookie': 'media-cookie',
      'User-Agent': 'Media UA',
      'referer': 'https://media.test/',
    });
  });

  test('configured JSON request headers remain separate from media headers',
      () async {
    final requests = <RequestOptions>[];
    final result = await resolveSpiderPlayback(
      site: _site(parses: [
        {
          'name': 'JSON',
          'type': 1,
          'url': 'https://json.test/?url=',
          'ext': {
            'header': {'user-agent': 'Parser UA', 'X-Parser': 'configured'},
          },
        },
      ]),
      episode: _episode,
      response: {'jx': 1, 'url': _episode.url},
      dio: _dio(requests, {
        'url': 'https://cdn.test/video.m3u8',
        'header': '{"User-Agent":"Media UA","Cookie":"result-cookie"}',
      }),
    );
    expect(requests.single.headers['user-agent'], 'Parser UA');
    expect(requests.single.headers['X-Parser'], 'configured');
    expect(result.headers?['User-Agent'], 'Media UA');
    expect(
        result.headers?.keys.where((key) => key.toLowerCase() == 'user-agent'),
        hasLength(1));
    expect(result.headers?['Referer'], 'https://video.test/');
    expect(result.headers?['Cookie'], 'result-cookie');
    expect(result.headers?['X-Parser'], isNull);
  });

  test('JSON parsing never forwards credentials between parser and media',
      () async {
    final requests = <RequestOptions>[];
    final result = await resolveSpiderPlayback(
      site: _site(parses: [
        {
          'name': 'JSON',
          'type': 1,
          'url': 'https://json.test/?url=',
          'ext': {
            'header': {
              'Cookie': 'parser-cookie',
              'Authorization': 'Bearer parser-token',
            },
          },
        },
      ]),
      episode: const PlaybackEpisode(
        name: 'Episode',
        url: 'https://video.test/watch.html',
        headers: {
          'Cookie': 'media-cookie',
          'Authorization': 'Bearer media-token',
        },
      ),
      response: {
        'jx': 1,
        'url': _episode.url,
        'header': {'X-Media': 'spider'},
      },
      dio: _dio(requests, {'url': 'https://cdn.test/video.m3u8'}),
    );
    expect(requests.single.headers['Cookie'], 'parser-cookie');
    expect(requests.single.headers['Authorization'], 'Bearer parser-token');
    expect(requests.single.headers['X-Media'], isNull);
    expect(result.headers, {
      'Cookie': 'media-cookie',
      'Authorization': 'Bearer media-token',
      'X-Media': 'spider',
    });
  });

  test('a web parser with no headers explicitly clears navigation inheritance',
      () async {
    final result = await resolveSpiderPlayback(
      site: _site(),
      episode: const PlaybackEpisode(
        name: 'Episode',
        url: 'https://video.test/watch.html',
        headers: {'Cookie': 'media-cookie'},
      ),
      response: {'jx': 1, 'url': _episode.url},
      dio: _dio([], {}),
    );
    expect(result.webHeaders, isEmpty);
    expect(result.headers, {'Cookie': 'media-cookie'});
  });

  test('explicit web prefix wins over a global flag', () async {
    final result = await resolveSpiderPlayback(
      site: _site(flags: ['qq']),
      episode: _episode,
      response: {
        'parse': 1,
        'flag': 'qq',
        'playUrl': 'https://explicit.test/?url=',
        'url': _episode.url,
      },
      dio: _dio([], {}),
    );
    expect(result.url, 'https://explicit.test/?url=${_episode.url}');
  });

  test('JSON HTML output remains a webpage and cannot become native media',
      () async {
    final result = await resolveSpiderPlayback(
      site: _site(),
      episode: _episode,
      response: {
        'playUrl': 'json:https://json.test/?url=',
        'url': _episode.url
      },
      dio: _dio([], {'url': 'https://parser.test/watch.html'}),
    );
    expect(result.requiresWebView, isTrue);
  });

  test('an empty top-level URL falls back to the nested JSON result', () async {
    final result = await resolveSpiderPlayback(
      site: _site(),
      episode: _episode,
      response: {
        'playUrl': 'json:https://json.test/?url=',
        'url': _episode.url
      },
      dio: _dio([], {
        'url': '',
        'data': {'url': 'https://cdn.test/video.mp4'},
      }),
    );
    expect(result.url, 'https://cdn.test/video.mp4');
  });

  for (final payload in <Object>[
    '<html>upstream unavailable</html>',
    {},
    {'url': ''},
    {'url': 'javascript:alert(1)'}
  ]) {
    test(
        'JSON response fails explicitly for ${payload.runtimeType} invalid output $payload',
        () async {
      await expectLater(
        resolveSpiderPlayback(
          site: _site(),
          episode: _episode,
          response: {
            'playUrl': 'json:https://json.test/?url=',
            'url': _episode.url
          },
          dio: _dio([], payload),
        ),
        throwsFormatException,
      );
    });
  }

  test('named native parser and absent parser fail without making a request',
      () async {
    for (final response in [
      {'playUrl': 'parse:Native', 'url': _episode.url},
      {'playUrl': 'parse:Missing', 'url': _episode.url},
      {'jx': 1, 'url': _episode.url},
    ]) {
      final requests = <RequestOptions>[];
      await expectLater(
        resolveSpiderPlayback(
          site: _site(parses: [
            {'name': 'Native', 'type': 3, 'url': 'native'}
          ]),
          episode: _episode,
          response: response,
          dio: _dio(requests, {}),
        ),
        throwsUnsupportedError,
      );
      expect(requests, isEmpty);
    }
  });

  test('network errors and explicit cancellation propagate without retry',
      () async {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.cancel
    ]) {
      final requests = <RequestOptions>[];
      final expected =
          DioException(requestOptions: RequestOptions(), type: type);
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
          requests.add(request);
          handler.reject(expected);
        }));
      await expectLater(
          resolveSpiderPlayback(
            site: _site(),
            episode: _episode,
            response: {
              'playUrl': 'json:https://json.test/?url=',
              'url': _episode.url
            },
            dio: dio,
          ),
          throwsA(same(expected)));
      expect(requests, hasLength(1));
    }
  });
}

TvBoxSite _site(
        {List<Map<String, dynamic>>? parses, List<String> flags = const []}) =>
    TvBoxSite(
      key: 'source',
      name: 'Source',
      type: 4,
      api: 'https://spider.test/api',
      flags: flags,
      parses: parses ??
          [
            {'name': 'Default', 'type': 0, 'url': 'https://default.test/?url='}
          ],
    );

Dio _dio(List<RequestOptions> requests, Object payload) => Dio()
  ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    requests.add(request);
    handler.resolve(Response<Object>(
        requestOptions: request, statusCode: 200, data: payload));
  }));
