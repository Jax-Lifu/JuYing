/// 统一的只读来源请求基线：有上限的超时、退避与可重试 HTTP 状态。
/// 具体来源可以收紧，不能通过调用方绕过这些限制。
class NetworkRequestPolicy {
  const NetworkRequestPolicy({
    this.timeout = const Duration(seconds: 15),
    this.maxAttempts = 2,
    this.retryBaseDelay = const Duration(milliseconds: 300),
  }) : assert(maxAttempts >= 1);

  final Duration timeout;
  final int maxAttempts;
  final Duration retryBaseDelay;

  Duration retryDelayFor(int failedAttempt) =>
      retryBaseDelay * failedAttempt.clamp(1, maxAttempts);

  bool shouldRetryHttpStatus(int statusCode) =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;
}
