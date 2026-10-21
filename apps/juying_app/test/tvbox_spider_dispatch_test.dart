import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/android_dex_spider_adapter.dart';
import 'package:juying/features/tvbox/services/app_ys_v2_dart_spider_adapter.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_runtime_capability.dart';
import 'package:juying/features/tvbox/services/xbpq_dart_spider_adapter.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('unsupported sources cannot bypass the gate through engine entry points',
      () async {
    final requests = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.uri);
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: const <String, dynamic>{},
      ));
    }));
    final engine = TvBoxSpiderEngine(dio: dio);
    for (final api in <String>[
      'https://config.test/drpy2.min.js',
      'https://config.test/spider.py?version=2',
      'py_custom',
      'csp_Custom',
      'csp_XPath',
      'csp_XYQHiker',
    ]) {
      final site = TvBoxSite(
        key: api,
        name: api,
        api: api,
        jar: 'https://config.test/spider.jar',
        ext: 'https://config.test/rules.json',
        categories: const <TvBoxCategory>[
          TvBoxCategory(id: '1', name: 'Cached category'),
        ],
      );
      expect(await engine.fetchSiteCategories(site), isEmpty, reason: api);
      expect(await engine.fetchCategoryMedia(site, '1'), isEmpty, reason: api);
      expect(await engine.searchSite(site, 'film'), isEmpty, reason: api);
      expect(
        await engine.fetchMediaCandidates(
            site, const MediaItem(id: '1', title: 'Film')),
        isEmpty,
        reason: api,
      );
    }
    expect(requests, isEmpty);
  });

  test('type 3 HTTP fallback requires a known CMS API path', () async {
    const website =
        TvBoxSite(key: 'website', name: 'Website', api: 'https://video.test/');
    const cms = TvBoxSite(
        key: 'cms',
        name: 'CMS',
        api: 'https://video.test/api.php/provide/vod/',
        ext: 'https://unrelated.test/api.php/app/');
    expect(website.isRuntimeSupported, isFalse);
    expect(cms.isRuntimeSupported, isTrue);
    final requests = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.uri);
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: const <String, dynamic>{
          'class': <Map<String, String>>[
            <String, String>{'type_id': '1', 'type_name': 'Films'},
          ],
        },
      ));
    }));
    final engine = TvBoxSpiderEngine(dio: dio);
    expect(await engine.fetchSiteCategories(website), isEmpty);
    expect((await engine.fetchSiteCategories(cms)).single.name, 'Films');
    expect(requests.single.path, '/api.php/provide/vod/');
  });

  test('runtime gate agrees with diagnostics for unsupported Spider formats',
      () {
    for (final api in <String>[
      'https://config.test/drpy2.min.js',
      'https://config.test/spider.py?version=2',
      'py_custom',
      'csp_Custom',
      'csp_XPath',
      'csp_XYQHiker',
    ]) {
      final site = TvBoxSite(
        key: api,
        name: api,
        api: api,
        jar: 'https://config.test/spider.jar',
        ext: 'https://config.test/rules.json',
      );

      expect(site.isRuntimeSupported, isFalse, reason: api);
      expect(site.spiderRuntimeCapability.runtimeAvailable, isFalse,
          reason: api);
      expect(XbpqDartSpiderAdapter.supports(site), isFalse, reason: api);
    }
  });

  test('App-like ext does not divert an Android JAR away from its runtime',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const site = TvBoxSite(
      key: 'jar',
      name: 'JAR',
      api: 'csp_Custom',
      jar: 'https://config.test/spider.jar',
      ext: 'https://unrelated.test/api.php/app/',
    );
    final requests = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.uri);
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: const <String, dynamic>{},
      ));
    }));
    expect(AppYsV2DartSpiderAdapter.supports(site), isFalse);
    final engine = TvBoxSpiderEngine(dio: dio, dexAdapter: _RecordingDex());
    expect(
        (await engine.fetchSiteCategories(site)).single.name, 'Dex category');
    expect(requests, isEmpty);
  });

  test('XBPQ never captures script APIs even when their ext looks like rules',
      () {
    for (final api in <String>[
      'https://config.test/drpy.js',
      'py_custom',
      'csp_Custom',
      'csp_XPath',
      'csp_XYQHiker',
    ]) {
      final site = TvBoxSite(
        key: api,
        name: api,
        api: api,
        ext: const <String, String>{'分类': r'电影$1'},
      );
      expect(XbpqDartSpiderAdapter.supports(site), isFalse, reason: api);
    }
  });

  test('ported Bili aliases keep the Dart path on Android even with a JAR',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final engine = TvBoxSpiderEngine(dexAdapter: _RecordingDex());
    for (final api in <String>['csp_BiliGuard', 'csp_Bili2']) {
      final site = TvBoxSite(
        key: api,
        name: api,
        api: api,
        jar: 'https://config.test/spider.jar',
        ext: const <String, dynamic>{
          'class': <Map<String, String>>[
            <String, String>{'type_id': '儿童早教', 'type_name': '儿童早教'},
          ],
        },
      );
      expect((await engine.fetchSiteCategories(site)).single.name, '儿童早教');
    }
  });

  test('only standard HTTP APIs or the built-in CCTV identity enable type 4',
      () {
    for (final api in <String>['', 'csp_Custom', 'http-not-a-url']) {
      final site = TvBoxSite(key: 't4', name: 'T4', type: 4, api: api);
      expect(site.isRuntimeSupported, isFalse, reason: api);
      expect(site.spiderRuntimeCapability.runtimeAvailable, isFalse,
          reason: api);
    }
    const cctv = TvBoxSite(key: 'cctv_vod', name: '央视', type: 4);
    const t4 =
        TvBoxSite(key: 't4', name: 'T4', type: 4, api: 'https://api.test/vod');
    expect(cctv.isRuntimeSupported, isTrue);
    expect(cctv.spiderRuntimeCapability.runtimeAvailable, isTrue);
    expect(t4.isRuntimeSupported, isTrue);
    expect(t4.spiderRuntimeCapability.runtimeAvailable, isTrue);
  });

  test('Android keeps unknown JAR execution separate from XBPQ', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const site = TvBoxSite(
      key: 'jar',
      name: 'JAR',
      api: 'csp_Custom',
      jar: 'https://config.test/spider.jar',
      ext: <String, String>{'分类': r'电影$1'},
    );
    expect(site.isRuntimeSupported, isTrue);
    expect(site.spiderRuntimeCapability.kind, TvBoxSpiderRuntimeKind.catVodJar);
    expect(site.adapterLabel, 'Android Dex');
    expect(XbpqDartSpiderAdapter.supports(site), isFalse);
  });

  test('XBPQ and XB64 retain inline JSON and base64 rule formats', () async {
    final rules = <String, String>{'分类': r'电影$1'};
    for (final ext in <Object>[
      rules,
      jsonEncode(rules),
      base64Encode(utf8.encode(jsonEncode(rules))),
    ]) {
      for (final api in <String>['csp_XBPQ', 'csp_XB64']) {
        final site = TvBoxSite(key: '$api$ext', name: api, api: api, ext: ext);
        expect(site.isRuntimeSupported, isTrue);
        expect(site.spiderRuntimeCapability.runtimeAvailable, isTrue);
        expect(XbpqDartSpiderAdapter.supports(site), isTrue);
        final categories =
            await XbpqDartSpiderAdapter(Dio()).fetchCategories(site);
        expect(categories.single.id, '1');
        expect(categories.single.name, '电影');
      }
    }
  });

  test('unrecognized XBPQ rule documents do not fabricate categories or URLs',
      () async {
    final requests = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.uri);
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: const <String, dynamic>{'url': 'https://video.test/'},
      ));
    }));
    const site = TvBoxSite(
      key: 'invalid_rules',
      name: 'Invalid rules',
      api: 'csp_XBPQ',
      ext: 'https://config.test/rules.json',
    );
    final adapter = XbpqDartSpiderAdapter(dio);
    await expectLater(adapter.fetchCategories(site), throwsUnsupportedError);
    expect(requests.single.toString(), 'https://config.test/rules.json');
  });

  test('partial XBPQ rules do not invent missing category and search routes',
      () async {
    final requests = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.uri);
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: const <String, String>{'主页url': 'https://video.test/'},
      ));
    }));
    const site = TvBoxSite(
      key: 'partial_rules',
      name: 'Partial rules',
      api: 'csp_XBPQ',
      ext: 'https://config.test/rules.json',
    );
    final adapter = XbpqDartSpiderAdapter(dio);
    expect(await adapter.fetchCategories(site), isEmpty);
    expect(await adapter.fetchCategory(site, '1'), isEmpty);
    expect(await adapter.search(site, 'film'), isEmpty);
    expect(requests.single.toString(), 'https://config.test/rules.json');
  });
}

class _RecordingDex extends AndroidDexSpiderAdapter {
  @override
  Future<List<TvBoxCategory>> fetchCategories(TvBoxSite site) async =>
      const <TvBoxCategory>[TvBoxCategory(id: 'dex', name: 'Dex category')];
}
