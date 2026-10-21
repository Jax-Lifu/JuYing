import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:juying/core/proxy/local_proxy_server.dart';
import 'package:juying/features/download/services/offline_download_manager.dart';

/// 将系统生命周期转换为可验证的资源管理动作。
class AppLifecycleController extends StatefulWidget {
  const AppLifecycleController({
    required this.child,
    required this.proxyServer,
    required this.downloadManager,
    super.key,
  });

  final Widget child;
  final LocalProxyServer proxyServer;
  final OfflineDownloadManager downloadManager;

  @override
  State<AppLifecycleController> createState() => _AppLifecycleControllerState();
}

class _AppLifecycleControllerState extends State<AppLifecycleController>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        widget.downloadManager.pauseAll();
        break;
      case AppLifecycleState.resumed:
        widget.downloadManager.resumeAll();
        break;
      case AppLifecycleState.detached:
        widget.downloadManager.pauseAll();
        unawaited(widget.proxyServer.stop());
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
