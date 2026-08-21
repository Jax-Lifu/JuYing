import 'package:window_manager/window_manager.dart';

/// 平台窗口的最小能力面。播放 UI 不直接依赖具体窗口插件。
abstract interface class WindowControls {
  Future<bool> isFullScreen();
  Future<void> enterFullScreen();
  Future<void> exitFullScreen();
}

/// 当前 Windows 宿主实现。
class WindowsWindowControls implements WindowControls {
  const WindowsWindowControls();

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> enterFullScreen() async {
    await windowManager.setFullScreen(true);
    if (await windowManager.isFullScreen()) return;

    // 少数 Windows 窗口管理器不会接受全屏状态切换。移除原生边框并最大化，
    // 仍提供沉浸式播放；退出时由 [exitFullScreen] 统一恢复。
    await windowManager.setAsFrameless();
    await windowManager.maximize();
  }

  @override
  Future<void> exitFullScreen() async {
    await windowManager.setFullScreen(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
  }
}

/// 未实现原生窗口控制的平台安全降级：仅由 Flutter 隐藏播放器工具栏。
class NoopWindowControls implements WindowControls {
  const NoopWindowControls();

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<void> enterFullScreen() async {}

  @override
  Future<void> exitFullScreen() async {}
}

/// 记录进入播放器前的窗口状态，保证退出和页面销毁不会意外退出用户原有的全屏。
class PlayerFullscreenSession {
  PlayerFullscreenSession(this._controls);

  final WindowControls _controls;
  var _active = false;
  var _wasFullScreen = false;

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
