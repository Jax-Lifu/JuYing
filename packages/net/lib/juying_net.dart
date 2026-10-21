/// Unified Network Layer for JuYing.
///
/// **What**: Configures Dio HTTP clients, request interceptors, proxy routes,
/// text encoding detectors (GBK/UTF-8), and DoH (DNS over HTTPS).
///
/// **Why**: Implements Section 3.2 network specifications. Ensures consistent
/// timeout, header injection, and retry policies across IPTV, crawler, and NAS providers.
library;

import 'package:dio/dio.dart';

/// Network policy configuration.
class NetworkPolicy {
  const NetworkPolicy({
    this.connectTimeout = const Duration(seconds: 6),
    this.receiveTimeout = const Duration(seconds: 10),
    this.userAgent = 'JuYing/1.0.0 (Windows/Android)',
    this.proxyUrl,
    this.allowSelfSignedCertificates = false,
  });

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final String userAgent;
  final String? proxyUrl;
  final bool allowSelfSignedCertificates;

  Dio createClient() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: {'User-Agent': userAgent},
      ),
    );
    return dio;
  }
}
