import 'dart:async';

import 'lan_gateway_server.dart';
import 'loopback_stream_proxy.dart';

/// 兼容现有调用的本地代理服务门面 (ADR-006 / ADR-015)。
///
/// 新代码应根据职责分别注入 [LoopbackStreamProxy] 与 [LanGatewayServer]。
class LocalProxyServer {
  LocalProxyServer({
    LoopbackStreamProxy? loopback,
    LanGatewayServer? gateway,
  })  : loopback = loopback ?? LoopbackStreamProxy(),
        gateway = gateway ?? LanGatewayServer();

  static final LocalProxyServer instance = LocalProxyServer();

  final LoopbackStreamProxy loopback;
  final LanGatewayServer gateway;

  bool get isRunning => loopback.isRunning;
  int get port => loopback.port;
  Stream<Map<String, dynamic>> get remoteConfigStream => gateway.events;

  Future<bool> start({int port = 9978}) => loopback.start(port: port);

  Future<bool> startLanGateway({int port = 9979}) => gateway.start(port: port);

  String registerStreamProxy({
    String? token,
    required StreamSourceResolver resolver,
    required int contentLength,
    String contentType = 'video/mp4',
    String? ownerId,
  }) {
    return loopback.register(
      resolver: resolver,
      contentLength: contentLength,
      contentType: contentType,
      ownerId: ownerId ?? token ?? 'anonymous',
    );
  }

  void unregisterStreamProxiesForPrefix(String prefix) {
    loopback.unregisterOwnersWithPrefix(prefix);
  }

  void unregisterOwner(String ownerId) => loopback.unregisterOwner(ownerId);

  Future<void> stop() async {
    await Future.wait(<Future<void>>[loopback.stop(), gateway.stop()]);
  }

  Future<void> dispose() async {
    await loopback.stop();
    await gateway.dispose();
  }
}
