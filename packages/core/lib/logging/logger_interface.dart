/// Diagnostic logging severity level.
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// Abstract logging contract for JuYing packages (Section 6.1).
///
/// **What**: Standardized logging interface to decouple low-level protocol packages
/// from Flutter UI frameworks and third-party logging engines.
///
/// **Why**: Pure Dart packages must remain independent of specific UI logger implementations
/// while ensuring tokens and sensitive credentials undergo desensitization.
abstract interface class ILogger {
  void debug(String message,
      {String? tag, Object? error, StackTrace? stackTrace});
  void info(String message,
      {String? tag, Object? error, StackTrace? stackTrace});
  void warning(String message,
      {String? tag, Object? error, StackTrace? stackTrace});
  void error(String message,
      {String? tag, Object? error, StackTrace? stackTrace});
}
