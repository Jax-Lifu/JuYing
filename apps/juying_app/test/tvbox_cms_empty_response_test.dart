import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

void main() {
  const site = TvBoxSite(
    key: 'empty_cms',
    name: 'CMS',
    type: 1,
    api: 'https://cms.example/api.php/provide/vod/',
  );
  const fallbackItems = {
    'list': [
      {'vod_id': 'unrelated', 'vod_name': 'Unrelated homepage item'},
    ],
  };
  final emptyResponses = <String, Object>{
    'JSON object': {'list': <Object>[]},
    'JSON text': '{"list":[]}',
    'XML list': '<rss><list page="3" pagecount="2"/></rss>',
    'XML videos': '<videos/>',
  };

  for (final fixture in emptyResponses.entries) {
    for (final search in [false, true]) {
      test('${fixture.key} empty ${search ? 'search' : 'category'} stays empty',
          () async {
        final requests = <RequestOptions>[];
        final dio = Dio();
        dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: requests.length == 1 ? fixture.value : fallbackItems,
          ));
        }));
        final engine = TvBoxSpiderEngine(dio: dio);

        final items = search
            ? await engine.searchSite(site, 'no match')
            : await engine.fetchCategoryMedia(site, '2', page: 3);

        expect(items, isEmpty);
        expect(requests, hasLength(1));
        expect(
            requests.single.queryParameters,
            search
                ? {'ac': 'detail', 'wd': 'no match', 'pg': 1}
                : {
                    'ac': 'detail',
                    't': '2',
                    'pg': 3,
                  });
      });
    }
  }

  for (final response in <Object>[
    '<html><body>Use the website catalog</body></html>',
    '<?xml version="1.0"?><error>Unsupported API</error>',
    {'code': 0, 'msg': 'Unsupported API'},
    {
      'list': [
        {'vod_name': 'Missing ID'},
      ],
    },
    '{"list":[42,{"title":"Not a CMS entry"}]}',
    '<rss><list><video><name>Missing ID</name></video></list></rss>',
  ]) {
    test('unrecognized response keeps the existing catalog fallback: $response',
        () async {
      var requests = 0;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests++;
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: requests == 1 ? response : fallbackItems,
        ));
      }));

      final items =
          await TvBoxSpiderEngine(dio: dio).fetchCategoryMedia(site, '2');

      expect(items.single.id, 'unrelated');
      expect(requests, 2);
    });
  }

  for (final response in <Object>[
    {
      'list': [
        null,
        {'vod_name': 'Missing ID'},
        {'vod_id': 'valid', 'vod_name': 'Valid item'},
      ],
    },
    '<rss><list><video><name>Missing ID</name></video>'
        '<video><id>valid</id><name>Valid item</name></video></list></rss>',
  ]) {
    test('partly valid list returns its media without fallback: $response',
        () async {
      var requests = 0;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests++;
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: response,
        ));
      }));

      final items =
          await TvBoxSpiderEngine(dio: dio).fetchCategoryMedia(site, '2');

      expect(items.single.id, 'valid');
      expect(requests, 1);
    });
  }
}
