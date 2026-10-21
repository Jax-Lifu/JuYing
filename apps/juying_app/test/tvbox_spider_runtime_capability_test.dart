import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_runtime_capability.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('distinguishes DRPY JavaScript from JAR and Python type=3 sites', () {
    final drpy = TvBoxSpiderRuntimeCapability.inspect(
      api: 'https://example.com/lib/drpy2.min.js',
      ext: 'https://example.com/rules/douban.js',
    );
    final jar = TvBoxSpiderRuntimeCapability.inspect(
      api: 'csp_XBPQ',
      jar: 'https://example.com/spider.jar',
    );
    final python = TvBoxSpiderRuntimeCapability.inspect(api: 'py_cctv_full');

    expect(drpy.kind, TvBoxSpiderRuntimeKind.drpyJavaScript);
    expect(drpy.requiredBridges, contains('pdfh/pdfa/pdfl parser'));
    expect(jar.kind, TvBoxSpiderRuntimeKind.catVodJar);
    expect(python.kind, TvBoxSpiderRuntimeKind.dartNative);
    expect(<bool>[drpy.runtimeAvailable, jar.runtimeAvailable],
        everyElement(false));
  });

  test('classifies an arbitrary HTTP API as native HTTP rather than JavaScript',
      () {
    final capability = TvBoxSpiderRuntimeCapability.inspect(
      api: 'https://example.com/api.php',
    );

    expect(capability.kind, TvBoxSpiderRuntimeKind.dartNative);
    expect(capability.runtimeAvailable, isTrue);
  });

  test('recognizes the clean-room csp_Bili Dart adapter', () {
    const site = TvBoxSite(
      key: 'bili',
      name: '哔哩哔哩',
      type: 3,
      api: 'csp_Bili',
    );

    expect(site.isRuntimeSupported, isTrue);
    expect(
        site.spiderRuntimeCapability.kind, TvBoxSpiderRuntimeKind.dartNative);
    expect(site.spiderRuntimeCapability.runtimeAvailable, isTrue);
    expect(site.adapterLabel, 'Dart Spider');
  });

  test('site extension preserves JAR capability after persistence parsing', () {
    final site = TvBoxSite.fromJson(<String, dynamic>{
      'key': 'xbpq',
      'name': 'XBPQ',
      'type': 3,
      'api': 'csp_XBPQ',
      'jar': 'https://example.com/spider.jar',
    });

    expect(site.spiderRuntimeCapability.kind, TvBoxSpiderRuntimeKind.catVodJar);
    expect(site.spiderRuntimeCapability.label, '待 Flutter 适配');
    expect(site.adapterLabel, '待 Flutter 适配');
    expect(site.toJson()['jar'], 'https://example.com/spider.jar');
  });

  test('recognizes cross-platform XBPQ and known Python replacements', () {
    const xbpq = TvBoxSite(
      key: 'xbpq',
      name: 'XBPQ',
      api: 'csp_XBPQ',
      ext: <String, String>{'分类': r'电影$1'},
    );
    const python = TvBoxSite(
      key: 'cctv_python',
      name: '央视少儿',
      api: 'py_cctv_full',
      ext: 'https://example.test/cctv.py',
    );

    expect(xbpq.isRuntimeSupported, isTrue);
    expect(xbpq.adapterLabel, 'Dart XBPQ');
    expect(python.isRuntimeSupported, isTrue);
    expect(python.spiderRuntimeCapability.runtimeAvailable, isTrue);
    expect(python.adapterLabel, 'Dart 兼容');
  });

  test('recognizes the cross-platform AppYsV2 replacement', () {
    final capability = TvBoxSpiderRuntimeCapability.inspect(
      api: 'csp_AppYsV2',
      jar: 'https://example.test/spider.jar',
      ext: 'https://app.test/api.php/app/',
    );

    expect(capability.kind, TvBoxSpiderRuntimeKind.dartNative);
    expect(capability.runtimeAvailable, isTrue);
  });

  test('recognizes pure Dart ported spiders without DEX (ADR-008)', () {
    const czSite = TvBoxSite(
      key: 'cz',
      name: '厂长资源',
      type: 3,
      api: 'csp_Czsapp',
      jar: 'https://example.test/spider.jar',
    );
    const aueteSite = TvBoxSite(
      key: 'auete',
      name: '奥特影视',
      type: 3,
      api: 'csp_Auete',
      jar: 'https://example.test/spider.jar',
    );

    expect(czSite.isRuntimeSupported, isTrue);
    expect(
        czSite.spiderRuntimeCapability.kind, TvBoxSpiderRuntimeKind.dartNative);
    expect(czSite.adapterLabel, 'Dart 移植');

    expect(aueteSite.isRuntimeSupported, isTrue);
    expect(aueteSite.spiderRuntimeCapability.kind,
        TvBoxSpiderRuntimeKind.dartNative);
    expect(aueteSite.adapterLabel, 'Dart 移植');
  });
}
