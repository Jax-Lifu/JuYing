import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/cctv/models/cctv_album.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';
import 'package:juying/features/search/presentation/search_page.dart';
import 'package:juying/features/search/services/federated_search_service.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

class _DelayedCatalog extends CctvApiService {
  final response = Completer<CctvQueryResult>();

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
  }) =>
      response.future;
}

class _EmptyCatalogSearch extends FederatedSearchService {
  @override
  Future<void> executeSearch(
    String query, {
    required void Function(List<AggregatedSearchResult>, int) onUpdate,
  }) async {
    onUpdate(<AggregatedSearchResult>[], 0);
  }
}

class _DelayedSpider extends TvBoxSpiderEngine {
  final requests = <String, Completer<List<MediaItem>>>{};

  @override
  Future<List<MediaItem>> federatedSearch(
    List<TvBoxSite> sites,
    String keyword,
  ) {
    if (keyword == '围棋') return Future.value(<MediaItem>[]);
    return (requests[keyword] = Completer<List<MediaItem>>()).future;
  }
}

const _catalogResult = CctvQueryResult(
  total: 1,
  albums: <CctvAlbum>[
    CctvAlbum(
      id: 'album',
      title: '央视节目',
      posterUrl: '',
      overview: '',
      category: '纪录片',
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new debounced query immediately invalidates an in-flight response',
      () async {
    final catalog = _DelayedCatalog();
    final service = FederatedSearchService(cctvApiService: catalog);
    addTearDown(service.dispose);
    final updates = <int>[];
    final pending = service.executeSearch('A', onUpdate: (_, epoch) {
      updates.add(epoch);
    });
    service.searchDebounced(
      'B',
      debounceDuration: const Duration(days: 1),
      onUpdate: (_, epoch) => updates.add(epoch),
    );
    catalog.response.complete(_catalogResult);
    await pending;
    expect(updates, isEmpty);
  });

  test('disposed search service never publishes an in-flight response',
      () async {
    final catalog = _DelayedCatalog();
    final service = FederatedSearchService(cctvApiService: catalog);
    var updated = false;
    final pending = service.executeSearch('A', onUpdate: (_, __) {
      updated = true;
    });
    service.dispose();
    catalog.response.complete(_catalogResult);
    await pending;
    expect(updated, isFalse);
  });

  test(
      'catalog search leaves episode candidates unresolved for the detail page',
      () async {
    final catalog = _DelayedCatalog();
    final service = FederatedSearchService(cctvApiService: catalog);
    addTearDown(service.dispose);
    catalog.response.complete(_catalogResult);
    final updates = <AggregatedSearchResult>[];
    await service.executeSearch('A', onUpdate: (results, _) {
      updates.addAll(results);
    });
    expect(updates.single.item.id, 'cctv_album_album');
    expect(updates.single.candidates, isEmpty);
  });

  for (final clearQuery in <bool>[false, true]) {
    testWidgets(
      clearQuery
          ? 'clearing input prevents an old spider response from restoring results'
          : 'old spider response cannot overwrite a newer completed search',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final spider = _DelayedSpider();
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: SearchPage(
                searchService: _EmptyCatalogSearch(),
                spiderEngine: spider,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '旧查询');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(spider.requests, contains('旧查询'));
        await tester.enterText(
          find.byType(TextField),
          clearQuery ? '' : '新查询',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        if (!clearQuery) {
          spider.requests['新查询']!.complete(const <MediaItem>[
            MediaItem(id: 'new', title: '新结果'),
          ]);
          await tester.pumpAndSettle();
          expect(find.text('新结果'), findsOneWidget);
        }
        spider.requests['旧查询']!.complete(const <MediaItem>[
          MediaItem(id: 'old', title: '旧结果'),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('旧结果'), findsNothing);
        if (!clearQuery) expect(find.text('新结果'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
