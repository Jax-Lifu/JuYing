import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/platform/window_controls.dart';

void main() {
  test('退出播放器不会改变用户进入前已有的全屏状态', () async {
    final controls = _FakeWindowControls(fullscreen: true);
    final session = PlayerFullscreenSession(controls);

    await session.enter();
    await session.exit();

    expect(controls.enterCount, 0);
    expect(controls.exitCount, 0);
  });

  test('播放器自身进入的全屏会在销毁时恢复窗口', () async {
    final controls = _FakeWindowControls();
    final session = PlayerFullscreenSession(controls);

    await session.enter();
    await session.dispose();

    expect(controls.enterCount, 1);
    expect(controls.exitCount, 1);
  });
}

class _FakeWindowControls implements WindowControls {
  _FakeWindowControls({this.fullscreen = false});

  bool fullscreen;
  int enterCount = 0;
  int exitCount = 0;

  @override
  Future<void> enterFullScreen() async {
    enterCount++;
    fullscreen = true;
  }

  @override
  Future<void> exitFullScreen() async {
    exitCount++;
    fullscreen = false;
  }

  @override
  Future<bool> isFullScreen() async => fullscreen;
}
