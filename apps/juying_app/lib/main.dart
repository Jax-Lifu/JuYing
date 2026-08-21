import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'features/player/infrastructure/native_playback_probe.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  MediaKit.ensureInitialized();
  final probeArgument = kDebugMode
      ? arguments
          .where((value) => value.startsWith('--playback-probe='))
          .firstOrNull
      : null;
  if (probeArgument != null) {
    final uri =
        Uri.tryParse(probeArgument.substring('--playback-probe='.length));
    final valid = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
    final succeeded = valid && await probeNativePlayback(uri);
    stdout.writeln(succeeded ? 'PLAYBACK_PROBE_OK' : 'PLAYBACK_PROBE_FAILED');
    exit(succeeded ? 0 : 2);
  }
  if (defaultTargetPlatform == TargetPlatform.windows) {
    await WebviewController.initializeEnvironment(
      additionalArguments: '--autoplay-policy=no-user-gesture-required',
    );
  }
  final loaded = await AppConfig.loadBundled();
  runApp(JuYingApp(
    config: loaded.appConfig,
    sourceConfiguration: loaded.sourceConfiguration,
  ));
}
