import 'package:juying_core/errors/app_failure.dart';

/// Lightweight functional Result monad for explicit error handling across subsystem boundaries.
///
/// **What**: Represents either a successful computation containing [data] of type [T],
/// or a failure containing [error] of type [AppFailure].
///
/// **Why**: Prevents uncaught exceptions from crossing protocol and isolate boundaries silently.
sealed class AppResult<T> {
  const AppResult();

  factory AppResult.success(T data) = AppSuccess<T>;
  factory AppResult.failure(AppFailure error) = AppError<T>;

  bool get isSuccess => this is AppSuccess<T>;
  bool get isFailure => this is AppError<T>;

  T? get dataOrNull => switch (this) {
        AppSuccess(data: final d) => d,
        AppError() => null,
      };

  AppFailure? get errorOrNull => switch (this) {
        AppSuccess() => null,
        AppError(error: final e) => e,
      };

  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(AppFailure error) onFailure,
  }) {
    return switch (this) {
      AppSuccess(data: final d) => onSuccess(d),
      AppError(error: final e) => onFailure(e),
    };
  }
}

final class AppSuccess<T> extends AppResult<T> {
  const AppSuccess(this.data);
  final T data;
}

final class AppError<T> extends AppResult<T> {
  const AppError(this.error);
  final AppFailure error;
}
