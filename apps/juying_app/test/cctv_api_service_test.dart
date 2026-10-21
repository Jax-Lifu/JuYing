import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juying/features/cctv/models/cctv_channel.dart';
import 'package:juying/features/cctv/models/cctv_filter.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';

void main() {
  group('CctvApiService & CCTV YXG Portal Tests', () {
    test('provides official CCTV YXG filter dimensions and channels', () {
      expect(CctvTopCategory.values.length, 5);
      expect(CctvTopCategory.movie.name, '电影');
      expect(CctvTopCategory.drama.name, '电视剧');
      expect(CctvTopCategory.animation.name, '动画片');
      expect(CctvTopCategory.documentary.name, '纪录片');
      expect(CctvTopCategory.special.name, '特别节目');

      expect(CctvFilterState.dramaGenres, isNotEmpty);
      expect(CctvFilterState.dramaGenres, contains('古装'));
      expect(CctvFilterState.dramaGenres, contains('武侠'));

      expect(CctvFilterState.movieGenres, contains('爱情'));
      expect(CctvFilterState.movieGenres, contains('战争'));

      expect(CctvFilterState.animationGenres, isNotEmpty);
      expect(CctvFilterState.animationGenres, contains('亲子'));
      expect(CctvFilterState.animationGenres, contains('益智'));

      expect(CctvFilterState.documentaryGenres, isNotEmpty);
      expect(CctvFilterState.documentaryGenres, contains('人文历史'));

      expect(CctvFilterState.specialGenres, isNotEmpty);
      expect(CctvFilterState.specialTags, contains('春节'));
      expect(CctvFilterState.specialTags, contains('中秋'));

      expect(CctvFilterState.areas, contains('内地（大陆）'));
      expect(CctvFilterState.years, contains('2026'));
      expect(CctvFilterState.letters, contains('A'));
      expect(CctvFilterState.channels, isNotEmpty);

      final channels = CctvChannel.officialChannels;
      expect(channels.length, greaterThanOrEqualTo(17));
      expect(channels.any((ch) => ch.id == 'cctv4k' && ch.is4K), isTrue);
      expect(
        channels.first.officialPageUrl,
        'https://tv.cctv.com/live/cctv1/index.shtml',
      );
      expect(
        channels
            .firstWhere((channel) => channel.id == 'cctv14')
            .officialPageUrl,
        'https://tv.cctv.com/live/cctvchild/index.shtml',
      );
    });

    test('fetches CCTV YXG filtered albums with total count and rich fields',
        () async {
      final service = CctvApiService();
      final result = await service.fetchYxgAlbums(
        firstCategory: '电视剧',
        genre: '古装',
        pageSize: 5,
      );

      expect(result.albums, isNotEmpty);
      expect(result.total, greaterThan(0));

      final first = result.albums.first;
      expect(first.title, isNotEmpty);
      expect(first.posterUrl, isNotEmpty);

      final mediaItem = first.toMediaItem();
      expect(mediaItem.id, startsWith('cctv_album_'));
      expect(mediaItem.title, first.title);
    });

    test('列表接口返回占位集数时使用分集接口总数补正', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('getVideoAlbumList')) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  data: <String, dynamic>{
                    'data': <String, dynamic>{
                      'total': 1,
                      'list': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'id': 'album-52',
                          'title': '《测试动画》',
                          'image': 'https://example.com/poster.jpg',
                          'count': '1',
                        },
                      ],
                    },
                  },
                ),
              );
              return;
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: <String, dynamic>{
                  'data': <String, dynamic>{'total': 52},
                },
              ),
            );
          },
        ),
      );

      final result = await CctvApiService(dio: dio).fetchYxgAlbums(
        firstCategory: '动画片',
      );

      expect(result.albums.single.totalEpisodes, 52);
      expect(result.albums.single.toMediaItem().totalEpisodes, 52);
    });

    test('fetches album episodes and builds candidate line', () async {
      final service = CctvApiService();
      final candidate =
          await service.fetchAlbumEpisodes('VIDA8lgsyrdD1LuVvEdkr2Fd260625');

      expect(candidate, isNotNull);
      expect(candidate!.episodes, isNotEmpty);
      expect(candidate.episodes.first.url, contains('cctv_guid://'));
    });

    test('filters CNTV highlight clips and keeps ordered full episodes',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: <String, dynamic>{
                  'data': <String, dynamic>{
                    'list': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'title': '正片看点：精彩片段',
                        'guid': 'clip-guid',
                        'length': '00:01:20',
                      },
                      <String, dynamic>{
                        'title': '《测试剧》 第2集',
                        'guid': 'episode-2',
                        'url': 'https://tv.cctv.com/2026/01/02/episode-2.shtml',
                        'image': 'https://example.com/episode-2.jpg',
                        'length': '00:42:00',
                        'part': 2,
                      },
                      <String, dynamic>{
                        'title': '《测试剧》 第1集',
                        'guid': 'episode-1',
                        'url': 'https://tv.cctv.com/2026/01/01/episode-1.shtml',
                        'image': 'https://example.com/episode-1.jpg',
                        'length': '00:43:00',
                        'part': 1,
                      },
                    ],
                  },
                },
              ),
            );
          },
        ),
      );

      final candidate =
          await CctvApiService(dio: dio).fetchAlbumEpisodes('test-album');

      expect(candidate, isNotNull);
      expect(candidate!.episodes, hasLength(2));
      expect(
          candidate.episodes.map((episode) => episode.sortIndex), <int>[1, 2]);
      expect(
        candidate.episodes.first.officialPageUrl,
        'https://tv.cctv.com/2026/01/01/episode-1.shtml',
      );
      expect(
        candidate.episodes.first.thumbnailUrl,
        'https://example.com/episode-1.jpg',
      );
      expect(
        candidate.episodes.any((episode) => episode.url.contains('clip-guid')),
        isFalse,
      );
    });

    test('片库 count 错误时仍返回汪汪队第八季的完整 52 集', () async {
      final service = CctvApiService();
      final candidate = await service.fetchAlbumEpisodes(
        'VIDAVcwK6oqbxwOPmVxNL87e260710',
      );

      expect(candidate, isNotNull);
      expect(candidate!.episodes, hasLength(52));
      expect(candidate.episodes.first.name, contains('第1集'));
      expect(candidate.episodes.last.name, contains('第52集'));
      expect(candidate.episodes.first.duration, const Duration(seconds: 632));
    });

    test('将央视明文主清单解析为绝对地址并忽略 UDRM 线路', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('getHttpVideoInfo.do')) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'hls_url':
                        'https://clear.example/asp/hls/main/video/main.m3u8',
                    'video': <String, dynamic>{'totalLength': '632.28'},
                    'manifest': <String, dynamic>{
                      'hls_enc_url':
                          'https://cdn.example/asp/enc/hls/main/video/main.m3u8?token=1',
                    },
                  },
                ),
              );
              return;
            }
            if (options.path.contains('/asp/hls/850/')) {
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: '#EXTM3U\n#EXTINF:10.0,\n0.ts\n#EXT-X-ENDLIST\n',
                ),
              );
              return;
            }
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: '#EXTM3U\n'
                    '#EXT-X-STREAM-INF:BANDWIDTH=460800\n'
                    '/asp/hls/450/video/450.m3u8\n',
              ),
            );
          },
        ),
      );

      final playback =
          await CctvApiService(dio: dio).resolveCctvGuidPlayback('guid');

      expect(playback, isNotNull);
      expect(playback!.duration, const Duration(milliseconds: 632280));
      expect(playback.variants.map((variant) => variant.label),
          <String>['标清', '流畅']);
      expect(playback.variants.first.url,
          'https://clear.example/asp/hls/850/video/850.m3u8');
    });

    test('resolves cctv_guid to playable HLS manifest with CDN token',
        () async {
      final service = CctvApiService();
      final hlsUrl =
          await service.resolveCctvGuid('a0f3f5b065eb4e81bb97c463512f58aa');

      expect(hlsUrl, isNotNull);
      expect(hlsUrl!, contains('.m3u8'));
      expect(hlsUrl, isNot(contains('/enc/')));
    });

    test('汪汪队第一集使用可解码的央视明文子清单', () async {
      final hlsUrl = await CctvApiService().resolveCctvGuid(
        'c34c3404797640ac804473811ea96d34',
      );

      expect(hlsUrl, isNotNull);
      expect(hlsUrl, contains('/asp/hls/850/'));
      expect(hlsUrl, isNot(contains('/enc/')));
    });
  });
}
