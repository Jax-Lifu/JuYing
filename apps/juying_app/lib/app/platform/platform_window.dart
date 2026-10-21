import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window management helper (Section 6.1 app/platform).
///
/// **What**: Manages desktop window size, constraints, centering, and titlebar styling
/// for Windows, macOS, and Linux targets.
///
/// **Why**: Prevents window rendering glitches and provides uniform startup dimensions (1280x720).
class PlatformWindowManager {
  static Future<void> initializeDesktopWindow() async {
    if (kIsWeb) return;

    final isDesktop = <TargetPlatform>{
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

    if (isDesktop) {
      await windowManager.ensureInitialized();
      const options = WindowOptions(
        size: Size(1280, 720),
        minimumSize: Size(960, 540),
        center: true,
        title: '聚映',
      );
      await windowManager.waitUntilReadyToShow(options, windowManager.show);
    }
  }
}
