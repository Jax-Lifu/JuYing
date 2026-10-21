import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/android_dex_spider_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.juying/tvbox_dex');
  const site = TvBoxSite(
    key: 'subscription::xigua',
    name: '西瓜测试源',
    api: 'csp_XBPQ',
    jar: 'https://example.test/spider.jar;md5;abc',
    ext: <String, String>{'host': 'https://example.test'},
  );

  late AndroidDexSpiderAdapter adapter;

  setUp(() {
    adapter = AndroidDexSpiderAdapter(
      channel: channel,
      runtimeOverride: true,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      expect(arguments['siteKey'], site.key);
      expect(arguments['api'], site.api);
      expect(json.decode(arguments['extend'] as String), site.ext);
      switch (arguments['operation']) {
        case 'home':
          return json.encode(<String, dynamic>{
            'class': <Map<String, String>>[
              <String, String>{'type_id': 'movie', 'type_name': '电影'},
            ],
          });
        case 'category':
        case 'search':
          return json.encode(<String, dynamic>{
            'list': <Map<String, String>>[
              <String, String>{
                'vod_id': 'vod-1',
                'vod_name': '测试影片',
                'vod_pic': 'https://example.test/poster.jpg',
              },
            ],
          });
        case 'detail':
          return json.encode(<String, dynamic>{
            'list': <Map<String, String>>[
              <String, String>{
                'vod_play_from': '主线',
                'vod_play_url': r'第1集$token-1',
              },
            ],
          });
        case 'player':
          return json.encode(<String, dynamic>{
            'url': 'https://example.test/live.m3u8',
            'header': <String, String>{'Referer': 'https://example.test/'},
          });
      }
      return '{}';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('parses CatVod home, list, search, detail and player contracts',
      () async {
    expect(adapter.supports(site), isTrue);

    final categories = await adapter.fetchCategories(site);
    expect(categories.single.id, 'movie');

    final categoryItems = await adapter.fetchCategory(site, 'movie');
    expect(categoryItems.single.title, '测试影片');

    final searchItems = await adapter.search(site, '测试');
    expect(searchItems.single.id, 'vod-1');

    final candidates = await adapter.fetchCandidates(
      site,
      const MediaItem(id: 'vod-1', title: '测试影片'),
    );
    expect(candidates.single.lineName, '主线');
    final playback = await candidates.single.episodes.single.resolvePlayback!();
    expect(playback.url, endsWith('live.m3u8'));
    expect(
      playback.headers?['Referer'],
      'https://example.test/',
    );
  });

  test('HTTP episode pages still call player and retain returned headers',
      () async {
    final playerArguments = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      if (arguments['operation'] == 'detail') {
        return json.encode(<String, dynamic>{
          'list': <Map<String, String>>[
            <String, String>{
              'vod_play_from': 'main',
              'vod_play_url': r'Episode$https://site.test/watch/1.html',
            },
          ],
        });
      }
      playerArguments.add(
        Map<String, dynamic>.from(arguments['arguments'] as Map),
      );
      return json.encode(<String, dynamic>{
        'parse': 0,
        'url': 'https://cdn.test/media.m3u8',
        'header': '{"Referer":"https://site.test/"}',
      });
    });

    final candidates = await adapter.fetchCandidates(
      site,
      const MediaItem(id: '1', title: 'Example'),
    );

    expect(playerArguments, isEmpty);
    final playback = await candidates.single.episodes.single.resolvePlayback!();
    expect(playerArguments, <Map<String, dynamic>>[
      <String, dynamic>{
        'flag': 'main',
        'id': 'https://site.test/watch/1.html',
        'flags': <String>[],
      },
    ]);
    expect(playback.url, 'https://cdn.test/media.m3u8');
    expect(playback.headers?['Referer'], 'https://site.test/');
    expect(playback.resolvePlayback, isNull);
    expect(playback.requiresWebView, isFalse);
  });

  test('passes VIP flags and uses the selected line when player omits flag',
      () async {
    final configured = site.copyWith(
      flags: ['vip-line'],
      parses: [
        {'name': 'web', 'type': 0, 'url': 'https://parser.test/?url='},
      ],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      if (arguments['operation'] == 'detail') {
        return json.encode({
          'list': [
            {
              'vod_play_from': 'vip-line',
              'vod_play_url': r'Episode$https://site.test/watch/1',
            },
          ],
        });
      }
      expect((arguments['arguments'] as Map)['flags'], ['vip-line']);
      return json.encode({'url': 'https://site.test/watch/1', 'parse': 1});
    });

    final candidates = await adapter.fetchCandidates(
      configured,
      const MediaItem(id: '1', title: 'Example'),
    );
    final playback = await candidates.single.episodes.single.resolvePlayback!();
    expect(playback.url, 'https://parser.test/?url=https://site.test/watch/1');
    expect(playback.requiresWebView, isTrue);
  });
}
