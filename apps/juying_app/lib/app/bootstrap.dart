import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'package:juying/app/platform/platform_window.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/lifecycle/app_lifecycle_controller.dart';
import 'package:juying/core/logging/local_log_service.dart';
import 'package:juying/core/proxy/local_proxy_server.dart';
import 'package:juying/features/download/services/offline_download_manager.dart';
import 'package:juying/features/sync/services/webdav_sync_coordinator.dart';

/// Application bootstrap orchestrator (Section 6.1 app/bootstrap.dart).
///
/// **What**: Coordinates startup lifecycle: sets up structured logging, platform window
/// geometries, libmpv playback bindings, i18n dictionaries, local range proxy server,
/// and initial background synchronization.
///
/// **Why**: Centralizing the boot pipeline prevents `main.dart` from bloating into an
/// unmaintainable procedural script and enables reproducible test fixtures.
void bootstrap(Widget Function() builder) {
  final logger = LocalLogService();

  unawaited(runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        unawaited(
          logger.record(details.exception, details.stack ?? StackTrace.current),
        );
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        unawaited(logger.record(error, stack));
        return true;
      };

      ErrorWidget.builder = (FlutterErrorDetails details) =>
          _RecoverableErrorWidget(details: details);

      // Initialize desktop window sizing & centering
      await PlatformWindowManager.initializeDesktopWindow();

      // Initialize media playback engine & native bindings
      MediaKit.ensureInitialized();

      // Initialize localization dictionary
      await I18nService.instance.init();

      // Start local loopback range proxy
      await LocalProxyServer.instance.start();

      runApp(
        ProviderScope(
          child: AppLifecycleController(
            proxyServer: LocalProxyServer.instance,
            downloadManager: OfflineDownloadManager.instance,
            child: builder(),
          ),
        ),
      );

      // Trigger non-blocking initial WebDAV sync
      unawaited(WebDavSyncCoordinator.instance.syncNow());
    },
    (Object error, StackTrace stackTrace) {
      unawaited(logger.record(error, stackTrace));
    },
  ));
}

class _RecoverableErrorWidget extends StatelessWidget {
  const _RecoverableErrorWidget({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0D1117),
      child: Center(
        child: Focus(
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFF85149),
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  '页面暂时无法显示',
                  style: TextStyle(color: Color(0xFFF0F6FC), fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  kDebugMode ? details.exceptionAsString() : '请返回上一页后重试',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8B949E)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
