/// AirPlay UxPlay Bridge and Screen Mirror Receiver (Section 6.1 receiver/airplay_bridge & ADR-004).
abstract interface class IAirPlayBridge {
  Future<bool> startServer({required String serverName, int port = 7000});
  Future<void> stopServer();
}
