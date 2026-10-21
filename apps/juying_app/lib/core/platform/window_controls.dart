import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 播放页面使用的最小窗口能力，避免 UI 直接耦合桌面窗口插件。
abstract interface class WindowControls {
  Future<bool> isFullScreen();
  Future<void> enterFullScreen();
  Future<void> exitFullScreen();
}

/// 桌面端窗口控制；移动端由系统播放器接管屏幕方向与沉浸模式。
class DesktopWindowControls implements WindowControls {
  const DesktopWindowControls();

  bool get _isDesktop =>
      !kIsWeb &&
      {
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  @override
  Future<bool> isFullScreen() async {
    return _isDesktop && await windowManager.isFullScreen();
  }

  @override
  Future<void> enterFullScreen() async {
    if (!_isDesktop) return;
    await windowManager.setFullScreen(true);
    if (await windowManager.isFullScreen()) return;

    // 某些 Windows 窗口管理器会忽略第一次全屏请求；无边框最大化仍能
    // 保证 WebView 纹理覆盖完整显示区域。
    await windowManager.setAsFrameless();
    await windowManager.maximize();
  }

  @override
  Future<void> exitFullScreen() async {
    if (!_isDesktop) return;
    await windowManager.setFullScreen(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
  }
}

/// 只恢复播放器自己改变的窗口状态，避免退出播放时破坏用户原有全屏。
class PlayerFullscreenSession {
  PlayerFullscreenSession(this._controls);

  final WindowControls _controls;
  bool _active = false;
  bool _wasFullScreen = false;

  bool get isActive => _active;

  Future<void> enter() async {
    if (_active) return;
    _wasFullScreen = await _controls.isFullScreen();
    _active = true;
    if (!_wasFullScreen) await _controls.enterFullScreen();
  }

  Future<void> exit() async {
    if (!_active) return;
    if (!_wasFullScreen) await _controls.exitFullScreen();
    _active = false;
  }

  Future<void> dispose() => exit();
}
