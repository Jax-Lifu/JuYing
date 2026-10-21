import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/player/presentation/web_media_resolver.dart';

const _episode = PlaybackEpisode(
  name: 'Episode 2',
  url: 'https://player.example/watch/2',
  sortIndex: 2,
  duration: Duration(minutes: 24),
  badge: 'HD',
  thumbnailUrl: 'https://player.example/2.jpg',
  requiresWebView: true,
);

class _Host {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final urls = <String>[];
  final scripts = <String>[];
  final userAgents = <String>[];
  Completer<void>? initialization;
  int disposed = 0;
  Object? result;

  void install() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('io.jns.webview.win'),
      (call) async {
        if (call.method == 'initialize') {
          await initialization?.future;
          return <String, Object>{'textureId': 992};
        }
        if (call.method == 'dispose') disposed++;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('io.jns.webview.win/992'),
      (call) async {
        if (call.method == 'loadUrl') urls.add(call.arguments as String);
        if (call.method == 'setUserAgent') {
          userAgents.add(call.arguments as String);
        }
        if (call.method == 'addScriptToExecuteOnDocumentCreated') {
          scripts.add(call.arguments as String);
          return 'script';
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('io.jns.webview.win/992/events'),
      (call) async => null,
    );
  }

  Future<void> message(String url) async {
    await messenger.handlePlatformMessage(
      'io.jns.webview.win/992/events',
      const StandardMethodCodec().encodeSuccessEnvelope(<String, Object>{
        'type': 'webMessageReceived',
        'value': jsonEncode(<String, Object>{
          'type': 'juying:media',
          'url': url,
          'page': 'https://redirect.example/watch/2#play',
          'userAgent': 'Browser UA',
          'cookie': 'must-not-copy=secret',
        }),
      }),
      (_) {},
    );
  }

  Future<void> mount(WidgetTester tester,
      {PlaybackEpisode episode = _episode}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: TextButton(
            onPressed: () {
              unawaited(resolveWebMedia(context, episode).then<void>(
                (value) => result = value,
                onError: (Object error) => result = error,
              ));
            },
            child: const Text('resolve'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('resolve'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }
}

Future<void> _settleClose(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Host host;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    host = _Host()..install();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('media result retains episode metadata and fills missing headers',
      (tester) async {
    await host.mount(tester);
    expect(host.urls, [_episode.url]);
    expect(host.scripts.single, contains('XMLHttpRequest.prototype.open'));
    await host.message('https://cdn.example/master.M3U8?token=short-lived');
    await _settleClose(tester);
    final result = host.result as PlaybackEpisode;
    expect(result.url, 'https://cdn.example/master.M3U8?token=short-lived');
    expect(result.name, _episode.name);
    expect(result.sortIndex, 2);
    expect(result.duration, _episode.duration);
    expect(result.badge, 'HD');
    expect(result.thumbnailUrl, _episode.thumbnailUrl);
    expect(result.requiresWebView, isFalse);
    expect(result.resolvePlayback, isNull);
    expect(result.headers, {
      'User-Agent': 'Browser UA',
      'Referer': 'https://redirect.example/watch/2',
    });
    expect(host.disposed, 1);
    expect(find.byKey(const ValueKey('web-media-cancel')), findsNothing);
  });

  testWidgets('explicit headers win regardless of capitalization',
      (tester) async {
    const headers = {
      'user-agent': 'Source UA',
      'referer': 'https://source.example/',
      'Authorization': 'source authorization',
      'Cookie': 'source cookie',
    };
    await host.mount(tester,
        episode: const PlaybackEpisode(
          name: 'Episode',
          url: 'https://player.example/watch',
          headers: headers,
          requiresWebView: true,
        ));
    await host.message('https://cdn.example/video.mp4');
    await _settleClose(tester);
    expect((host.result as PlaybackEpisode).headers, headers);
    expect(host.disposed, 1);
  });

  testWidgets('parser navigation headers stay separate from media credentials',
      (tester) async {
    await host.mount(tester,
        episode: const PlaybackEpisode(
          name: 'Episode',
          url: 'https://parser.example/watch',
          headers: {'User-Agent': 'Media UA', 'Cookie': 'media session'},
          webHeaders: {'User-Agent': 'Parser UA', 'Cookie': 'parser session'},
          requiresWebView: true,
        ));
    expect(host.userAgents, ['Parser UA']);
    await host.message('https://cdn.example/video.mp4');
    await _settleClose(tester);
    final media = host.result as PlaybackEpisode;
    expect(media.headers?['User-Agent'], 'Media UA');
    expect(media.headers?['Cookie'], 'media session');
    expect(media.webHeaders, isNull);
  });

  testWidgets('blobs, segments, and player URLs never become media results',
      (tester) async {
    await host.mount(tester);
    for (final url in [
      'blob:https://player.example/video',
      'file:///video.mp4',
      'https://cdn.example/0001.ts',
      'https://cdn.example/0001.m4s',
      'https://player.example/play?url=https://cdn.example/video.m3u8',
    ]) {
      await host.message(url);
    }
    expect(host.result, isNull);
    await tester.pump(const Duration(seconds: 12));
    await _settleClose(tester);
    expect(host.result, isA<TimeoutException>());
    expect(host.disposed, 1);
  });

  testWidgets('cancel releases the browser without a playback result',
      (tester) async {
    await host.mount(tester);
    await tester.tap(find.byKey(const ValueKey('web-media-cancel')));
    await _settleClose(tester);
    expect(host.result, isA<WebMediaResolutionCancelled>());
    expect(host.disposed, 1);
  });

  testWidgets('cancel during native initialization prevents the eventual load',
      (tester) async {
    host.initialization = Completer<void>();
    await host.mount(tester);
    await tester.tap(find.byKey(const ValueKey('web-media-cancel')));
    await _settleClose(tester);
    expect(host.result, isA<WebMediaResolutionCancelled>());
    host.initialization!.complete();
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(host.urls, isEmpty);
    expect(host.disposed, 1);
  });

  testWidgets('late media after Back cannot pop the underlying page',
      (tester) async {
    await host.mount(tester);
    final dialogContext = tester.element(find.byType(AlertDialog));
    Navigator.of(dialogContext).pop();
    await host.message('https://cdn.example/master.m3u8');
    await _settleClose(tester);
    expect(host.result, isA<WebMediaResolutionCancelled>());
    expect(find.text('resolve'), findsOneWidget);
    expect(host.disposed, 1);
  });

  testWidgets('unsupported platforms fail without opening a browser',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await host.mount(tester);
    await _settleClose(tester);
    expect(host.result, isA<StateError>());
    expect(host.urls, isEmpty);
  });
}
