import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'tvbox_config_parser.dart';

abstract interface class TvboxJavascriptRuntime {
  Future<Object?> invoke(
    TvboxExecutableSite site,
    String method,
    List<Object?> arguments,
  );
}

/// 每次调用启动一个短生命周期宿主。远端代码不进入 Flutter 进程；超时后直接
/// 终止宿主，因此死循环或崩溃不会阻塞应用 UI。
class ProcessTvboxJavascriptRuntime implements TvboxJavascriptRuntime {
  ProcessTvboxJavascriptRuntime({String? executablePath})
      : _executablePath = executablePath;

  static const maxRequestBytes = 512 * 1024;
  static const maxResponseBytes = 2 * 1024 * 1024;
  static const invocationTimeout = Duration(seconds: 18);
  final String? _executablePath;

  @override
  Future<Object?> invoke(
    TvboxExecutableSite site,
    String method,
    List<Object?> arguments,
  ) async {
    final executable = _executablePath ?? _defaultExecutablePath();
    final request = utf8.encode(jsonEncode({
      'api': site.apiUri.toString(),
      'ext': site.ext,
      'method': method,
      'args': arguments,
      'headers': site.httpHeaders,
    }));
    if (request.length > maxRequestBytes) {
      throw StateError('JavaScript 插件请求超过安全上限');
    }

    final process = await Process.start(
      executable,
      const [],
      mode: ProcessStartMode.normal,
    );
    try {
      process.stdin.add(request);
      await process.stdin.close();
      final stdoutFuture = process.stdout.fold<List<int>>(<int>[], (all, data) {
        if (all.length + data.length > maxResponseBytes) {
          throw StateError('JavaScript 插件响应超过安全上限');
        }
        return all..addAll(data);
      });
      final stderrFuture = process.stderr.transform(utf8.decoder).join().then(
          (value) => value.length > 4096 ? value.substring(0, 4096) : value);
      final exitCode =
          await process.exitCode.timeout(invocationTimeout, onTimeout: () {
        process.kill();
        throw TimeoutException('JavaScript 插件执行超时');
      });
      final output = await stdoutFuture;
      final errorOutput = await stderrFuture;
      if (exitCode != 0) {
        throw StateError(errorOutput.trim().isEmpty
            ? 'JavaScript 插件宿主异常退出（$exitCode）'
            : errorOutput.trim());
      }
      final decoded = jsonDecode(utf8.decode(output));
      if (decoded is! Map) throw const FormatException('插件宿主响应格式无效');
      if (decoded['ok'] != true) {
        throw StateError(decoded['error']?.toString() ?? 'JavaScript 插件调用失败');
      }
      final value = decoded['result'];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          return jsonDecode(trimmed);
        }
      }
      return value;
    } finally {
      if (await _isRunning(process)) process.kill();
    }
  }

  static Future<bool> _isRunning(Process process) async {
    try {
      await process.exitCode.timeout(Duration.zero);
      return false;
    } on TimeoutException {
      return true;
    }
  }

  static String _defaultExecutablePath() {
    if (!Platform.isWindows) {
      throw UnsupportedError('JavaScript 插件宿主目前只在 Windows 验证');
    }
    return '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}juying_tvbox_js_host.exe';
  }
}
