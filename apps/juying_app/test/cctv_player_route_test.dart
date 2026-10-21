import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/history/playback_history_service.dart';
import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/detail/presentation/video_detail_page.dart';
import 'package:juying/features/player/presentation/cctv_official_web_player_page.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';

class _PlayerRouteObserver extends NavigatorObserver {
  Widget? destination;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null && route is MaterialPageRoute) {
      // Inspect the actual route builder before platform textures/controllers
      // are mounted; these tests cover routing rather than media decoding.
      destination = route.builder(navigator!.context);
    }
  }
}

void main() {
  for (final scenario in <String>[
    'reordered',
    'equivalent number',
    'missing episode',
    'different named content',
    'unnamed legacy episode',
  ]) {
    testWidgets('detail history identity handles $scenario', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final historyName = switch (scenario) {
        'different named content' => '正片',
        'unnamed legacy episode' => '',
        _ => '第2集',
      };
      final episode = PlaybackEpisode(
        name: switch (scenario) {
          'equivalent number' => '第 002 集',
          'missing episode' => '第1集',
          'different named content' => '预告',
          'unnamed legacy episode' => '',
          _ => '第2集',
        },
        sortIndex:
            scenario == 'reordered' || scenario == 'equivalent number' ? 1 : 2,
        url: 'https://example.com/selected.mp4',
        duration: const Duration(minutes: 10),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'juying_playback_history': jsonEncode(<Map<String, Object>>[
          <String, Object>{
            'id': 'identity_test',
            'title': '测试剧',
            'posterUrl': '',
            'episodeName': historyName,
            'episodeIndex': 2,
            'positionMs': 90000,
            'durationMs': 600000,
            'timestampMs': 1,
          },
        ]),
      });
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final observer = _PlayerRouteObserver();
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          navigatorObservers: <NavigatorObserver>[observer],
          home: VideoDetailPage(
            mediaItem: const MediaItem(id: 'identity_test', title: '测试剧'),
            candidates: <PlaybackCandidate>[
              PlaybackCandidate(
                sourceKey: 'new_order',
                sourceName: '新来源',
                lineName: '主线',
                episodes: <PlaybackEpisode>[
                  episode,
                  if (episode.sortIndex == 1)
                    const PlaybackEpisode(
                      name: '第1集',
                      sortIndex: 2,
                      url: 'https://example.com/other.mp4',
                      duration: Duration(minutes: 10),
                    ),
                ],
              ),
            ],
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.textContaining('继续播放')));
      final destination = observer.destination! as VideoPlayerPage;
      final missing = scenario == 'missing episode' ||
          scenario == 'different named content';
      expect(destination.currentEpisode, same(episode));
      expect(destination.initialPosition,
          missing ? Duration.zero : const Duration(seconds: 90));
      await tester.idle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      debugDefaultTargetPlatformOverride = null;
    });
  }

  final resumeCases = <({
    String name,
    TargetPlatform platform,
    int positionMs,
    int durationMs,
    int episodeIndex,
    bool selectEpisode,
    int expectedMs,
  })>[
    (
      name: 'native',
      platform: TargetPlatform.windows,
      positionMs: 90500,
      durationMs: 600000,
      episodeIndex: 1,
      selectEpisode: false,
      expectedMs: 90500
    ),
    (
      name: 'official',
      platform: TargetPlatform.android,
      positionMs: 90500,
      durationMs: 600000,
      episodeIndex: 1,
      selectEpisode: false,
      expectedMs: 90500
    ),
    (
      name: 'completed',
      platform: TargetPlatform.windows,
      positionMs: 600000,
      durationMs: 600000,
      episodeIndex: 1,
      selectEpisode: false,
      expectedMs: 0
    ),
    (
      name: 'unknown duration',
      platform: TargetPlatform.windows,
      positionMs: 90500,
      durationMs: 0,
      episodeIndex: 1,
      selectEpisode: false,
      expectedMs: 0
    ),
    (
      name: 'missing episode',
      platform: TargetPlatform.windows,
      positionMs: 90500,
      durationMs: 600000,
      episodeIndex: 2,
      selectEpisode: false,
      expectedMs: 0
    ),
    (
      name: 'explicit episode selection',
      platform: TargetPlatform.windows,
      positionMs: 90500,
      durationMs: 600000,
      episodeIndex: 1,
      selectEpisode: true,
      expectedMs: 0
    ),
  ];
  for (final scenario in resumeCases) {
    testWidgets('detail resume respects ${scenario.name}', (tester) async {
      debugDefaultTargetPlatformOverride = scenario.platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'juying_playback_history': jsonEncode(<Map<String, Object>>[
          <String, Object>{
            'id': 'cctv_album_test',
            'title': '央视节目',
            'posterUrl': '',
            'episodeName': '第${scenario.episodeIndex}集',
            'episodeIndex': scenario.episodeIndex,
            'positionMs': scenario.positionMs,
            'durationMs': scenario.durationMs,
            'timestampMs': 1,
          },
        ]),
      });
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const episode = PlaybackEpisode(
        name: '第1集',
        url: 'cctv_guid://test',
        officialPageUrl: 'https://tv.cctv.com/test.shtml',
      );
      final observer = _PlayerRouteObserver();
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          navigatorObservers: <NavigatorObserver>[observer],
          home: const VideoDetailPage(
            mediaItem: MediaItem(id: 'cctv_album_test', title: '央视节目'),
            candidates: <PlaybackCandidate>[
              PlaybackCandidate(
                sourceKey: 'cctv',
                sourceName: '央视',
                lineName: '官方',
                episodes: <PlaybackEpisode>[episode],
              ),
            ],
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(scenario.selectEpisode
          ? find.text('第1集').last
          : find.text('继续播放 第1集')));
      final destination = observer.destination!;
      final position = destination is VideoPlayerPage
          ? destination.initialPosition
          : (destination as CctvOfficialWebPlayerPage).initialPosition;
      expect(position.inMilliseconds, scenario.expectedMs);
      await tester.idle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('returning from playback refreshes the next resume position',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final observer = _PlayerRouteObserver();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: const VideoDetailPage(
          mediaItem: MediaItem(id: 'cctv_album_test', title: '央视节目'),
          candidates: <PlaybackCandidate>[
            PlaybackCandidate(
              sourceKey: 'cctv',
              sourceName: '央视',
              lineName: '官方',
              episodes: <PlaybackEpisode>[
                PlaybackEpisode(name: '第1集', url: 'cctv_guid://test'),
              ],
            ),
          ],
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('第1集').last));
    await tester.idle();
    await tester.runAsync(() => PlaybackHistoryService.instance.saveHistory(
          const PlaybackHistoryItem(
            id: 'cctv_album_test',
            title: '央视节目',
            posterUrl: '',
            episodeName: '第1集',
            episodeIndex: 1,
            positionMs: 180000,
            durationMs: 600000,
            timestampMs: 2,
          ),
        ));
    observer.navigator!.pop();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('继续播放 第1集')));
    expect((observer.destination! as VideoPlayerPage).initialPosition,
        const Duration(minutes: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.android,
  ]) {
    testWidgets('CCTV detail chooses the supported player on ${platform.name}',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const episode = PlaybackEpisode(
        name: '第1集',
        url: 'cctv_guid://test',
        officialPageUrl: 'https://tv.cctv.com/test.shtml',
      );
      const candidate = PlaybackCandidate(
        sourceKey: 'cctv',
        sourceName: '央视',
        lineName: '官方',
        episodes: <PlaybackEpisode>[episode],
      );
      final observer = _PlayerRouteObserver();
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          navigatorObservers: <NavigatorObserver>[observer],
          home: const VideoDetailPage(
            mediaItem: MediaItem(id: 'cctv_album_test', title: '央视节目'),
            candidates: <PlaybackCandidate>[candidate],
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('第1集').last));
      if (platform == TargetPlatform.windows) {
        final player = observer.destination! as VideoPlayerPage;
        expect(player.currentEpisode, same(episode));
        expect(player.candidate, same(candidate));
      } else {
        final player = observer.destination! as CctvOfficialWebPlayerPage;
        expect(player.currentEpisode, same(episode));
        expect(player.episodes, candidate.episodes);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
