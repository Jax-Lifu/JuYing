/// Standardized application error codes (Section 6.3).
enum ErrorCode {
  // Player Errors
  playerDecoderFailed,
  playerFormatUnsupported,
  playerTimeout,
  playerNetworkError,
  playerDrmProtected,

  // IPTV / Live Errors
  liveStreamOffline,
  liveManifestInvalid,
  liveCircuitBreakerTripped,

  // Source / Spider Errors
  spiderNotConfigured,
  spiderTimeout,
  spiderEvaluationFailed,
  spiderPlatformUnsupported,

  // Network / Proxy Errors
  networkDnsLookupFailed,
  networkCertificateInvalid,
  networkHttp403Forbidden,
  networkHttp404NotFound,
  networkHttpTimeout,
  proxySsrfBlocked,
  proxyPortOccupied,

  // Storage / NAS Errors
  storagePermissionDenied,
  storageSpaceInsufficient,
  nasAuthenticationFailed,
  nasHostUnreachable,

  // DLNA / Cast Errors
  castDeviceNotFound,
  castActionRejected,

  // General Errors
  unknown,
}

/// Unified error abstraction across all JuYing subsystem boundaries.
///
/// **What**: Standardized error container carrying a domain [code], human-readable [message],
/// and optional underlying [cause] / [stackTrace].
///
/// **Why**: Section 6.3 requires all protocol-level exceptions to convert to [AppFailure]
/// rather than bubbling untyped raw platform exceptions to the presentation layer.
class AppFailure implements Exception {
  const AppFailure({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  /// High-level diagnostic error code.
  final ErrorCode code;

  /// Human-readable, user-presentable or debug error message.
  final String message;

  /// Underlying root cause exception or error.
  final Object? cause;

  /// Captured stack trace for telemetry and local log reporting.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('AppFailure($code): $message');
    if (cause != null) {
      buffer.write(' (Cause: $cause)');
    }
    return buffer.toString();
  }
}
