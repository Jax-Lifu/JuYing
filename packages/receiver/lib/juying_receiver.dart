/// DLNA DMR Receiver Service for JuYing.
///
/// **What**: Implements UPnP MediaRenderer device description, AVTransport,
/// RenderingControl, ConnectionManager, and GENA event subscriptions (Section 5.8).
///
/// **Why**: Implements DMR-01~07 to allow JuYing on TV or PC to be discovered
/// and cast to by external mobile streaming applications.
library;

/// Incoming cast request payload.
class IncomingCastPayload {
  const IncomingCastPayload({
    required this.mediaUri,
    this.title,
    this.coverUrl,
    this.senderIp,
  });

  final String mediaUri;
  final String? title;
  final String? coverUrl;
  final String? senderIp;
}

/// Abstract receiver service contract (Section 5.8).
abstract class ReceiverService {
  Future<void> start();
  Future<void> stop();
  Stream<IncomingCastPayload> get onIncomingCast;
}
