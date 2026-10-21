import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/home/presentation/home_page.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomePage initializes with pagination and TV focus wrapper',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: HomePage(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('🎬 聚映'), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  test('TvBoxSpiderEngine parses episodes without dollar sign delimiter', () {
    final engine = TvBoxSpiderEngine();
    const site = TvBoxSite(
      key: 'test_cms',
      name: '测试源',
      api: 'https://example.com/api',
    );
    final candidates = engine.parseMacCmsCandidates(site, <String, dynamic>{
      'list': <dynamic>[
        <String, dynamic>{
          'vod_id': '101',
          'vod_name': '测试影视',
          'vod_play_from': '主线路',
          'vod_play_url':
              r'https://example.com/stream1.m3u8#第2集$https://example.com/stream2.m3u8',
        },
      ],
    });

    expect(candidates, isNotEmpty);
    expect(candidates.first.episodes.length, 2);
    expect(candidates.first.episodes[0].name, '播放');
    expect(
        candidates.first.episodes[0].url, 'https://example.com/stream1.m3u8');
    expect(candidates.first.episodes[1].name, '第2集');
    expect(
        candidates.first.episodes[1].url, 'https://example.com/stream2.m3u8');
  });
}
