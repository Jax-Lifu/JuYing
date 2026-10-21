import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/history/playback_history_service.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/core/player/player_engine.dart';
import 'package:juying/features/cast/services/dlna_cast_service.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';
import 'package:juying/features/cctv/services/cctv_hls_proxy.dart';
import 'package:juying/features/player/presentation/cctv_official_web_player_page.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';
import 'package:juying/features/player/presentation/web_media_resolver.dart';

class _DelayedCctvService extends CctvApiService {
  final requests = <String, Completer<CctvVodPlayback?>>{};
  int clearRequests = 0;

  @override
  Future<CctvVodPlayback?> resolveCctvGuidPlayback(String guid) {
    clearRequests++;
    return (requests[guid] = Completer<CctvVodPlayback?>()).future;
  }

  @override
  Future<CctvVodPlayback?> resolveCctvGuidHdPlayback(String guid) =>
      (requests[guid] = Completer<CctvVodPlayback?>()).future;
}

class _TestProxy extends CctvHlsProxy {
  _TestProxy({this.delayed = false});

  final bool delayed;
  final opened = <String>[];
  final responses = <Completer<String>>[];
  int disposals = 0;

  @override
  Future<String> open(String mediaPlaylistUrl, {Map<String, String>? headers}) {
    opened.add(mediaPlaylistUrl);
    if (!delayed) {
      return Future.value('http://127.0.0.1:9979/${opened.length}/index.m3u8');
    }
    final response = Completer<String>();
    responses.add(response);
    return response.future;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _RouteObserver extends NavigatorObserver {
  Widget? replacement;
  int replacements = 0;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacements++;
    replacement = (newRoute as MaterialPageRoute).builder(navigator!.context);
  }
}

class _RecordingPlayer extends PlatformPlayer {
  _RecordingPlayer() : super(configuration: const PlayerConfiguration());

  final opened = <String>[];
  int stops = 0;

  void emitPosition(Duration position) => positionController.add(position);

  @override
  Future<void> stop() async {
    stops++;
    emitPosition(Duration.zero);
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((playable as Media).uri);
  }
}

// Video still builds normally; no native texture exists until the controller
// supplies one, so a null notifier is sufficient for coordination tests.
class _BlankVideoController extends Fake implements VideoController {
  _BlankVideoController(this.player);

  @override
  final Player player;

  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
}

class _TestEngine extends Fake implements PlayerEngine {
  _TestEngine(this.player, {bool observeProgress = false})
      : _eventEngine = observeProgress ? PlayerEngine.forTesting(player) : null;

  final PlayerEngine? _eventEngine;

  @override
  final Player player;

  bool disposed = false;
  int playPauseCalls = 0;
  bool failOpen = false;
  @override
  bool get hasStartedPlaying => _eventEngine?.hasStartedPlaying ?? false;
  final startPositions = <Duration?>[];
  final openedHeaders = <Map<String, String>?>[];
  final seeks = <Duration>[];

  @override
  late final VideoController videoController = _BlankVideoController(player);

  @override
  Future<void> openStream(String url,
      {Map<String, String>? headers, Duration? startPosition}) async {
    if (failOpen) throw StateError('decoder failed');
    openedHeaders.add(headers);
    startPositions.add(startPosition);
    if (_eventEngine != null) {
      await _eventEngine.openStream(url,
          headers: headers, startPosition: startPosition);
    } else {
      await player.open(Media(url));
    }
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    (player.platform! as _RecordingPlayer).emitPosition(position);
  }

  @override
  Future<void> playOrPause() async {
    playPauseCalls++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    unawaited(_eventEngine?.dispose() ?? player.dispose());
  }
}

class _TestDlnaService extends DlnaCastService {
  String? castUrl;

  @override
  Future<List<DlnaDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 3),
  }) async =>
      const <DlnaDevice>[
        DlnaDevice(
          id: 'test-tv',
          name: '客厅电视',
          controlUrl: 'http://192.0.2.1/control',
          location: 'http://192.0.2.1/device.xml',
        ),
      ];

  @override
  Future<bool> castVideo({
    required DlnaDevice device,
    required String mediaUrl,
    required String title,
  }) async {
    castUrl = mediaUrl;
    return true;
  }
}

CctvVodPlayback _playback(String id, int minutes) => CctvVodPlayback(
      variants: <CctvStreamVariant>[
        CctvStreamVariant(
          id: id,
          label: id,
          resolution: '1080P',
          bitrateKbps: 2000,
          url: 'https://example.com/$id.m3u8',
        ),
      ],
      duration: Duration(minutes: minutes),
    );

CctvVodPlayback _hdPlayback(String guid) => CctvVodPlayback(
      variants: <CctvStreamVariant>[
        for (final height in <int>[720, 1080])
          CctvStreamVariant(
            id: '$height',
            label: height == 720 ? '高清' : '超清',
            resolution: '${height}P',
            bitrateKbps: 2000,
            url: 'https://example.com/$guid/$height.m3u8',
            isH5e: true,
          ),
      ],
      duration: const Duration(minutes: 40),
    );

const _first = PlaybackEpisode(
  name: '第1集',
  url: 'cctv_guid://old',
  officialPageUrl: 'https://tv.cctv.com/old.shtml',
);
const _second = PlaybackEpisode(
  name: '第2集',
  url: 'cctv_guid://new',
  officialPageUrl: 'https://tv.cctv.com/new.shtml',
  sortIndex: 2,
);

Future<void> _pumpHdPlayer(
  WidgetTester tester, {
  required _TestEngine engine,
  required _DelayedCctvService service,
  required _TestProxy proxy,
  _RouteObserver? observer,
  ValueChanged<PlaybackEpisode>? onEpisodeChanged,
  Duration initialPosition = Duration.zero,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    navigatorObservers: <NavigatorObserver>[if (observer != null) observer],
    home: VideoPlayerPage(
      title: '央视节目',
      currentEpisode: _first,
      initialPosition: initialPosition,
      candidate: const PlaybackCandidate(
        sourceKey: 'cctv',
        sourceName: '央视',
        lineName: '官方',
        episodes: <PlaybackEpisode>[_first, _second],
      ),
      playerEngine: engine,
      cctvApiService: service,
      cctvHlsProxy: proxy,
      onEpisodeChanged: onEpisodeChanged,
    ),
  ));
  await tester.pump();
}

Future<void> _selectSecond(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  await tester.tap(find.text('选集'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('第2集'));
  await tester.pumpAndSettle();
}

Future<void> _unmountPlayer(WidgetTester tester, _TestEngine engine) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  engine.videoController.notifier.dispose();
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('history distinguishes deliberate zero, native stop and progress',
      (tester) async {
    for (final action in <String>['seek zero', 'native stop', 'progress']) {
      const saved = PlaybackHistoryItem(
        id: 'zero_seek',
        title: '归零测试',
        posterUrl: '',
        episodeName: '第1集',
        episodeIndex: 1,
        positionMs: 10000,
        durationMs: 600000,
        timestampMs: 1,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'juying_playback_history': jsonEncode(<Object>[saved.toJson()]),
      });
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform = _RecordingPlayer();
      final engine = _TestEngine(Player(platformPlayer: platform));
      await tester.pumpWidget(MaterialApp(
        home: VideoPlayerPage(
          title: '归零测试',
          mediaId: 'zero_seek',
          currentEpisode: const PlaybackEpisode(
            name: '第1集',
            url: 'https://example.com/video.mp4',
            duration: Duration(minutes: 10),
          ),
          initialPosition: const Duration(seconds: 10),
          playerEngine: engine,
        ),
      ));
      await tester.pump();
      if (action == 'seek zero') {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      } else if (action == 'native stop') {
        await platform.stop();
      } else {
        platform.emitPosition(const Duration(seconds: 20));
      }
      await tester.pump();
      await _unmountPlayer(tester, engine);
      final history = await tester
          .runAsync(() => PlaybackHistoryService.instance.getHistory());
      expect(
          history!.single.positionMs,
          switch (action) {
            'seek zero' => 0,
            'native stop' => 10000,
            _ => 20000,
          },
          reason: action);
      if (action == 'seek zero') expect(engine.seeks.single, Duration.zero);
    }
  });

  for (final scenario in <String>[
    'matching',
    'different',
    'equivalent number'
  ]) {
    final sameEpisode = scenario != 'different';
    testWidgets('manual candidate switch handles $scenario episode progress',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const current = PlaybackEpisode(
        name: '第20集',
        url: 'https://example.com/old20.mp4',
        sortIndex: 20,
        duration: Duration(minutes: 40),
      );
      final target = PlaybackEpisode(
        name: scenario == 'equivalent number'
            ? '第 020 集'
            : sameEpisode
                ? '第20集'
                : '第1集',
        url: 'https://example.com/new.mp4',
        sortIndex: sameEpisode ? 20 : 1,
        duration: Duration(minutes: sameEpisode ? 40 : 10),
      );
      final candidates = <PlaybackCandidate>[
        const PlaybackCandidate(
          sourceKey: 'old',
          sourceName: '原来源',
          lineName: '原线路',
          episodes: <PlaybackEpisode>[current],
        ),
        PlaybackCandidate(
          sourceKey: 'new',
          sourceName: '新来源',
          lineName: '新线路',
          episodes: <PlaybackEpisode>[
            if (scenario == 'equivalent number')
              const PlaybackEpisode(
                name: '第1集',
                url: 'https://example.com/wrong1.mp4',
              ),
            target,
          ],
        ),
      ];
      final platform = _RecordingPlayer();
      final engine = _TestEngine(Player(platformPlayer: platform));
      final changed = <PlaybackEpisode>[];
      await tester.pumpWidget(MaterialApp(
        home: VideoPlayerPage(
          title: '节目',
          currentEpisode: current,
          initialPosition: const Duration(minutes: 5),
          candidate: candidates.first,
          allCandidates: candidates,
          playerEngine: engine,
          onEpisodeChanged: changed.add,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('换源 (1/2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新来源 · 新线路'));
      await tester.pumpAndSettle();
      final opened = platform.opened.last;
      final start = engine.startPositions.last;
      final displayedDuration =
          find.text(sameEpisode ? '40:00' : '10:00').evaluate().length;
      final displayedPosition =
          find.text(sameEpisode ? '05:00' : '00:00').evaluate().length;
      await _unmountPlayer(tester, engine);

      expect(opened, target.url);
      expect(start, sameEpisode ? const Duration(minutes: 5) : Duration.zero);
      expect(displayedDuration, 1);
      expect(displayedPosition, 1);
      expect(changed, sameEpisode ? isEmpty : <PlaybackEpisode>[target]);
    });
  }

  for (final scenario in <String>['matching', 'missing', 'equivalent number']) {
    final hasMatchingLine = scenario != 'missing';
    testWidgets('automatic candidate switch handles $scenario episode lines',
        (tester) async {
      const current = PlaybackEpisode(
        name: '第20集',
        url: 'https://example.com/current20.mp4',
        sortIndex: 1,
        duration: Duration(minutes: 40),
      );
      const different = PlaybackEpisode(
        name: '第1集',
        url: 'https://example.com/wrong1.mp4',
        sortIndex: 1,
        duration: Duration(minutes: 10),
      );
      final matching = PlaybackEpisode(
        name: scenario == 'equivalent number' ? '第 020 集' : '第20集',
        url: 'https://example.com/matching20.mp4',
        sortIndex: 20,
        duration: const Duration(minutes: 40),
      );
      final candidates = <PlaybackCandidate>[
        const PlaybackCandidate(
          sourceKey: 'current',
          sourceName: '当前',
          lineName: '一',
          episodes: <PlaybackEpisode>[current],
        ),
        const PlaybackCandidate(
          sourceKey: 'missing',
          sourceName: '缺集',
          lineName: '二',
          episodes: <PlaybackEpisode>[different],
        ),
        if (hasMatchingLine)
          PlaybackCandidate(
            sourceKey: 'matching',
            sourceName: '同集',
            lineName: '三',
            episodes: <PlaybackEpisode>[matching],
          ),
      ];
      final platform = _RecordingPlayer();
      final engine = _TestEngine(Player(platformPlayer: platform));
      final proxy = _TestProxy();
      final changed = <PlaybackEpisode>[];
      await tester.pumpWidget(MaterialApp(
        home: VideoPlayerPage(
          title: '节目',
          currentEpisode: current,
          initialPosition: const Duration(minutes: 5),
          candidate: candidates.first,
          allCandidates: candidates,
          playerEngine: engine,
          cctvHlsProxy: proxy,
          onEpisodeChanged: changed.add,
        ),
      ));
      await tester.pump();
      proxy.onError!(StateError('current line failed'));
      await tester.pump();
      await tester.pump();
      final opened = List<String>.of(platform.opened);
      final start = engine.startPositions.last;
      final fatal = find.text('所有播放源均连接失败，请尝试其他影视或检查网络').evaluate().length;
      await _unmountPlayer(tester, engine);

      expect(opened, <String>[current.url, if (hasMatchingLine) matching.url]);
      expect(start, const Duration(minutes: 5));
      expect(fatal, hasMatchingLine ? 0 : 1);
      expect(changed, isEmpty);
    });
  }

  for (final progress in <String>['none', 'resume offset', 'advancing']) {
    testWidgets('candidate retry budget respects $progress progress',
        (tester) async {
      final platform = _RecordingPlayer();
      final engine =
          _TestEngine(Player(platformPlayer: platform), observeProgress: true);
      final proxy = _TestProxy();
      final candidates = <PlaybackCandidate>[
        for (final source in <String>['first', 'second'])
          PlaybackCandidate(
            sourceKey: source,
            sourceName: source,
            lineName: source,
            episodes: <PlaybackEpisode>[
              PlaybackEpisode(
                name: '正片',
                url: 'https://example.com/$source.mp4',
              ),
            ],
          ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: VideoPlayerPage(
          title: '失败线路',
          currentEpisode: candidates.first.episodes.first,
          candidate: candidates.first,
          allCandidates: candidates,
          playerEngine: engine,
          cctvHlsProxy: proxy,
        ),
      ));
      await tester.pump();
      if (progress != 'none') {
        platform.emitPosition(const Duration(seconds: 90));
        await tester.pump();
        expect(engine.hasStartedPlaying, isTrue);
        for (var attempt = 0; attempt < 3; attempt++) {
          proxy.onError!(StateError('media failed after open'));
          await tester.pump();
          await tester.pump();
          platform.emitPosition(const Duration(seconds: 90));
          await tester.pump();
          expect(engine.hasStartedPlaying, isFalse);
        }
        expect(engine.startPositions.last, const Duration(seconds: 90));
        if (progress == 'advancing') {
          platform.emitPosition(const Duration(milliseconds: 90200));
          await tester.pump();
          expect(engine.hasStartedPlaying, isTrue);
        }
      }
      final previousOpens = platform.opened.length;
      final remainingFailures = progress == 'resume offset' ? 1 : 4;
      for (var attempt = 0; attempt < remainingFailures; attempt++) {
        proxy.onError!(StateError('media failed after open'));
        await tester.pump();
        await tester.pump();
        if (attempt < remainingFailures - 1) {
          expect(find.text('所有播放源均连接失败，请尝试其他影视或检查网络'), findsNothing);
        }
      }
      expect(platform.opened, hasLength(previousOpens + remainingFailures - 1));
      expect(find.text('所有播放源均连接失败，请尝试其他影视或检查网络'), findsOneWidget);
      await tester.tap(find.text('重试播放'));
      await tester.pump();
      await tester.pump();
      proxy.onError!(StateError('media failed after explicit retry'));
      await tester.pump();
      await tester.pump();
      expect(platform.opened, hasLength(previousOpens + remainingFailures + 1));
      expect(find.text('所有播放源均连接失败，请尝试其他影视或检查网络'), findsNothing);
      await _unmountPlayer(tester, engine);
    });
  }

  testWidgets(
      'native resume reaches the engine and resets when changing episode',
      (tester) async {
    final engine = _TestEngine(Player(platformPlayer: _RecordingPlayer()));
    final service = _DelayedCctvService();
    await _pumpHdPlayer(tester,
        engine: engine,
        service: service,
        proxy: _TestProxy(),
        initialPosition: const Duration(milliseconds: 90500));
    service.requests['old']!.complete(_hdPlayback('old'));
    await tester.pump();
    await tester.pump();
    expect(engine.startPositions.single, const Duration(milliseconds: 90500));
    expect(find.text('01:30'), findsOneWidget);
    await _selectSecond(tester);
    service.requests['new']!.complete(_hdPlayback('new'));
    await tester.pump();
    await tester.pump();
    expect(engine.startPositions.last, Duration.zero);
    await _unmountPlayer(tester, engine);
  });

  testWidgets('native live playback ignores a VOD resume offset',
      (tester) async {
    final engine = _TestEngine(Player(platformPlayer: _RecordingPlayer()));
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: '直播',
        currentEpisode: const PlaybackEpisode(
            name: '直播', url: 'https://example.com/live.m3u8'),
        isLive: true,
        initialPosition: const Duration(minutes: 3),
        playerEngine: engine,
      ),
    ));
    await tester.pump();
    expect(engine.startPositions.single, isNull);
    expect(find.text('00:00'), findsWidgets);
    await _unmountPlayer(tester, engine);
  });

  testWidgets('Spider resolves only the selected episode and keeps headers',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _RecordingPlayer();
    final engine = _TestEngine(Player(platformPlayer: platform));
    final pending = Completer<PlaybackEpisode>();
    var requests = 0;
    final episode = PlaybackEpisode(
      name: '第1集',
      url: 'opaque-play-id',
      resolvePlayback: () {
        requests++;
        return pending.future;
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: 'Spider',
        currentEpisode: episode,
        playerEngine: engine,
      ),
    ));
    await tester.pump();
    expect(requests, 1);
    expect(platform.opened, isEmpty);
    pending.complete(const PlaybackEpisode(
      name: '第1集',
      url: 'https://example.com/video.m3u8',
      headers: <String, String>{'Referer': 'https://example.com/player'},
    ));
    await tester.pump();
    await tester.pump();
    expect(platform.opened.single, 'https://example.com/video.m3u8');
    expect(
        engine.openedHeaders.single!['Referer'], 'https://example.com/player');
    await _unmountPlayer(tester, engine);
  });

  testWidgets('disposing during Spider resolution prevents late playback',
      (tester) async {
    final platform = _RecordingPlayer();
    final engine = _TestEngine(Player(platformPlayer: platform));
    final pending = Completer<PlaybackEpisode>();
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: 'Spider',
        currentEpisode: PlaybackEpisode(
          name: '正片',
          url: 'opaque-id',
          resolvePlayback: () => pending.future,
        ),
        playerEngine: engine,
      ),
    ));
    await tester.pump();
    await _unmountPlayer(tester, engine);
    pending.complete(const PlaybackEpisode(
      name: '正片',
      url: 'https://example.com/late.mp4',
    ));
    await tester.pump();
    expect(platform.opened, isEmpty);
  });

  testWidgets('Spider parser result reaches native player with media headers',
      (tester) async {
    final platform = _RecordingPlayer();
    final engine = _TestEngine(Player(platformPlayer: platform));
    final pending = Completer<PlaybackEpisode>();
    PlaybackEpisode? requested;
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: 'Spider',
        currentEpisode: const PlaybackEpisode(
          name: '正片',
          url: 'https://example.com/watch/1',
          requiresWebView: true,
        ),
        playerEngine: engine,
        webMediaResolver: (_, episode) {
          requested = episode;
          return pending.future;
        },
      ),
    ));
    await tester.pump();
    expect(requested!.url, 'https://example.com/watch/1');
    expect(platform.opened, isEmpty);
    pending.complete(const PlaybackEpisode(
      name: '正片',
      url: 'https://cdn.example.com/stream.m3u8',
      headers: <String, String>{'Referer': 'https://example.com/watch/1'},
    ));
    await tester.pump();
    await tester.pump();
    expect(platform.opened.single, 'https://cdn.example.com/stream.m3u8');
    expect(
        engine.openedHeaders.single!['Referer'], 'https://example.com/watch/1');
    await _unmountPlayer(tester, engine);
  });

  testWidgets('late browser resolution cannot reopen a disposed player',
      (tester) async {
    final platform = _RecordingPlayer();
    final engine = _TestEngine(Player(platformPlayer: platform));
    final pending = Completer<PlaybackEpisode>();
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: 'Spider',
        currentEpisode: const PlaybackEpisode(
          name: '正片',
          url: 'https://example.com/watch/1',
          requiresWebView: true,
        ),
        playerEngine: engine,
        webMediaResolver: (_, __) => pending.future,
      ),
    ));
    await tester.pump();
    await _unmountPlayer(tester, engine);
    pending.complete(const PlaybackEpisode(
      name: '正片',
      url: 'https://example.com/late.mp4',
    ));
    await tester.pump();
    expect(platform.opened, isEmpty);
  });

  testWidgets('failed Spider resolution advances to the next candidate',
      (tester) async {
    final platform = _RecordingPlayer();
    final engine = _TestEngine(Player(platformPlayer: platform));
    final pending = Completer<PlaybackEpisode>();
    final first = PlaybackEpisode(
      name: '正片',
      url: 'first-id',
      resolvePlayback: () => pending.future,
    );
    final candidates = <PlaybackCandidate>[
      PlaybackCandidate(
        sourceKey: 'first',
        sourceName: '第一源',
        lineName: '一',
        episodes: <PlaybackEpisode>[first],
      ),
      const PlaybackCandidate(
        sourceKey: 'second',
        sourceName: '第二源',
        lineName: '二',
        episodes: <PlaybackEpisode>[
          PlaybackEpisode(name: '正片', url: 'https://example.com/second.mp4'),
        ],
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: 'Spider',
        currentEpisode: first,
        allCandidates: candidates,
        candidate: candidates.first,
        playerEngine: engine,
      ),
    ));
    await tester.pump();
    pending.completeError(StateError('player API unavailable'));
    await tester.pump();
    await tester.pump();
    expect(platform.opened.single, 'https://example.com/second.mp4');
    await _unmountPlayer(tester, engine);
  });

  testWidgets('cancelling browser resolution does not retry another candidate',
      (tester) async {
    final platform = _RecordingPlayer();
    final engine = _TestEngine(Player(platformPlayer: platform));
    var requests = 0;
    const episode = PlaybackEpisode(
        name: '正片',
        url: 'https://example.com/player.html',
        requiresWebView: true);
    final pending = Completer<PlaybackEpisode>();
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerPage(
      title: 'Spider',
      currentEpisode: episode,
      playerEngine: engine,
      allCandidates: const <PlaybackCandidate>[
        PlaybackCandidate(
            sourceKey: 'one',
            sourceName: '一',
            lineName: '一',
            episodes: [episode]),
        PlaybackCandidate(
            sourceKey: 'two',
            sourceName: '二',
            lineName: '二',
            episodes: [episode]),
      ],
      webMediaResolver: (_, __) {
        requests++;
        return pending.future;
      },
    )));
    await tester.pump();
    pending.completeError(const WebMediaResolutionCancelled());
    await tester.pump();
    await tester.pump();
    expect(requests, 1);
    expect(platform.opened, isEmpty);
    await _unmountPlayer(tester, engine);
  });

  testWidgets(
      'Windows HD uses local full HLS, seeks and preserves quality position',
      (tester) async {
    final platform = _RecordingPlayer();
    final engine = _TestEngine(Player(platformPlayer: platform));
    final service = _DelayedCctvService();
    final proxy = _TestProxy();
    PlaybackEpisode? selected;
    await _pumpHdPlayer(tester,
        engine: engine,
        service: service,
        proxy: proxy,
        onEpisodeChanged: (episode) => selected = episode);
    service.requests['old']!.complete(_hdPlayback('old'));
    await tester.pump();
    await tester.pump();
    expect(platform.opened.single, 'http://127.0.0.1:9979/1/index.m3u8');
    expect(find.text('40:00'), findsOneWidget);

    tester.widget<Slider>(find.byType(Slider)).onChanged!(0.5);
    await tester.pump();
    expect(engine.seeks.single, const Duration(minutes: 20));
    await tester.tap(find.text('高清 · 720P'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('超清 · 1080P'));
    await tester.pumpAndSettle();
    service.requests['old']!.complete(_hdPlayback('old'));
    await tester.pump();
    await tester.pump();
    expect(proxy.opened.last, 'https://example.com/old/1080.m3u8');
    expect(engine.startPositions.last, const Duration(minutes: 20));

    await _selectSecond(tester);
    service.requests['new']!.complete(_hdPlayback('new'));
    await tester.pump();
    await tester.pump();
    expect(selected, same(_second));
    expect(proxy.opened.last, 'https://example.com/new/720.m3u8');
    expect(engine.startPositions.last, Duration.zero);
    expect(service.clearRequests, 0);
    expect(platform.stops, 3);
    await tester.tap(find.byIcon(Icons.cast));
    await tester.pump();
    expect(find.text('央视原生高清暂不支持投屏'), findsOneWidget);
    expect(find.text('DLNA / UPnP 无线投屏'), findsNothing);
    await _unmountPlayer(tester, engine);
    expect(proxy.disposals, 1);
  });

  for (final stage in <String>['resolution', 'proxy']) {
    testWidgets('late HD $stage cannot replace the current episode',
        (tester) async {
      final platform = _RecordingPlayer();
      final engine = _TestEngine(Player(platformPlayer: platform));
      final service = _DelayedCctvService();
      final proxy = _TestProxy(delayed: stage == 'proxy');
      await _pumpHdPlayer(tester,
          engine: engine, service: service, proxy: proxy);
      final old = service.requests['old']!;
      if (stage == 'proxy') {
        old.complete(_hdPlayback('old'));
        await tester.pump();
      }
      await _selectSecond(tester);
      service.requests['new']!.complete(_hdPlayback('new'));
      await tester.pump();
      if (stage == 'proxy') {
        proxy.responses.last.complete('http://127.0.0.1/new/index.m3u8');
        await tester.pump();
        proxy.responses.first.complete('http://127.0.0.1/old/index.m3u8');
      } else {
        old.complete(_hdPlayback('old'));
      }
      await tester.pump();
      await tester.pump();
      expect(platform.opened, hasLength(1));
      expect(proxy.opened.last, 'https://example.com/new/720.m3u8');
      expect(proxy.disposals, 0);
      expect(find.text('央视节目 - 第2集'), findsOneWidget);
      await _unmountPlayer(tester, engine);
    });

    testWidgets('disposing during HD $stage prevents a late player open',
        (tester) async {
      final platform = _RecordingPlayer();
      final engine = _TestEngine(Player(platformPlayer: platform));
      final service = _DelayedCctvService();
      final proxy = _TestProxy(delayed: stage == 'proxy');
      await _pumpHdPlayer(tester,
          engine: engine, service: service, proxy: proxy);
      if (stage == 'proxy') {
        service.requests['old']!.complete(_hdPlayback('old'));
        await tester.pump();
      }
      await _unmountPlayer(tester, engine);
      if (stage == 'proxy') {
        proxy.responses.single.complete('http://127.0.0.1/old/index.m3u8');
      } else {
        service.requests['old']!.complete(_hdPlayback('old'));
      }
      await tester.pump();
      expect(platform.opened, isEmpty);
      expect(engine.disposed, isTrue);
      expect(proxy.disposals, 1);
      expect(proxy.onError, isNull);
    });
  }

  for (final trigger in <String>[
    'no HD',
    'decoder',
    'proxy',
    'manual',
    'manual from zero',
    'pending manual',
  ]) {
    testWidgets(
        '$trigger fallback replaces native with the active official episode',
        (tester) async {
      final platform = _RecordingPlayer();
      final engine = _TestEngine(Player(platformPlayer: platform));
      final service = _DelayedCctvService();
      final proxy = _TestProxy();
      final observer = _RouteObserver();
      PlaybackEpisode? selected;
      await _pumpHdPlayer(tester,
          engine: engine,
          service: service,
          proxy: proxy,
          observer: observer,
          onEpisodeChanged: (episode) => selected = episode);
      service.requests['old']!.complete(_hdPlayback('old'));
      await tester.pump();
      await tester.pump();
      platform.emitPosition(const Duration(seconds: 94));
      await tester.pump();
      await _selectSecond(tester);
      // A queued event from the previous native stream must not seed the
      // next episode while its VDN request is still unresolved.
      platform.emitPosition(const Duration(seconds: 181));
      await tester.pump();
      engine.failOpen = trigger == 'decoder';
      if (trigger != 'pending manual') {
        service.requests['new']!
            .complete(trigger == 'no HD' ? null : _hdPlayback('new'));
      }
      await tester.pump();
      if (trigger == 'proxy' || trigger.startsWith('manual')) {
        platform.emitPosition(const Duration(milliseconds: 135500));
        await tester.pump();
      }
      if (trigger == 'proxy') {
        // Native failure/stop notifications may reset the public position
        // before the proxy error reaches the page.
        platform.emitPosition(Duration.zero);
        await tester.pump();
        proxy.onError!(StateError('segment failed'));
        proxy.onError!(StateError('duplicate segment failure'));
      } else if (trigger.contains('manual')) {
        if (trigger == 'manual from zero') {
          tester.widget<Slider>(find.byType(Slider)).onChanged!(0);
          await tester.pump();
          expect(engine.seeks.single, Duration.zero);
        }
        await tester.tap(find.text('官方播放器'));
      }
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      for (var i = 0; i < 5 && observer.replacements == 0; i++) {
        await tester.pump();
      }
      expect(observer.replacements, 1);
      final fallback = observer.replacement! as CctvOfficialWebPlayerPage;
      expect(fallback.currentEpisode, same(_second));
      expect(fallback.episodes, <PlaybackEpisode>[_first, _second]);
      expect(
        fallback.initialPosition,
        trigger == 'proxy' || trigger == 'manual'
            ? const Duration(milliseconds: 135500)
            : Duration.zero,
      );
      fallback.onEpisodeChanged!(_first);
      expect(selected, same(_first));
      expect(service.clearRequests, 0);
      expect(engine.disposed, isTrue);
      expect(proxy.disposals, 1);
      if (trigger == 'pending manual') {
        service.requests['new']!.complete(_hdPlayback('new'));
        await tester.pump();
        expect(platform.opened, hasLength(1));
      }
      await _unmountPlayer(tester, engine);
    });
  }

  testWidgets('quality failure resumes the same episode before native stop',
      (tester) async {
    final platform = _RecordingPlayer();
    final engine = _TestEngine(Player(platformPlayer: platform));
    final service = _DelayedCctvService();
    final proxy = _TestProxy();
    final observer = _RouteObserver();
    await _pumpHdPlayer(tester,
        engine: engine, service: service, proxy: proxy, observer: observer);
    service.requests['old']!.complete(_hdPlayback('old'));
    await tester.pump();
    await tester.pump();
    platform.emitPosition(const Duration(milliseconds: 90500));
    await tester.pump();
    await tester.tap(find.text('高清 · 720P'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('超清 · 1080P'));
    await tester.pumpAndSettle();
    service.requests['old']!.complete(null);
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 5 && observer.replacements == 0; i++) {
      await tester.pump();
    }

    expect(observer.replacements, 1);
    final fallback = observer.replacement! as CctvOfficialWebPlayerPage;
    expect(fallback.currentEpisode, same(_first));
    expect(fallback.initialPosition, const Duration(milliseconds: 90500));
    expect(platform.stops, 2);
    await _unmountPlayer(tester, engine);
  });

  testWidgets('casting closes only the sheet and keeps local playback usable',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _RecordingPlayer();
    final engine = _TestEngine(Player(platformPlayer: platform));
    final castService = _TestDlnaService();
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: '测试影片',
        currentEpisode: const PlaybackEpisode(
          name: '正片',
          url: 'https://example.com/movie.mp4',
        ),
        playerEngine: engine,
        dlnaCastService: castService,
      ),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.cast));
    await tester.pumpAndSettle();
    await tester.tap(find.text('客厅电视'));
    await tester.pumpAndSettle();

    expect(castService.castUrl, 'https://example.com/movie.mp4');
    expect(find.text('DLNA / UPnP 无线投屏'), findsNothing);
    expect(find.byType(VideoPlayerPage), findsOneWidget);
    expect(engine.disposed, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.playPauseCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    engine.videoController.notifier.dispose();
  });

  testWidgets('late CCTV resolution cannot replace a newer episode metadata',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _DelayedCctvService();
    final platform = _RecordingPlayer();
    final engine = _TestEngine(Player(platformPlayer: platform));
    const first = PlaybackEpisode(name: '第1集', url: 'cctv_guid://old');
    const second = PlaybackEpisode(
      name: '第2集',
      url: 'cctv_guid://new',
      sortIndex: 2,
    );
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerPage(
        title: '央视节目',
        currentEpisode: first,
        candidate: const PlaybackCandidate(
          sourceKey: 'cctv',
          sourceName: '央视',
          lineName: '官方',
          episodes: <PlaybackEpisode>[first, second],
        ),
        playerEngine: engine,
        cctvApiService: service,
      ),
    ));
    expect(service.requests, contains('old'));

    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第2集'));
    await tester.pumpAndSettle();
    service.requests['new']!.complete(_playback('新清晰度', 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('新清晰度 · 1080P'), findsOneWidget);
    expect(find.text('40:00'), findsOneWidget);

    service.requests['old']!.complete(_playback('旧清晰度', 20));
    await tester.pump();
    await tester.pump();
    expect(find.text('新清晰度 · 1080P'), findsOneWidget);
    expect(find.text('40:00'), findsOneWidget);
    expect(find.text('旧清晰度 · 1080P'), findsNothing);
    expect(platform.opened, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    engine.videoController.notifier.dispose();
  });
}
