import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'tvbox_config_parser.dart';
import 'tvbox_javascript_runtime.dart';

/// 在独立 JVM 中执行 TVBox `csp_*` DEX/JAR。下载、摘要校验和 DEX 转换结果
/// 都按 URL 缓存；每次方法调用仍使用短生命周期进程并受超时限制。
class ProcessTvboxCspRuntime implements TvboxJavascriptRuntime {
  ProcessTvboxCspRuntime({required http.Client client, String? hostDirectory})
      : _client = client,
        _hostDirectory = hostDirectory;

  static const maxJarBytes = 32 * 1024 * 1024;
  static const maxResponseBytes = 4 * 1024 * 1024;
  static const invocationTimeout = Duration(seconds: 20);
  final http.Client _client;
  final String? _hostDirectory;
  final Map<String, Future<File>> _converted = {};

  @override
  Future<Object?> invoke(
    TvboxExecutableSite executableSite,
    String method,
    List<Object?> arguments,
  ) async {
    if (executableSite is! TvboxCspSite) {
      throw ArgumentError('CSP 运行时只接受 csp_* 站点');
    }
    final site = executableSite;
    final cacheKey = '${site.jarUri}#${site.jarMd5 ?? ''}';
    final converted = await (_converted[cacheKey] ??=
        _prepareJar(site).catchError((Object error) {
      _converted.remove(cacheKey);
      throw error;
    }));
    final host = Directory(_hostDirectory ?? _defaultHostDirectory());
    final java = File('${host.path}${Platform.pathSeparator}runtime'
        '${Platform.pathSeparator}bin${Platform.pathSeparator}java.exe');
    if (!java.existsSync()) throw StateError('TVBox CSP 运行时未随应用安装');
    final classpath = [
      '${host.path}${Platform.pathSeparator}classes',
      converted.path,
      '${host.path}${Platform.pathSeparator}lib${Platform.pathSeparator}*',
    ].join(';');
    final process = await Process.start(
      java.path,
      ['-cp', classpath, 'com.juying.tvbox.CspHost', site.className],
      workingDirectory: host.path,
    );
    try {
      process.stdin.write(jsonEncode({
        'method': method,
        'args': arguments,
        'ext': site.ext,
      }));
      await process.stdin.close();
      final outputFuture = process.stdout.fold<List<int>>(<int>[], (all, data) {
        if (all.length + data.length > maxResponseBytes) {
          throw StateError('CSP 插件响应超过安全上限');
        }
        return all..addAll(data);
      });
      final errorFuture = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final exit =
          await process.exitCode.timeout(invocationTimeout, onTimeout: () {
        process.kill();
        throw TimeoutException('CSP 插件执行超时');
      });
      final output = await outputFuture;
      final error = await errorFuture;
      if (exit != 0) {
        final message = error.trim();
        throw StateError(message.isEmpty
            ? 'CSP 插件宿主异常退出（$exit）'
            : message.length > 4096
                ? message.substring(0, 4096)
                : message);
      }
      final envelope = jsonDecode(utf8.decode(output));
      if (envelope is! Map || envelope['ok'] != true) {
        final encoded = envelope is Map ? envelope['errorBase64'] : null;
        throw StateError(encoded is String
            ? utf8.decode(base64Decode(encoded))
            : 'CSP 插件调用失败');
      }
      final encoded = envelope['resultBase64'];
      if (encoded is! String) throw const FormatException('CSP 宿主响应格式无效');
      final value = utf8.decode(base64Decode(encoded));
      final trimmed = value.trim();
      return trimmed.startsWith('{') || trimmed.startsWith('[')
          ? jsonDecode(trimmed)
          : value;
    } finally {
      if (await _isRunning(process)) process.kill();
    }
  }

  Future<File> _prepareJar(TvboxCspSite site) async {
    final root = Directory('${Directory.systemTemp.path}'
        '${Platform.pathSeparator}juying_tvbox_csp');
    await root.create(recursive: true);
    final key = sha256
        .convert(utf8.encode('${site.jarUri}#${site.jarMd5 ?? ''}'))
        .toString();
    final original = File('${root.path}${Platform.pathSeparator}$key.jar');
    final converted = File('${root.path}${Platform.pathSeparator}$key.jvm.jar');
    if (converted.existsSync()) return converted;
    final response = await _client.get(site.jarUri).timeout(
          const Duration(seconds: 15),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('CSP JAR 下载失败（HTTP ${response.statusCode}）');
    }
    if (response.bodyBytes.length > maxJarBytes) {
      throw StateError('CSP JAR 超过 32 MiB 上限');
    }
    final expected = site.jarMd5;
    if (expected != null &&
        md5.convert(response.bodyBytes).toString() != expected) {
      throw StateError('CSP JAR 的 MD5 与配置声明不一致');
    }
    await original.writeAsBytes(response.bodyBytes, flush: true);
    final host = Directory(_hostDirectory ?? _defaultHostDirectory());
    final java = '${host.path}${Platform.pathSeparator}runtime'
        '${Platform.pathSeparator}bin${Platform.pathSeparator}java.exe';
    final dexLib = '${host.path}${Platform.pathSeparator}dex2jar'
        '${Platform.pathSeparator}lib${Platform.pathSeparator}*';
    final conversion = await Process.run(java, [
      '-cp',
      dexLib,
      'com.googlecode.dex2jar.tools.Dex2jarCmd',
      original.path,
      '-o',
      converted.path,
      '--force',
    ]).timeout(const Duration(seconds: 30));
    if (conversion.exitCode != 0 || !converted.existsSync()) {
      throw StateError('CSP DEX 转换失败：${conversion.stderr}');
    }
    return converted;
  }

  static Future<bool> _isRunning(Process process) async {
    try {
      await process.exitCode.timeout(Duration.zero);
      return false;
    } on TimeoutException {
      return true;
    }
  }

  static String _defaultHostDirectory() {
    if (!Platform.isWindows) throw UnsupportedError('CSP 运行时目前只在 Windows 验证');
    return '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}tvbox_csp_host';
  }
}
