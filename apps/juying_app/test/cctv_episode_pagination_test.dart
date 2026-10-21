import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/cctv/services/cctv_api_service.dart';

Map<String, dynamic> _episode(int number) => <String, dynamic>{
      'title': '《测试动画》 第$number集',
      'guid': 'episode-$number',
      'part': number,
      'length': '00:10:00',
    };

void main() {
  test('loads every page of a long CCTV album', () async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final pages = <int>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      final page = request.queryParameters['p'] as int;
      pages.add(page);
      expect(request.queryParameters['n'], 100);
      handler.resolve(Response<dynamic>(
        requestOptions: request,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'total': 152,
            'list': <Map<String, dynamic>>[
              for (var number = (page - 1) * 100 + 1;
                  number <= (page == 1 ? 100 : 152);
                  number++)
                _episode(number),
            ],
          },
        },
      ));
    }));

    final result =
        await CctvApiService(dio: dio).fetchAlbumEpisodes('long-album');
    expect(result!.episodes, hasLength(152));
    expect(result.episodes.last.url, 'cctv_guid://episode-152');
    expect(pages, <int>[1, 2]);
  });

  test('deduplicates overlapping pages and stops when a page repeats',
      () async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final pages = <int>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      final page = request.queryParameters['p'] as int;
      pages.add(page);
      expect(page, lessThanOrEqualTo(3));
      handler.resolve(Response<dynamic>(
        requestOptions: request,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'total': '1000',
            'list': <Map<String, dynamic>>[
              _episode(page == 1 ? 1 : 2),
              _episode(page == 1 ? 2 : 3),
            ],
          },
        },
      ));
    }));

    final result = await CctvApiService(dio: dio).fetchAlbumEpisodes('overlap');
    expect(
        result!.episodes.map((episode) => episode.sortIndex), <int>[1, 2, 3]);
    expect(pages, <int>[1, 2, 3]);
  });

  test('preserves fetched episodes when a later page fails', () async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final pages = <int>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      final page = request.queryParameters['p'] as int;
      pages.add(page);
      if (page == 2) {
        handler.reject(DioException(
          requestOptions: request,
          type: DioExceptionType.connectionTimeout,
        ));
        return;
      }
      handler.resolve(Response<dynamic>(
        requestOptions: request,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'total': 101,
            'list': <Map<String, dynamic>>[
              for (var number = 1; number <= 100; number++) _episode(number),
            ],
          },
        },
      ));
    }));

    final result = await CctvApiService(dio: dio).fetchAlbumEpisodes('partial');
    expect(result!.episodes, hasLength(100));
    expect(pages, <int>[1, 2]);
  });

  test('overlapping rows do not count twice toward the reported total',
      () async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final pages = <int>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      final page = request.queryParameters['p'] as int;
      pages.add(page);
      final numbers = <List<int>>[
        <int>[1, 2],
        <int>[2, 3],
        <int>[4],
      ][page - 1];
      handler.resolve(Response<dynamic>(
        requestOptions: request,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'total': 4,
            'list': numbers.map(_episode).toList(),
          },
        },
      ));
    }));

    final result =
        await CctvApiService(dio: dio).fetchAlbumEpisodes('overlap-total');
    expect(result!.episodes.map((episode) => episode.sortIndex),
        <int>[1, 2, 3, 4]);
    expect(pages, <int>[1, 2, 3]);
  });

  test('live long album includes episodes beyond the first 100 records',
      () async {
    final result = await CctvApiService()
        .fetchAlbumEpisodes('VIDA9GIP7nMnaOU9lAV86Gs2260506');
    expect(result, isNotNull);
    expect(result!.episodes.length, greaterThanOrEqualTo(152));
    expect(result.episodes.any((episode) => episode.sortIndex == 152), isTrue);
  }, skip: !const bool.fromEnvironment('TVBOX_LIVE_TEST'));
}
