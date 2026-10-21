import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/player/presentation/cctv_official_web_player_page.dart';

const _first = PlaybackEpisode(
  name: '第一集',
  url: 'cctv_guid://first',
  officialPageUrl: 'https://tv.cctv.com/first.html',
);
const _second = PlaybackEpisode(
  name: '第二集',
  url: 'cctv_guid://second',
  officialPageUrl: 'https://tv.cctv.com/second.html',
);

/// Capture the actual scripts passed to WebView2, without a native browser.
class _WebviewHost {
  final scripts = <String>[];
  final urls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('io.jns.webview.win'),
      (call) async => switch (call.method) {
        'getWebViewVersion' => 'test-runtime',
        'initialize' => <String, Object>{'textureId': 991},
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('io.jns.webview.win/991'),
      (call) async {
        if (call.method == 'addScriptToExecuteOnDocumentCreated') {
          scripts.add(call.arguments as String);
          return 'script-${scripts.length}';
        }
        if (call.method == 'loadUrl') urls.add(call.arguments as String);
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('io.jns.webview.win/991/events'),
      (call) async => null,
    );
  }

  Future<void> message(String type, int generation) async {
    await messenger.handlePlatformMessage(
      'io.jns.webview.win/991/events',
      const StandardMethodCodec().encodeSuccessEnvelope(<String, Object>{
        'type': 'webMessageReceived',
        'value': jsonEncode(<String, Object>{
          'type': type,
          'generation': generation,
        }),
      }),
      (_) {},
    );
  }

  double get initialSeconds => double.parse(
        RegExp(r'const initialPosition = ([\d.]+);')
            .firstMatch(scripts.last)!
            .group(1)!,
      );
}

Future<void> _mount(
  WidgetTester tester, {
  bool live = false,
  ValueChanged<PlaybackEpisode>? onEpisodeChanged,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: CctvOfficialWebPlayerPage(
      title: '测试节目',
      currentEpisode: _first,
      episodes: const [_first, _second],
      initialPosition: const Duration(milliseconds: 120500),
      isLive: live,
      onEpisodeChanged: onEpisodeChanged,
    ),
  ));
  for (var index = 0; index < 5; index++) {
    await tester.pump();
  }
}

Future<void> _refresh(
  WidgetTester tester,
  _WebviewHost host,
  int generation,
) async {
  await host.message('juying:unavailable', generation);
  await tester.pump();
  await tester.tap(find.text('刷新'));
  for (var index = 0; index < 3; index++) {
    await tester.pump();
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _WebviewHost host;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    host = _WebviewHost()..install();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('retry keeps pending position and ignores stale acknowledgement',
      (tester) async {
    await _mount(tester);
    expect(host.initialSeconds, 120.5);
    await _refresh(tester, host, 1);
    expect(host.initialSeconds, 120.5);

    await host.message('juying:resume-applied', 1);
    await _refresh(tester, host, 2);
    expect(host.initialSeconds, 120.5);

    await host.message('juying:resume-applied', 3);
    await _refresh(tester, host, 3);
    expect(host.initialSeconds, 0);
    await _unmount(tester);
  });

  testWidgets('switching episodes consumes the original resume position',
      (tester) async {
    final selected = <PlaybackEpisode>[];
    await _mount(tester, onEpisodeChanged: selected.add);
    await host.message('juying:next', 1);
    await tester.pump();
    await tester.pump();
    expect(host.urls.last, _second.officialPageUrl);
    expect(host.initialSeconds, 0);
    expect(selected.last, _second);

    await host.message('juying:previous', 2);
    await tester.pump();
    await tester.pump();
    expect(host.urls.last, _first.officialPageUrl);
    expect(host.initialSeconds, 0);
    await _unmount(tester);
  });

  testWidgets('live streams ignore the initial VOD position', (tester) async {
    await _mount(tester, live: true);
    expect(host.initialSeconds, 0);
    await _unmount(tester);
  });

  testWidgets('user seek cancellation prevents restoration on retry',
      (tester) async {
    await _mount(tester);
    await host.message('juying:resume-cancelled', 1);
    await _refresh(tester, host, 1);
    expect(host.initialSeconds, 0);
    await _unmount(tester);
  });
}
