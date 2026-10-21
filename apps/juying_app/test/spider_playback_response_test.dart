import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/services/spider_playback_response.dart';

void main() {
  const episode = PlaybackEpisode(
    name: 'Episode 2',
    url: 'https://site.test/watch/2.html',
    sortIndex: 2,
    headers: <String, String>{'User-Agent': 'Spider'},
  );

  test('direct player response preserves metadata and merges JSON headers', () {
    final playback = parseSpiderPlaybackResponse(
      episode: episode,
      response: <String, dynamic>{
        'parse': '0',
        'url': 'https://cdn.test/tokenized-stream',
        'header': '{"Cookie":"session=value","Referer":"https://site.test/"}',
      },
    );

    expect(playback.name, episode.name);
    expect(playback.sortIndex, 2);
    expect(playback.requiresWebView, isFalse);
    expect(playback.headers, <String, String>{
      'User-Agent': 'Spider',
      'Cookie': 'session=value',
      'Referer': 'https://site.test/',
    });
  });

  test('parse=1 plus playUrl routes the composed page to WebView', () {
    final playback = parseSpiderPlaybackResponse(
      episode: episode,
      response: <String, dynamic>{
        'parse': 1,
        'url': 'https://site.test/watch/2',
        'playUrl': 'https://parser.test/?url=',
        'header': <String, String>{'Referer': 'https://parser.test/'},
      },
    );

    expect(playback.url, 'https://parser.test/?url=https://site.test/watch/2');
    expect(playback.requiresWebView, isTrue);
    expect(playback.headers?['Referer'], 'https://parser.test/');
  });

  test('unmarked HTTP page and explicit HTML cannot become native media', () {
    for (final response in <Map<String, dynamic>>[
      <String, dynamic>{'url': 'https://site.test/watch/2'},
      <String, dynamic>{'parse': 0, 'url': episode.url},
    ]) {
      expect(
        parseSpiderPlaybackResponse(episode: episode, response: response)
            .requiresWebView,
        isTrue,
      );
    }
  });

  test('an empty player result cannot fall back to the HTTP episode page', () {
    expect(
      () => parseSpiderPlaybackResponse(
        episode: episode,
        response: <String, dynamic>{},
      ),
      throwsFormatException,
    );
    final direct = parseSpiderPlaybackResponse(
      episode: const PlaybackEpisode(
        name: 'Direct media',
        url: 'https://cdn.test/media.m3u8?token=value',
      ),
      response: <String, dynamic>{},
    );
    expect(direct.url, contains('media.m3u8'));
    expect(direct.requiresWebView, isFalse);
  });

  test('unsupported parser modes fail before producing a playback URL', () {
    for (final mode in <Map<String, dynamic>>[
      <String, dynamic>{'jx': 1},
      <String, dynamic>{'playUrl': 'json:https://parser.test/?url='},
      <String, dynamic>{'playUrl': 'parse:external'},
    ]) {
      expect(
        () => parseSpiderPlaybackResponse(
          episode: episode,
          response: <String, dynamic>{'url': episode.url, ...mode},
        ),
        throwsUnsupportedError,
      );
    }
  });
}
