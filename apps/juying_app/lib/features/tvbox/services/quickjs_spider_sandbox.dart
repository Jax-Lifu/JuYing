import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';

/// Runs a TVBox JavaScript spider in a resource-limited QuickJS context.
///
/// The sandbox intentionally starts without `fetch`, `XMLHttpRequest`, `require`,
/// file-system or process bridges. Network access is added by the TVBox protocol
/// adapter, rather than exposing the host runtime directly to untrusted scripts.
class QuickJsSpiderSandbox {
  QuickJsSpiderSandbox({
    this.executionTimeout = const Duration(seconds: 8),
    this.memoryLimitBytes = 64 * 1024 * 1024,
  });

  final Duration executionTimeout;
  final int memoryLimitBytes;

  QuickJsRuntime2? _runtime;
  bool _loaded = false;

  /// Loads one legacy CatVod script exposing a global `__JS_SPIDER__` object.
  void loadLegacyCatVod(String source, {String sourceName = 'spider.js'}) {
    QuickJsRuntime2 runtime;
    try {
      runtime = QuickJsRuntime2(
        timeout: executionTimeout.inMilliseconds,
      );
      _runtime = runtime;
    } catch (e) {
      dispose();
      throw QuickJsSpiderException('QuickJS 引擎初始化失败: $e');
    }

    // flutter_js 0.8.7 的 Windows 预编译桥缺少 jsSetMemoryLimit 导出；先在
    // Dart 边界拒绝超大脚本，避免因调用缺失符号导致整个应用启动失败。
    // Android/Linux 原生堆限额将在自维护 QuickJS 桥统一 ABI 后再启用。
    if (utf8.encode(source).length > memoryLimitBytes) {
      dispose();
      throw const QuickJsSpiderException('Spider 脚本超过沙箱容量上限');
    }

    final result = runtime.evaluate(
      '''
"use strict";
globalThis.process = undefined;
globalThis.require = undefined;
globalThis.Deno = undefined;
globalThis.XMLHttpRequest = undefined;
globalThis.fetch = undefined;
globalThis.__JS_SPIDER__ = undefined;
$source
if (!globalThis.__JS_SPIDER__ ||
    typeof globalThis.__JS_SPIDER__ !== "object") {
  throw new Error("Spider 未导出 __JS_SPIDER__");
}
true;
''',
      name: sourceName,
    );
    if (result.isError) {
      dispose();
      throw QuickJsSpiderException(result.stringResult);
    }
    _loaded = true;
  }

  /// Calls a CatVod entry point and converts its JSON-compatible result to Dart.
  dynamic invoke(String method, List<dynamic> arguments) {
    if (!_loaded || _runtime == null) {
      throw const QuickJsSpiderException('Spider 尚未加载');
    }
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(method)) {
      throw const QuickJsSpiderException('非法 Spider 方法名');
    }

    final result = _runtime!.evaluate(
      '''
(() => {
  const fn = globalThis.__JS_SPIDER__[${jsonEncode(method)}];
  if (typeof fn !== "function") {
    throw new Error("Spider 未实现方法: " + ${jsonEncode(method)});
  }
  const value = fn.apply(globalThis.__JS_SPIDER__, ${jsonEncode(arguments)});
  if (value && typeof value.then === "function") {
    throw new Error("当前入口必须使用同步 CatVod 契约");
  }
  return JSON.stringify(value === undefined ? null : value);
})()
''',
      name: 'invoke-$method.js',
    );
    if (result.isError) {
      throw QuickJsSpiderException(result.stringResult);
    }
    try {
      final decoded = jsonDecode(result.stringResult);
      if (decoded is String) {
        final text = decoded.trim();
        if (text.startsWith('{') || text.startsWith('[')) {
          return jsonDecode(text);
        }
      }
      return decoded;
    } on FormatException catch (error) {
      throw QuickJsSpiderException('Spider 返回值不是合法 JSON: $error');
    }
  }

  /// Releases native memory immediately when switching subscriptions or sites.
  void dispose() {
    _loaded = false;
    _runtime?.dispose();
    _runtime = null;
  }
}

class QuickJsSpiderException implements Exception {
  const QuickJsSpiderException(this.message);

  final String message;

  @override
  String toString() => 'QuickJsSpiderException: $message';
}
