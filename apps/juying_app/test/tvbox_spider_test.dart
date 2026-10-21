import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/providers/tvbox_provider.dart';
import 'package:juying/features/tvbox/services/tvbox_config_service.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

void main() {
  group('TvBoxSpiderEngine Tests', () {
    test('provides built-in TVBox preset sites including CCTV official', () {
      final sites = TvBoxSpiderEngine.defaultPresetSites;
      expect(sites, isNotEmpty);
      expect(sites.any((s) => s.key == 'cctv_vod' && s.type == 4), isTrue);
      expect(sites.every((site) => site.isRuntimeSupported), isTrue);
    });

    test('fetches real MacCMS categories, media and direct playback lines',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final query = options.queryParameters;
            if (query['ac'] == 'list') {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'class': <Map<String, dynamic>>[
                      <String, dynamic>{'type_id': 2, 'type_name': '电视剧'},
                    ],
                  },
                ),
              );
              return;
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'list': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'vod_id': '100',
                      'vod_name': '测试剧集',
                      'vod_pic': 'https://img.example/poster.jpg',
                      'vod_content': '<p>真实 CMS 简介</p>',
                      'vod_play_from': r'hls$$$backup',
                      'vod_play_url':
                          r'第1集$https://media.example/1.m3u8|{"Referer":"https://cms.example/"}#第2集$https://media.example/2.m3u8$$$正片$https://backup.example/movie.mp4',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      const site = TvBoxSite(
        key: 'cms_test',
        name: '测试 CMS',
        type: 1,
        api: 'https://cms.example/api.php/provide/vod/',
      );
      final engine = TvBoxSpiderEngine(dio: dio);

      final categories = await engine.fetchSiteCategories(site);
      final items = await engine.fetchCategoryMedia(site, '2');
      final candidates = await engine.fetchMediaCandidates(site, items.first);

      expect(categories.single.name, '电视剧');
      expect(items.single.title, '测试剧集');
      expect(items.single.overview, '真实 CMS 简介');
      expect(candidates, hasLength(2));
      expect(candidates.first.lineName, 'hls');
      expect(candidates.first.episodes, hasLength(2));
      expect(candidates.first.episodes.first.headers?['Referer'],
          'https://cms.example/');
      expect(candidates.last.episodes.single.url,
          'https://backup.example/movie.mp4');
    });

    test('performs federated search against supported CMS sites only',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{
                'list': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'vod_id': 'qyn2',
                    'vod_name': '庆余年 第二季',
                  },
                ],
              },
            ),
          ),
        ),
      );
      final engine = TvBoxSpiderEngine(dio: dio);
      const sites = <TvBoxSite>[
        TvBoxSite(
          key: 'cms',
          name: 'CMS',
          type: 1,
          api: 'https://cms.example/api.php/provide/vod/',
        ),
        TvBoxSite(
          key: 'js',
          name: 'JS Spider',
          type: 3,
          api: 'csp_Test',
        ),
      ];

      final results = await engine.federatedSearch(sites, '庆余年');
      expect(results.single.title, contains('庆余年'));
    });

    test('parses MacCMS XML categories and episode groups', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final isList = options.queryParameters['ac'] == 'list';
            final xml = isList
                ? '<rss><class><ty id="1">电影</ty></class></rss>'
                : '<rss><list><video><id>9</id><name>XML影片</name>'
                    '<pic>https://img.example/9.jpg</pic><dl>'
                    '<dd flag="直连">正片\$https://media.example/9.m3u8</dd>'
                    '</dl></video></list></rss>';
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: xml,
              ),
            );
          },
        ),
      );
      const site = TvBoxSite(
        key: 'xml',
        name: 'XML CMS',
        type: 0,
        api: 'https://xml.example/api.php/provide/vod/',
      );
      final engine = TvBoxSpiderEngine(dio: dio);

      final categories = await engine.fetchSiteCategories(site);
      final items = await engine.fetchCategoryMedia(site, '1');
      final candidates = await engine.fetchMediaCandidates(site, items.single);

      expect(categories.single.name, '电影');
      expect(items.single.title, 'XML影片');
      expect(candidates.single.lineName, '直连');
      expect(candidates.single.episodes.single.url,
          'https://media.example/9.m3u8');
    });

    test('circuit-breaks a failing CMS source across repeated requests',
        () async {
      var requestCount = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCount++;
            handler.reject(
              DioException.badResponse(
                statusCode: 502,
                requestOptions: options,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 502,
                ),
              ),
            );
          },
        ),
      );
      const site = TvBoxSite(
        key: 'dead_cms',
        name: '失效 CMS',
        type: 1,
        api: 'https://dead.example/api.php/provide/vod/',
      );
      final engine = TvBoxSpiderEngine(dio: dio);

      expect(await engine.fetchSiteCategories(site), isEmpty);
      expect(await engine.fetchCategoryMedia(site, 'default'), isEmpty);
      expect(await engine.searchSite(site, '测试'), isEmpty);

      expect(requestCount, 1);
    });

    test('recursively expands multi-warehouse configs into actual sites',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.path.endsWith('/root.json')
                ? '{"urls":[{"name":"子仓","url":"child.json"}]}'
                : '{"sites":[{"key":"cms","name":"真实CMS",'
                    '"type":1,"api":"https://cms.example/api.php"}]}';
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: data,
              ),
            );
          },
        ),
      );

      final config = await TvBoxConfigService(dio: dio).loadConfig(
        'https://warehouse.example/root.json',
      );

      expect(config?.sites, hasLength(1));
      expect(config?.sites.single.key, 'cms');
      expect(config?.sites.single.isRuntimeSupported, isTrue);
    });

    test('propagates and resolves the global JAR only for csp sites', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: '{'
                    '"spider":"runtime/spider.jar;md5;ABC",'
                    '"sites":['
                    '{"key":"jar","name":"JAR","type":3,"api":"csp_Demo"},'
                    '{"key":"js","name":"JS","type":3,'
                    '"api":"https://example.com/drpy.js",'
                    '"ext":"https://example.com/rule.js"}'
                    ']'
                    '}',
              ),
            );
          },
        ),
      );

      final config = await TvBoxConfigService(dio: dio).loadConfig(
        'https://warehouse.example/config/root.json',
      );

      expect(
        config?.spiderUrl,
        'https://warehouse.example/config/runtime/spider.jar;md5;ABC',
      );
      expect(config?.sites.first.jar, config?.spiderUrl);
      expect(config?.sites.last.jar, isEmpty);
    });

    test('keeps different sites that reuse the same key across warehouses',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.path.endsWith('/root.json')
                ? '{"urls":[{"url":"a.json"},{"url":"b.json"}]}'
                : options.path.endsWith('/a.json')
                    ? '{"sites":[{"key":"cms","name":"A","type":1,'
                        '"api":"https://a.example/api"}]}'
                    : '{"sites":[{"key":"cms","name":"B","type":1,'
                        '"api":"https://b.example/api"}]}';
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: data,
              ),
            );
          },
        ),
      );

      final config = await TvBoxConfigService(dio: dio).loadConfig(
        'https://warehouse.example/root.json',
      );

      expect(config?.sites, hasLength(2));
      expect(config?.sites.map((site) => site.key).toSet(), hasLength(2));
      expect(
        config?.sites.map((site) => site.api),
        containsAll(<String>[
          'https://a.example/api',
          'https://b.example/api',
        ]),
      );
    });

    test('persists one subscription with its nested sites', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final writer = TvBoxSubscriptionsNotifier();
      writer.upsert(
        url: 'https://warehouse.example/config.json',
        sites: const <TvBoxSite>[
          TvBoxSite(
            key: 'persisted_cms',
            name: '持久化 CMS',
            type: 1,
            api: 'https://cms.example/api.php',
          ),
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final reader = TvBoxSubscriptionsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(reader.state.where((item) => !item.isBuiltIn), hasLength(1));
      expect(reader.state.last.sites.single.name, '持久化 CMS');
      writer.dispose();
      reader.dispose();
    });

    test('refreshes an existing imported subscription by URL', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final notifier = TvBoxSubscriptionsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      notifier.upsert(
        url: 'https://warehouse.example/config.json',
        sites: const <TvBoxSite>[
          TvBoxSite(
            key: 'refreshable',
            name: '旧源',
            type: 1,
            api: 'https://old.example/api',
          ),
        ],
      );
      notifier.upsert(
        url: 'https://warehouse.example/config.json',
        sites: const <TvBoxSite>[
          TvBoxSite(
            key: 'refreshable',
            name: '新源',
            type: 1,
            api: 'https://new.example/api',
            jar: 'https://new.example/spider.jar',
          ),
        ],
      );

      final imported = notifier.state.where((item) => !item.isBuiltIn);
      expect(imported, hasLength(1));
      final refreshed = imported.single.sites.single;
      expect(refreshed.name, '新源');
      expect(refreshed.api, 'https://new.example/api');
      expect(refreshed.jar, 'https://new.example/spider.jar');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      notifier.dispose();
    });

    test('deletes an imported subscription without removing the built-in one',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final notifier = TvBoxSubscriptionsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final imported = notifier.upsert(
        url: 'https://warehouse.example/delete-me.json',
        sites: const <TvBoxSite>[
          TvBoxSite(
            key: 'delete_me',
            name: '待删除源',
            type: 1,
            api: 'https://cms.example/api.php',
          ),
        ],
      );

      notifier.remove(imported.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(notifier.state, hasLength(1));
      expect(notifier.state.single.isBuiltIn, isTrue);
      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('tvbox_subscriptions_v2'), '[]');
      notifier.dispose();
    });

    test(
        'TvBoxConfigService handles JSON comments and trailing commas correctly',
        () {
      const dirtyJson = '''
      {
        // This is a single line comment
        "spider": "https://example.com/spider.jar",
        /* Multi-line
           comment here */
        "sites": [
          {
            "key": "test_site",
            "name": "测试站点",
            "type": 3,
            "api": "https://example.com/api.php", // comment inside site
          },
        ],
      }
      ''';

      final cleaned = TvBoxConfigService.sanitizeJson(dirtyJson);
      expect(cleaned, isNot(contains('This is a single line comment')));
      expect(cleaned, isNot(contains('Multi-line')));
      expect(cleaned, isNot(contains('comment inside site')));
      expect(cleaned, contains('https://example.com/spider.jar'));
      expect(cleaned, contains('测试站点'));

      final decoded = json.decode(cleaned);
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded['spider'], 'https://example.com/spider.jar');
      expect((decoded['sites'] as List).length, 1);
    });

    test('TvBoxConfigService escapes raw controls inside JSON strings', () {
      const dirtyJson = '''
      {
        "sites": [{
          "key": "dirty_controls",
          "name": "腾
讯\t视频",
          "type": 1,
          "api": "https://example.com/api.php"
        }]
      }
      ''';

      final cleaned = TvBoxConfigService.sanitizeJson(dirtyJson);
      final decoded = json.decode(cleaned) as Map<String, dynamic>;
      final sites = decoded['sites'] as List<dynamic>;
      final site = sites.single as Map<String, dynamic>;

      expect(site['name'], '腾\n讯\t视频');
    });

    test('TvBoxConfigService requests IDN warehouse hosts as punycode',
        () async {
      String? requestedHost;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestedHost = options.uri.host;
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: '{"sites":[]}',
              ),
            );
          },
        ),
      );

      await TvBoxConfigService(dio: dio).loadConfig('https://盒子迷.top/config');

      expect(requestedHost, startsWith('xn--'));
      expect(requestedHost, isNot(contains('%')));
    });

    test('parses TVBox shorthand string categories without dropping the site',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: '''
              {
                "sites": [{
                  "key": "xh_4k",
                  "name": "小胡 4K",
                  "type": 1,
                  "api": "https://example.com/api.php/provide/vod/ ",
                  "categories": [
                    "欧美剧",
                    "韩剧",
                    {"type_id": "6", "type_name": "动作片"},
                    42
                  ]
                }],
                "lives": ["bad", {"name": "直播"}],
                "parses": "invalid"
              }
              ''',
            ),
          ),
        ),
      );

      final config = await TvBoxConfigService(dio: dio).loadConfig(
        'http://xhztv.top/4k.json',
      );
      final site = config!.sites.single;

      expect(site.api, 'https://example.com/api.php/provide/vod/');
      expect(site.categories.map((category) => category.id), <String>[
        '欧美剧',
        '韩剧',
        '6',
      ]);
      expect(config.lives, hasLength(1));
      expect(config.parses, isEmpty);
    });

    test('TvBoxSpiderEngine cools down failing sites with progressive backoff',
        () async {
      var requestCount = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCount++;
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 404,
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      const failingSite = TvBoxSite(
        key: 'dead_site_404',
        name: 'Dead Site',
        type: 1,
        api: 'https://dead.example/api.php',
      );

      final engine = TvBoxSpiderEngine(dio: dio);

      // First request fails with HTTP 404 and triggers cooldown
      final items1 = await engine.fetchCategoryMedia(failingSite, '1');
      expect(items1, isEmpty);
      expect(requestCount, 1);

      // Second request immediately returns empty without hitting network
      final items2 = await engine.fetchCategoryMedia(failingSite, '1');
      expect(items2, isEmpty);
      expect(requestCount, 1);

      // Search also respects cooldown without hitting network
      final searchItems = await engine.searchSite(failingSite, 'test');
      expect(searchItems, isEmpty);
      expect(requestCount, 1);
    });
  });
}
