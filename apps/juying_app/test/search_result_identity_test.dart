import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/cctv/models/cctv_album.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';
import 'package:juying/features/search/services/federated_search_service.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

/// 同名翻拍有独立目录 ID，不能因展示标题相同而吞掉其中一部。
class _SameTitleCatalog extends CctvApiService {
  _SameTitleCatalog({this.repeatAcrossCategories = false});

  final bool repeatAcrossCategories;

  @override
  Future<CctvQueryResult> fetchYxgAlbums({
    required String firstCategory,
    String genre = '',
    String area = '',
    String year = '',
    String letter = '',
    String channelId = '',
    int page = 1,
    int pageSize = 24,
  }) async {
    return CctvQueryResult(
      total: firstCategory == '电影' || repeatAcrossCategories ? 2 : 0,
      albums: firstCategory == '电影' || repeatAcrossCategories
          ? const <CctvAlbum>[
              CctvAlbum(
                id: 'old',
                title: '同名作品',
                year: '1990',
                posterUrl: '',
                overview: '',
                category: '电影',
              ),
              CctvAlbum(
                id: 'remake',
                title: '同名作品',
                year: '2020',
                posterUrl: '',
                overview: '',
                category: '电影',
              ),
            ]
          : const <CctvAlbum>[],
    );
  }
}

TvBoxSpiderEngine _cmsEngine(
  List<Map<String, String>> Function(RequestOptions) results,
) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: <String, dynamic>{'list': results(options)},
          ),
        );
      },
    ),
  );
  return TvBoxSpiderEngine(dio: dio);
}

const _cmsSite = TvBoxSite(
  key: 'cms',
  name: 'CMS',
  type: 1,
  api: 'https://cms.test/api.php/provide/vod/',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CMS search keeps distinct media IDs with the same title', () async {
    final engine = _cmsEngine((_) => <Map<String, String>>[
          <String, String>{
            'vod_id': 'old',
            'vod_name': '同名作品',
            'vod_year': '1990',
          },
          <String, String>{
            'vod_id': 'remake',
            'vod_name': '同名作品',
            'vod_year': '2020',
          },
        ]);
    final results = await engine.federatedSearch(
      const <TvBoxSite>[_cmsSite],
      '同名',
    );

    expect(results.map((item) => item.id), <String>['old', 'remake']);
  });

  test('CMS search deduplicates one site by media ID', () async {
    final engine = _cmsEngine((_) => <Map<String, String>>[
          <String, String>{'vod_id': '1', 'vod_name': '作品'},
          <String, String>{'vod_id': '1', 'vod_name': '作品（高清）'},
        ]);
    final results = await engine.federatedSearch(
      const <TvBoxSite>[_cmsSite],
      '作品',
    );

    expect(results.single.id, '1');
  });

  test('CMS search keeps the same media ID from different sites', () async {
    final engine = _cmsEngine((_) => <Map<String, String>>[
          <String, String>{'vod_id': '1', 'vod_name': '作品'},
        ]);
    final results = await engine.federatedSearch(
      <TvBoxSite>[
        _cmsSite,
        _cmsSite.copyWith(
          key: 'cms_other',
          api: 'https://other.test/api.php/provide/vod/',
        ),
      ],
      '作品',
    );

    expect(results.map((item) => item.id), <String>['1', '1']);
  });

  test('CCTV search keeps distinct album IDs with the same title', () async {
    final service = FederatedSearchService(cctvApiService: _SameTitleCatalog());
    addTearDown(service.dispose);
    final results = <AggregatedSearchResult>[];

    await service.executeSearch('同名', onUpdate: (items, _) {
      results.addAll(items);
    });

    expect(
      results.map((result) => result.item.id),
      <String>['cctv_album_old', 'cctv_album_remake'],
    );
  });

  test('CCTV search deduplicates albums repeated across categories', () async {
    final service = FederatedSearchService(
      cctvApiService: _SameTitleCatalog(repeatAcrossCategories: true),
    );
    addTearDown(service.dispose);
    final results = <AggregatedSearchResult>[];

    await service.executeSearch('同名', onUpdate: (items, _) {
      results.addAll(items);
    });

    expect(
      results.map((result) => result.item.id),
      <String>['cctv_album_old', 'cctv_album_remake'],
    );
  });
}
