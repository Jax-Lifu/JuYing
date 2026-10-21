import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/bilibili_spider_adapter.dart';

void main() {
  test('BiliGuard reads ext.json class and excludes the configuration action',
      () async {
    final requests = <RequestOptions>[];
    final dio = _fixtureDio(requests, (request) {
      if (request.uri.host == 'config.test') {
        return <String, dynamic>{
          'class': <Map<String, String>>[
            <String, String>{'type_id': 'peizhi', 'type_name': '登陆配置'},
            <String, String>{'type_id': '儿童早教', 'type_name': '儿童早教'},
          ],
        };
      }
      return <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{
          'result': <Map<String, String>>[
            <String, String>{'bvid': 'BVfixture', 'title': '早教视频'},
          ],
        },
      };
    });
    const site = TvBoxSite(
      key: 'bili_guard',
      name: '少儿教育',
      type: 3,
      api: 'csp_BiliGuard',
      ext: <String, String>{'json': 'https://config.test/children.txt'},
    );
    final adapter = BilibiliSpiderAdapter(dio);

    expect(BilibiliSpiderAdapter.supports(site), isTrue);
    final categories = await adapter.fetchCategories(site);
    expect(categories.single.id, '儿童早教');
    final media = await adapter.fetchCategory(categories.single.id, page: 2);
    expect(media.single.id, 'BVfixture');
    expect(requests.first.uri.toString(), 'https://config.test/children.txt');
    expect(requests.last.queryParameters['keyword'], '儿童早教');
    expect(requests.last.queryParameters['page'], 2);
  });

  test('Bili2 accepts inline class config without claiming PGC or live support',
      () async {
    final requests = <RequestOptions>[];
    final adapter = BilibiliSpiderAdapter(_fixtureDio(requests, (_) => null));
    const site = TvBoxSite(
      key: 'bili2',
      name: '学习课堂',
      type: 3,
      api: 'csp_Bili2',
      ext: <String, dynamic>{
        'class': <Map<String, String>>[
          <String, String>{'type_id': '小学语文', 'type_name': '语文'},
        ],
      },
    );

    expect(BilibiliSpiderAdapter.supports(site), isTrue);
    expect((await adapter.fetchCategories(site)).single.id, '小学语文');
    expect(requests, isEmpty);
    for (final api in <String>['csp_Bilimd', 'csp_BiliLive']) {
      expect(
        BilibiliSpiderAdapter.supports(
          TvBoxSite(key: api, name: api, type: 3, api: api),
        ),
        isFalse,
      );
    }
  });

  test('BV detail resolves only the selected page and refreshes expiring URLs',
      () async {
    final requests = <RequestOptions>[];
    var playCalls = 0;
    final dio = _fixtureDio(requests, (request) {
      if (request.path.endsWith('/view')) {
        return <String, dynamic>{
          'code': 0,
          'data': <String, dynamic>{
            'pages': <Map<String, dynamic>>[
              <String, dynamic>{'cid': 11, 'page': 1, 'part': '上集'},
              <String, dynamic>{
                'cid': 22,
                'page': 2,
                'part': '下集',
                'duration': 120,
              },
            ],
          },
        };
      }
      playCalls++;
      return <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{
          'quality': 32,
          'durl': <Map<String, String>>[
            <String, String>{'url': 'https://media.test/$playCalls.mp4'},
          ],
        },
      };
    });
    const site = TvBoxSite(key: 'bili', name: 'Bili', type: 3, api: 'csp_Bili');
    final adapter = BilibiliSpiderAdapter(dio);

    final candidates = await adapter.fetchCandidates(
      site,
      const MediaItem(id: 'BVfixture', title: '合集'),
    );
    expect(requests, hasLength(1));
    expect(playCalls, 0);
    final episode = candidates.single.episodes[1];
    expect(episode.duration, const Duration(seconds: 120));
    final first = await episode.resolvePlayback!();
    final refreshed = await episode.resolvePlayback!();
    expect(requests.skip(1).every((r) => r.queryParameters['cid'] == '22'),
        isTrue);
    expect(first.url, 'https://media.test/1.mp4');
    expect(refreshed.url, 'https://media.test/2.mp4');
    expect(refreshed.name, '下集');
    expect(refreshed.sortIndex, 2);
    expect(refreshed.duration, const Duration(seconds: 120));
    expect(refreshed.badge, '480P');
    expect(refreshed.headers?['Referer'], 'https://www.bilibili.com/');
    expect(refreshed.officialPageUrl,
        'https://www.bilibili.com/video/BVfixture?p=2');
    expect(refreshed.resolvePlayback, isNull);
  });

  test('a rejected play response fails the selected page explicitly', () async {
    final dio = _fixtureDio(<RequestOptions>[], (request) {
      if (request.path.endsWith('/view')) {
        return <String, dynamic>{
          'code': 0,
          'data': <String, dynamic>{
            'pages': <Map<String, dynamic>>[
              <String, dynamic>{'cid': 11, 'part': '正片'},
            ],
          },
        };
      }
      return <String, dynamic>{'code': -10403, 'message': 'Access denied'};
    });
    final candidates = await BilibiliSpiderAdapter(dio).fetchCandidates(
      const TvBoxSite(key: 'bili', name: 'Bili', type: 3, api: 'csp_Bili'),
      const MediaItem(id: 'BVfixture', title: '视频'),
    );
    expect(candidates.single.episodes, hasLength(1));
    await expectLater(candidates.single.episodes.single.resolvePlayback!(),
        throwsA(isA<StateError>()));
  });

  test('multiple durl segments are not silently truncated to the first file',
      () async {
    final dio = _fixtureDio(<RequestOptions>[], (request) {
      if (request.path.endsWith('/view')) {
        return <String, dynamic>{
          'code': 0,
          'data': <String, dynamic>{
            'pages': <Map<String, dynamic>>[
              <String, dynamic>{'cid': 11, 'part': '正片'},
            ],
          },
        };
      }
      return <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{
          'durl': <Map<String, String>>[
            <String, String>{'url': 'https://media.test/part1.flv'},
            <String, String>{'url': 'https://media.test/part2.flv'},
          ],
        },
      };
    });
    final candidates = await BilibiliSpiderAdapter(dio).fetchCandidates(
      const TvBoxSite(key: 'bili', name: 'Bili', type: 3, api: 'csp_Bili'),
      const MediaItem(id: 'BVfixture', title: '视频'),
    );
    await expectLater(candidates.single.episodes.single.resolvePlayback!(),
        throwsA(isA<UnsupportedError>()));
  });
}

Dio _fixtureDio(
  List<RequestOptions> requests,
  Object? Function(RequestOptions) reply,
) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    requests.add(request);
    handler.resolve(Response<Object?>(
      requestOptions: request,
      statusCode: 200,
      data: reply(request),
    ));
  }));
  return dio;
}
