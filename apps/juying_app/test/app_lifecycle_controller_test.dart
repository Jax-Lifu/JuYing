import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/lifecycle/app_lifecycle_controller.dart';
import 'package:juying/core/proxy/local_proxy_server.dart';
import 'package:juying/features/download/services/offline_download_manager.dart';

void main() {
  testWidgets('lifecycle pauses downloads, resumes them and stops proxy',
      (tester) async {
    final proxy = _RecordingProxyServer();
    final downloads = _RecordingDownloadManager();
    await tester.pumpWidget(
      AppLifecycleController(
        proxyServer: proxy,
        downloadManager: downloads,
        child: const MaterialApp(home: SizedBox()),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(downloads.pauseCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(downloads.resumeCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    expect(downloads.pauseCount, 2);
    expect(proxy.stopCount, 1);
  });
}

class _RecordingProxyServer extends LocalProxyServer {
  int stopCount = 0;

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

class _RecordingDownloadManager extends OfflineDownloadManager {
  int pauseCount = 0;
  int resumeCount = 0;

  @override
  void pauseAll() {
    pauseCount++;
  }

  @override
  void resumeAll() {
    resumeCount++;
  }
}
