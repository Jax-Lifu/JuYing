import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/app_ys_v2_dart_spider_adapter.dart';
import 'package:juying/features/tvbox/services/bilibili_spider_adapter.dart';
import 'package:juying/features/tvbox/services/cctv_vod_adapter.dart';
import 'package:juying/features/tvbox/services/python_compat_spider_adapter.dart';
import 'package:juying/features/tvbox/services/t4_http_spider_adapter.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';
import 'package:juying/features/tvbox/services/xbpq_dart_spider_adapter.dart';

void main() {
  test('federated search routes T4 to its API and honors CCTV search setting',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'list': <Map<String, String>>[
            <String, String>{'vod_id': 't4_result', 'vod_name': '测试赛事'},
          ],
        },
      ));
    }));
    final engine = TvBoxSpiderEngine(
      dio: dio,
      cctvAdapter: _FakeCctvAdapter(),
    );
    final results = await engine.federatedSearch(const <TvBoxSite>[
      TvBoxSite(
        key: 'sports_t4',
        name: '体育',
        type: 4,
        api: 'https://t4.test/vod',
      ),
      TvBoxSite(
        key: 'cctv_vod',
        name: '央视',
        type: 4,
        searchable: false,
      ),
    ], '测试');

    expect(results.map((item) => item.id), <String>['t4_result']);
    expect(requests.single.queryParameters['wd'], '测试');
  });

  test('known Python CCTV identity uses the cross-platform Dart replacement',
      () async {
    final adapter = PythonCompatSpiderAdapter(
      cctvAdapter: _FakeCctvAdapter(),
    );
    const site = TvBoxSite(
      key: 'py_cctv',
      name: '央视少儿',
      api: 'py_cctv_full',
      ext: 'https://example.test/cctv.py',
    );

    final categories = await adapter.fetchCategories(site);
    final media = await adapter.fetchCategory(site, categories[1].id);
    final candidates = await adapter.fetchCandidates(media.single);

    expect(PythonCompatSpiderAdapter.supports(site), isTrue);
    expect(media.single.id, 'cctv_album_test');
    expect(candidates.single.episodes.single.url, 'cctv_guid://episode');
  });

  test('XBPQ Dart adapter executes declarative category and playback rules',
      () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = switch (options.path) {
            'https://video.test/list/1/1.html' => '''
              <a class="module-item" href="/detail/1" title="跨平台影片"
                 data-original="/poster.jpg"></a>
            ''',
            'https://video.test/detail/1' => '<a href="/play/1.html">第1集</a>',
            'https://video.test/play/1.html' =>
              '<script>url:"https://cdn.test/video.m3u8"</script>',
            _ => '',
          };
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
    const site = TvBoxSite(
      key: 'xbpq',
      name: 'XBPQ',
      type: 3,
      api: 'csp_XBPQ',
      ext: <String, String>{
        '分类': r'电影$1',
        '分类url': 'https://video.test/list/{cateId}/{catePg}.html',
      },
    );
    final adapter = XbpqDartSpiderAdapter(dio);

    final categories = await adapter.fetchCategories(site);
    final media = await adapter.fetchCategory(site, categories.single.id);
    final candidates = await adapter.fetchCandidates(site, media.single);

    expect(categories.single.name, '电影');
    expect(media.single.title, '跨平台影片');
    final playable = await candidates.single.episodes.single.resolvePlayback!();
    expect(playable.url, endsWith('video.m3u8'));
  });

  test('XBPQ fallback does not capture dedicated Dart Spider identities', () {
    const bili = TvBoxSite(
      key: 'bili',
      name: 'Bili',
      type: 3,
      api: 'csp_Bili',
      ext: 'https://config.test/bili.json',
    );
    const appYs = TvBoxSite(
      key: 'appys',
      name: 'AppYs',
      type: 3,
      api: 'csp_AppYsV2',
      ext: 'https://video.test/api.php/app/',
    );

    expect(XbpqDartSpiderAdapter.supports(bili), isFalse);
    expect(BilibiliSpiderAdapter.supports(bili), isTrue);
    expect(XbpqDartSpiderAdapter.supports(appYs), isFalse);
    expect(AppYsV2DartSpiderAdapter.supports(appYs), isTrue);
  });

  test('Bilibili Dart Spider completes category, search and playback contract',
      () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          dynamic data;
          if (options.path.endsWith('/bili.json')) {
            data = json.encode(<String, dynamic>{
              'classes': <Map<String, String>>[
                <String, String>{'type_id': '儿童', 'type_name': '少儿'},
              ],
            });
          } else if (options.path.endsWith('/search/type')) {
            data = <String, dynamic>{
              'code': 0,
              'data': <String, dynamic>{
                'result': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'bvid': 'BV123',
                    'title': '测试<em>视频</em>',
                    'pic': '//image.test/poster.jpg',
                    'description': '简介',
                  },
                ],
              },
            };
          } else if (options.path.endsWith('/view')) {
            data = <String, dynamic>{
              'code': 0,
              'data': <String, dynamic>{
                'pages': <Map<String, dynamic>>[
                  <String, dynamic>{'cid': 1, 'part': '正片'},
                ],
              },
            };
          } else {
            data = <String, dynamic>{
              'code': 0,
              'data': <String, dynamic>{
                'quality': 64,
                'durl': <Map<String, String>>[
                  <String, String>{'url': 'https://video.test/main.mp4'},
                ],
              },
            };
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: data,
            ),
          );
        },
      ),
    );
    const site = TvBoxSite(
      key: 'bili',
      name: 'Bili',
      type: 3,
      api: 'csp_Bili',
      ext: 'https://config.test/bili.json',
    );
    final adapter = BilibiliSpiderAdapter(dio);

    final categories = await adapter.fetchCategories(site);
    final media = await adapter.search('测试');
    final candidates = await adapter.fetchCandidates(site, media.single);

    expect(categories.single.id, '儿童');
    expect(media.single.title, '测试视频');
    final playback = await candidates.single.episodes.single.resolvePlayback!();
    expect(playback.url, 'https://video.test/main.mp4');
    expect(playback.headers?['Referer'], 'https://www.bilibili.com/');
  });

  test('standard type=4 uses remote CatVod HTTP protocol instead of CCTV',
      () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          dynamic data;
          if (options.queryParameters['filter'] == 'true') {
            data = <String, dynamic>{
              'class': <Map<String, String>>[
                <String, String>{
                  'type_id': '2@直播',
                  'type_name': '直播',
                },
              ],
            };
          } else if (options.queryParameters.containsKey('t')) {
            data = <String, dynamic>{
              'list': <Map<String, String>>[
                <String, String>{
                  'vod_id': 'match_1',
                  'vod_name': '测试赛事',
                },
              ],
            };
          } else if (options.queryParameters.containsKey('ids')) {
            data = <String, dynamic>{
              'list': <Map<String, String>>[
                <String, String>{
                  'vod_play_from': '直播',
                  'vod_play_url': r'主线$stream_1',
                },
              ],
            };
          } else {
            data = <String, dynamic>{
              'parse': 0,
              'url': 'https://live.test/channel.flv',
              'header': <String, String>{'User-Agent': 'TVBox'},
            };
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: data,
            ),
          );
        },
      ),
    );
    const site = TvBoxSite(
      key: 'sports_t4',
      name: '体育',
      type: 4,
      api: 'https://t4.test/vod',
    );
    final adapter = T4HttpSpiderAdapter(dio);

    final categories = await adapter.fetchCategories(site);
    final media = await adapter.fetchCategory(site, categories.single.id);
    final candidates = await adapter.fetchCandidates(
      site,
      const MediaItem(id: 'match_1', title: '测试赛事'),
    );

    expect(site.adapterLabel, 'T4 HTTP');
    expect(media.single.title, '测试赛事');
    final playback = await candidates.single.episodes.single.resolvePlayback!();
    expect(playback.url, 'https://live.test/channel.flv');
    expect(playback.headers?['User-Agent'], 'TVBox');
  });

  test('AppYsV2 Dex identity uses the cross-platform Dart App API contract',
      () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          dynamic data;
          if (options.path.contains('/nav')) {
            data = <String, dynamic>{
              'data': <Map<String, String>>[
                <String, String>{
                  'type_id': '1',
                  'type_name': '电影',
                },
              ],
            };
          } else if (options.path.contains('/video_detail')) {
            data = <String, dynamic>{
              'data': <String, dynamic>{
                'vod_id': 'vod_1',
                'vod_name': '跨平台影片',
                'vod_url_with_player': <Map<String, String>>[
                  <String, String>{
                    'code': 'direct',
                    'url': r'第1集$https://media.test/1.m3u8',
                  },
                ],
              },
            };
          } else {
            data = <String, dynamic>{
              'data': <Map<String, String>>[
                <String, String>{
                  'vod_id': 'vod_1',
                  'vod_name': '跨平台影片',
                  'vod_pic': 'https://image.test/1.jpg',
                },
              ],
            };
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: data,
            ),
          );
        },
      ),
    );
    const site = TvBoxSite(
      key: 'app',
      name: 'App API',
      type: 3,
      api: 'csp_AppYsV2',
      ext: 'https://app.test/api.php/app/',
    );
    final adapter = AppYsV2DartSpiderAdapter(dio);

    final categories = await adapter.fetchCategories(site);
    final media = await adapter.fetchCategory(site, categories.single.id);
    final search = await adapter.search(site, '跨平台');
    final candidates = await adapter.fetchCandidates(site, media.single);

    expect(site.adapterLabel, 'Dart App API');
    expect(media.single.title, '跨平台影片');
    expect(search.single.id, 'vod_1');
    expect(candidates.single.episodes.single.url, 'https://media.test/1.m3u8');
  });
}

class _FakeCctvAdapter extends CctvVodAdapter {
  @override
  Future<List<MediaItem>> fetchAlbumList({
    required String channelId,
    required String firstCategory,
    String subCategory = '',
    String area = '',
    String letter = '',
    int page = 1,
    int pageSize = 24,
  }) async {
    return const <MediaItem>[
      MediaItem(id: 'cctv_album_test', title: '央视测试节目'),
    ];
  }

  @override
  Future<PlaybackCandidate?> fetchAlbumEpisodes(String albumId) async {
    return const PlaybackCandidate(
      sourceKey: 'cctv',
      sourceName: '央视',
      lineName: '官方',
      episodes: <PlaybackEpisode>[
        PlaybackEpisode(name: '第1集', url: 'cctv_guid://episode'),
      ],
    );
  }
}
