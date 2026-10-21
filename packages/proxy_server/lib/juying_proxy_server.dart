/// Local Range Proxy and Loopback Stream Bridge for JuYing.
///
/// **What**: Manages isolated loopback Range proxies (127.0.0.1:9978),
/// temporary LAN casting endpoints, and secured PIN-paired remote configuration (ADR-006 & ADR-015).
///
/// **Why**: Smart TVs and media renderers cannot inject custom headers or authenticate
/// against LAN/NAS private shares directly. Physical isolation between loopback and external LAN
/// eliminates network attack surfaces during local playback.
library;

export 'src/lan_gateway_server.dart';
export 'src/local_proxy_server.dart';
export 'src/loopback_stream_proxy.dart';
export 'src/stream_registration.dart';
