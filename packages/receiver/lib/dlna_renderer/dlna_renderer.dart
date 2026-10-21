/// DLNA MediaRenderer Daemon and SOAP Service Handler (Section 6.1 receiver/dlna_renderer).
abstract interface class IDlnaRendererDaemon {
  Future<void> start({required int port, required String friendlyName});
  Future<void> stop();
}
