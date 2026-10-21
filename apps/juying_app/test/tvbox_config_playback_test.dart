import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_config_service.dart';

void main() {
  Future<TvBoxConfig?> load(Map<String, Object> documents) {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response<String>(
        requestOptions: options,
        statusCode: 200,
        data: jsonEncode(documents[Uri.parse(options.path).path]),
      ));
    }));
    return TvBoxConfigService(dio: dio)
        .loadConfig('https://warehouse.example/root.json');
  }

  test('keeps each warehouse parser context through copies and persistence',
      () async {
    final config = await load({
      '/root.json': {
        'urls': [
          {'url': 'a/config.json'},
          {'url': 'b/config.json'},
        ],
      },
      for (final warehouse in ['a', 'b'])
        '/$warehouse/config.json': {
          'sites': [
            {
              'key': 'cms',
              'name': 'CMS',
              'type': 1,
              'api': 'https://cms.example/api',
            },
          ],
          'flags': [warehouse],
          'parses': [
            {'name': 'parser', 'type': 1, 'url': './parse?url='},
          ],
        },
    });
    expect(config!.sites, hasLength(2));
    for (var i = 0; i < 2; i++) {
      final warehouse = ['a', 'b'][i];
      final saved = TvBoxSite.fromJson(config.sites[i].copyWith().toJson());
      expect(saved.toJson()['flags'], [warehouse]);
      expect(saved.toJson()['parses'], [
        {
          'name': 'parser',
          'type': 1,
          'url': 'https://warehouse.example/$warehouse/parse?url=',
        },
      ]);
    }
  });

  test('resolves API, per-site JAR and remote rules against their warehouse',
      () async {
    final config = await load({
      '/root.json': {
        'spider': './default.jar',
        'sites': [
          {
            'key': 'jar',
            'api': 'csp_XBPQ',
            'jar': './runtime/custom.jar;md5;ABC',
            'ext': './rules/demo.json',
          },
          {'key': 'js', 'api': './runtime/drpy.js', 'ext': 'rules/demo.js'},
          {'key': 't4', 'type': 4, 'api': './api/t4'},
        ],
      },
    });
    final sites = config!.sites;
    expect(sites[0].api, 'csp_XBPQ');
    expect(
        sites[0].jar, 'https://warehouse.example/runtime/custom.jar;md5;ABC');
    expect(sites[0].ext, 'https://warehouse.example/rules/demo.json');
    expect(sites[1].api, 'https://warehouse.example/runtime/drpy.js');
    expect(sites[1].ext, 'https://warehouse.example/rules/demo.js');
    expect(sites[2].api, 'https://warehouse.example/api/t4');
  });

  test('keeps embedded rules and opaque extension arguments unchanged',
      () async {
    const embedded = '{"主页url":"https://example.com"}';
    final config = await load({
      '/root.json': {
        'sites': [
          {'key': 'json', 'api': 'csp_XBPQ', 'ext': embedded},
          {'key': 'python', 'api': 'py_cctv', 'ext': '动画片'},
          {'key': 'opaque', 'api': 'csp_Demo', 'ext': 'token/key'},
        ],
      },
    });
    expect(
        config!.sites.map((site) => site.ext), [embedded, '动画片', 'token/key']);
    expect(config.sites[1].api, 'py_cctv');
  });

  test('child parser aggregation cannot change the parent site context',
      () async {
    final config = await load({
      '/root.json': {
        'sites': [
          {'key': 'parent', 'type': 1, 'api': 'https://cms.example/api'},
        ],
        'parses': [
          {'name': 'parent parser', 'type': 0, 'url': './parse?url='},
        ],
        'urls': [
          {'url': 'child.json'},
        ],
      },
      '/child.json': {
        'parses': [
          {'name': 'child parser', 'type': 0, 'url': './other?url='},
        ],
      },
    });
    expect(config!.parses, hasLength(2));
    expect(config.sites.single.parses, hasLength(1));
    expect(config.sites.single.parses.single['name'], 'parent parser');
  });
}
