import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/home/presentation/home_page.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/providers/tvbox_provider.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

class _DelayedSpider extends TvBoxSpiderEngine {
  final categories = <String, Completer<List<TvBoxCategory>>>{};

  @override
  Future<List<TvBoxCategory>> fetchSiteCategories(TvBoxSite site) => categories
      .putIfAbsent(site.key, () => Completer<List<TvBoxCategory>>())
      .future;

  @override
  Future<List<MediaItem>> fetchCategoryMedia(
    TvBoxSite site,
    String categoryId, {
    int page = 1,
    int pageSize = 20,
  }) async =>
      <MediaItem>[MediaItem(id: site.key, title: 'Result ${site.key}')];
}

const _oldSite = TvBoxSite(
  key: 'old',
  name: 'Old source',
  type: 1,
  api: 'https://old.test/api.php/provide/vod/',
);
const _newSite = TvBoxSite(
  key: 'new',
  name: 'New source',
  type: 1,
  api: 'https://new.test/api.php/provide/vod/',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('a failed source leaves loading and presents the retry action',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const site = TvBoxSite(
      key: 'bili',
      name: 'Failed source',
      api: 'csp_Bili',
      categories: <TvBoxCategory>[
        TvBoxCategory(id: '纪录片', name: '纪录片'),
      ],
    );

    // Widget tests return HTTP 400 locally; no real source request is sent.
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        activeTvBoxSiteProvider.overrideWith(
          (ref) => ActiveTvBoxSiteNotifier(const <TvBoxSite>[site]),
        ),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('重试刷新'), findsOneWidget);
  });

  testWidgets('a category failure also ends initial loading', (tester) async {
    final spider = _DelayedSpider();
    await _pumpHome(tester, spider);
    spider.categories[_oldSite.key]!.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('重试刷新'), findsOneWidget);
  });

  testWidgets('an old source failure cannot end the new source loading',
      (tester) async {
    final spider = _DelayedSpider();
    final notifier = await _pumpHome(tester, spider);
    notifier.selectSite(_newSite);
    await tester.pump();
    await tester.pump();

    spider.categories[_oldSite.key]!.completeError(StateError('Old failure'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('重试刷新'), findsNothing);

    spider.categories[_newSite.key]!.complete(<TvBoxCategory>[]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Result new'), findsWidgets);
  });
}

Future<ActiveTvBoxSiteNotifier> _pumpHome(
  WidgetTester tester,
  TvBoxSpiderEngine spider,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late ActiveTvBoxSiteNotifier notifier;
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      activeTvBoxSiteProvider.overrideWith((ref) {
        return notifier =
            ActiveTvBoxSiteNotifier(const <TvBoxSite>[_oldSite, _newSite]);
      }),
    ],
    child: MaterialApp(home: HomePage(spiderEngine: spider)),
  ));
  await tester.pump();
  return notifier;
}
