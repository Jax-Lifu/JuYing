import 'dart:io';

import 'package:flutter/foundation.dart';

/// Form factor categories for responsive layout and interaction models (Section 6.1).
enum AppFormFactor {
  desktop,
  mobile,
  tv,
}

/// Platform capabilities and hardware form factor detector.
///
/// **What**: Detects operating system environment and device profile (Desktop, Mobile, TV).
///
/// **Why**: Implements Section 1.3 principle: UI is built from day one for spatial focus navigation
/// on TV while maintaining native desktop window and mobile touch experiences.
class PlatformInfo {
  static bool? _isPortableCache;

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether the Windows application is running in portable zero-install mode (Section 3.3 & Q9).
  ///
  /// When true, data and logs are isolated alongside the executable rather than %APPDATA%,
  /// and firewall rules or autostart must be guided interactively.
  static bool get isPortable {
    if (!isWindows) return false;
    if (_isPortableCache != null) return _isPortableCache!;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final flagFile =
          File('${exeDir.path}${Platform.pathSeparator}portable.flag');
      _isPortableCache = flagFile.existsSync();
    } catch (_) {
      _isPortableCache = false;
    }
    return _isPortableCache!;
  }
}
