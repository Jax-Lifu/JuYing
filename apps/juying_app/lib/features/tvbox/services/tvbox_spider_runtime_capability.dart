// Capability inspection is kept after the result fields to read as a decision table.
// ignore_for_file: sort_constructors_first

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:juying_source_providers/juying_source_providers.dart';

/// TVBox type=3 站点背后的实际执行技术栈。
///
/// type=3 只是 TVBox 配置层的统一编号，并不代表内容一定是 JavaScript；
/// 将 JAR、Python 与 DRPY 混为一类会导致错误地选择运行时，甚至扩大沙箱权限。
enum TvBoxSpiderRuntimeKind {
  drpyJavaScript,
  catVodJavaScript,
  catVodJar,
  dartNative,
  python,
  unknown,
}

/// type=3 Spider 的静态能力诊断结果。
///
/// 诊断结果同时承担平台门禁：Android 可启用标准 CatVod Dex 宿主，其他平台
/// 只展示能力说明；尚未满足内存、超时和宿主桥限制的脚本运行时不会被误启用。
class TvBoxSpiderRuntimeCapability {
  const TvBoxSpiderRuntimeCapability({
    required this.kind,
    required this.runtimeAvailable,
    required this.reason,
    this.requiredBridges = const <String>[],
  });

  final TvBoxSpiderRuntimeKind kind;
  final bool runtimeAvailable;
  final String reason;
  final List<String> requiredBridges;

  String get label => switch (kind) {
        TvBoxSpiderRuntimeKind.drpyJavaScript => 'DRPY JS 待沙箱',
        TvBoxSpiderRuntimeKind.catVodJavaScript => 'CatVod JS 待沙箱',
        TvBoxSpiderRuntimeKind.catVodJar =>
          runtimeAvailable ? 'Android Dex' : '待 Flutter 适配',
        TvBoxSpiderRuntimeKind.dartNative => 'Dart Spider',
        TvBoxSpiderRuntimeKind.python => 'Python 不可用',
        TvBoxSpiderRuntimeKind.unknown => 'Spider 类型未知',
      };

  /// 根据 TVBox `api`、`jar` 与 `ext` 字段识别真正需要的运行时。
  factory TvBoxSpiderRuntimeCapability.inspect({
    required String api,
    int type = 3,
    String key = '',
    String? jar,
    Object? ext,
  }) {
    final normalizedApi = api.trim();
    final lowerApi = normalizedApi.toLowerCase();
    final normalizedJar = jar?.trim() ?? '';

    if (type == 0 || type == 1 || type == 4) {
      final supported = (type == 4 && key == 'cctv_vod') ||
          (_isHttpUrl(normalizedApi) && !_isScriptUrl(normalizedApi));
      return TvBoxSpiderRuntimeCapability(
        kind: supported
            ? TvBoxSpiderRuntimeKind.dartNative
            : TvBoxSpiderRuntimeKind.unknown,
        runtimeAvailable: supported,
        reason: supported
            ? '标准 CMS / T4 HTTP 协议或内置央视片库由跨平台适配器执行。'
            : '该站点缺少有效的 HTTP(S) API，无法执行声明的协议。',
      );
    }
    if (type != 3) {
      return const TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.unknown,
        runtimeAvailable: false,
        reason: '当前未实现该 TVBox 站点类型。',
      );
    }

    if (<String>{'csp_bili', 'csp_biliguard', 'csp_bili2'}.contains(lowerApi)) {
      return const TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.dartNative,
        runtimeAvailable: true,
        reason: 'B站关键词分类、搜索和分P播放已移植为跨平台 Dart 实现。',
        requiredBridges: <String>[
          'Bilibili Web API',
          'CatVod class/classes config',
        ],
      );
    }

    if (lowerApi == 'py_cctv_full' ||
        (lowerApi.startsWith('py_cctv') &&
            (ext?.toString().contains('央视') ?? false))) {
      return const TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.dartNative,
        runtimeAvailable: true,
        reason: '已将 Python 央视 Spider 映射为官方接口的跨平台 Dart 实现。',
        requiredBridges: <String>['CCTV official APIs'],
      );
    }

    if (supportsXbpq(api: normalizedApi, ext: ext)) {
      return const TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.dartNative,
        runtimeAvailable: true,
        reason: '声明式 XBPQ 规则由跨平台 Dart 适配器执行。',
        requiredBridges: <String>['HTTP(S)', 'XBPQ boundary parser'],
      );
    }

    if (supportsAppApi(api: normalizedApi, ext: ext)) {
      return const TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.dartNative,
        runtimeAvailable: true,
        reason: '通用 App API Dex 契约已 clean-room 重写为跨平台 Dart 适配器。',
        requiredBridges: <String>['HTTP(S)', 'AppYsV2 API parser'],
      );
    }

    if (supportsLiveToVod(api: normalizedApi, ext: ext)) {
      return const TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.dartNative,
        runtimeAvailable: true,
        reason: 'live2vod 直播目录与分组列表已移植为跨平台 Dart 实现。',
        requiredBridges: <String>['HTTP(S)', 'IPTV M3U/TXT/JSON parser'],
      );
    }

    if (supportsTuxiaobei(api: normalizedApi, ext: ext)) {
      return const TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.dartNative,
        runtimeAvailable: true,
        reason: '兔小贝 DRPY 规则已移植为官方分类、搜索及原生播放地址的 Dart 实现。',
        requiredBridges: <String>['Tuxiaobei official HTTP API'],
      );
    }

    if (PortedSpiderRegistry.instance.has(normalizedApi)) {
      final portedRule = PortedSpiderRegistry.instance.find(normalizedApi);
      final displayName = portedRule?.displayName ?? normalizedApi;
      return TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.dartNative,
        runtimeAvailable: true,
        reason: '已由纯 Dart 移植适配器执行 ($displayName)。',
        requiredBridges: const <String>['HTTP(S)', 'Dart Ported Spider'],
      );
    }

    if (_isRemoteJavaScript(lowerApi)) {
      final isDrpy = lowerApi.contains('drpy') || ext != null;
      return TvBoxSpiderRuntimeCapability(
        kind: isDrpy
            ? TvBoxSpiderRuntimeKind.drpyJavaScript
            : TvBoxSpiderRuntimeKind.catVodJavaScript,
        runtimeAvailable: false,
        reason: isDrpy
            ? 'DRPY 运行时尚未满足 64MB 内存、8 秒硬中断及模块/网络桥安全边界。'
            : 'JavaScript Spider 运行时尚未满足 64MB 内存、8 秒硬中断及网络白名单。',
        requiredBridges: isDrpy
            ? const <String>[
                'HTTP(S) req/fetch',
                'ES module loader',
                'pdfh/pdfa/pdfl parser',
                'crypto/local storage',
              ]
            : const <String>[
                'HTTP(S) req/fetch',
                'ES module loader',
              ],
      );
    }

    if (lowerApi.startsWith('py_') ||
        (Uri.tryParse(lowerApi)?.path.endsWith('.py') ?? false)) {
      return const TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.python,
        runtimeAvailable: false,
        reason: '该 Python Spider 尚未移植为 Dart；不会在 Flutter 进程中执行任意 Python。',
      );
    }

    if (lowerApi.startsWith('csp_') || normalizedJar.isNotEmpty) {
      final isAndroid = !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          lowerApi.startsWith('csp_') &&
          normalizedJar.isNotEmpty;
      return TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.catVodJar,
        runtimeAvailable: isAndroid,
        reason: isAndroid
            ? '由 Android DexClassLoader 执行标准 CatVod Spider 生命周期。'
            : '该 JAR 是任意 Android 业务代码，需逐站 clean-room 移植为 Dart，不能直接当作 Flutter 字节码执行。',
      );
    }

    if (httpCmsApi(type: type, api: normalizedApi).isNotEmpty) {
      return const TvBoxSpiderRuntimeCapability(
        kind: TvBoxSpiderRuntimeKind.dartNative,
        runtimeAvailable: true,
        reason: '标准 HTTP VOD / CMS API 接口跨平台直接执行。',
        requiredBridges: <String>['HTTP(S)'],
      );
    }

    return const TvBoxSpiderRuntimeCapability(
      kind: TvBoxSpiderRuntimeKind.unknown,
      runtimeAvailable: false,
      reason: '无法从配置判断 Spider 执行栈，已按不受支持处理。',
    );
  }

  /// 只映射已移植的规则文件身份，不启用其他 DRPY 脚本或按站点显示名猜测。
  static bool supportsLiveToVod({required String api, Object? ext}) =>
      _isHttpUrl(api.trim()) &&
      Uri.parse(api.trim()).pathSegments.lastOrNull?.toLowerCase() ==
          'live2vod.js' &&
      ext is String &&
      ext.trim().isNotEmpty;

  /// 内置身份与已知兔小贝规则共用官方适配器，其他脚本仍需完整沙箱。
  static bool supportsTuxiaobei({required String api, Object? ext}) {
    if (api.trim().toLowerCase() == 'csp_tuxiaobei') return true;
    if (!_isRemoteJavaScript(api.trim().toLowerCase())) return false;
    final apiFile = Uri.parse(api.trim()).pathSegments.last.toLowerCase();
    const names = <String>{'兔小贝.js', 'tuxiaobei.js'};
    if (names.contains(apiFile)) return true;
    if (!apiFile.contains('drpy') || ext is! String || !_isHttpUrl(ext)) {
      return false;
    }
    final segments = Uri.parse(ext).pathSegments;
    return segments.isNotEmpty && names.contains(segments.last.toLowerCase());
  }

  /// App API 只能由已实现的显式 Spider 身份声明，不能用 ext 路径抢占其他协议。
  static bool supportsAppApi({required String api, Object? ext}) {
    if (!<String>{
      'csp_appysv2',
      'csp_appys',
      'csp_app',
      'csp_appysv10',
      'app_ys',
      'csp_v2',
      'csp_vip',
    }.contains(api.trim().toLowerCase())) {
      return false;
    }
    if (ext is Map) ext = ext['url'] ?? ext['api'];
    final url = ext?.toString().split('###').first.trim() ?? '';
    return _isHttpUrl(url) && !_isScriptUrl(url);
  }

  /// type=3 的 HTTP 兼容入口只接收已有 CMS 路径，不把普通网页或 ext 当成 API。
  static String httpCmsApi({required int type, required String api}) {
    final value = api.trim();
    if (!_isHttpUrl(value) || _isScriptUrl(value)) return '';
    if (type == 0 || type == 1) return value;
    if (type != 3) return '';
    final path = Uri.parse(value).path.toLowerCase();
    return path.endsWith('/api.php') ||
            path.contains('/api.php/') ||
            path.contains('/provide/vod')
        ? value
        : '';
  }

  /// 只有已实现的 XBPQ/XB64 语法进入边界解析器；其他 Spider 的 ext 不是规则。
  static bool supportsXbpq({required String api, Object? ext}) {
    if (!<String>{'csp_xbpq', 'csp_xb64'}.contains(api.trim().toLowerCase())) {
      return false;
    }
    if (ext is String && _isHttpUrl(ext.trim())) {
      return !_isScriptUrl(ext.trim());
    }
    return hasXbpqRules(parseXbpqRules(ext));
  }

  /// 保留已支持的 Map、JSON、XB64 以及逗号键值规则格式。
  static Map<String, String> parseXbpqRules(Object? source) {
    if (source is String) {
      var text = source.trim();
      if (!text.startsWith('{') &&
          text.length > 20 &&
          RegExp(r'^[A-Za-z0-9+/=_\-]+$').hasMatch(text)) {
        try {
          text = utf8.decode(base64.decode(base64.normalize(text)));
        } on FormatException {
          return <String, String>{};
        }
      }
      if (text.startsWith('{')) {
        try {
          source = json.decode(text);
        } on FormatException {
          return <String, String>{};
        }
      } else {
        source = <String, String>{
          for (final entry in text.split(','))
            if (entry.indexOf(':') > 0)
              entry.substring(0, entry.indexOf(':')).trim():
                  entry.substring(entry.indexOf(':') + 1).trim(),
        };
      }
    }
    return <String, String>{
      if (source is Map)
        for (final entry in source.entries)
          if (entry.value != null)
            entry.key.toString().trim(): entry.value.toString(),
    };
  }

  /// 至少包含本适配器读取的规则字段，避免将站点配置伪装成成功加载的规则。
  static bool hasXbpqRules(Map<String, String> rules) => <String>[
        '分类',
        '分类url',
        '分类URL',
        '搜索url',
        '搜索URL',
        '主页url',
        '数组',
        '播放数组',
        '播放列表',
      ].any((key) => rules[key]?.trim().isNotEmpty ?? false);

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        <String>{'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty;
  }

  static bool _isScriptUrl(String value) {
    final path = Uri.tryParse(value)?.path.toLowerCase() ?? '';
    return <String>['.js', '.py', '.jar'].any(path.endsWith);
  }

  static bool _isRemoteJavaScript(String api) {
    final uri = Uri.tryParse(api);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path.endsWith('.js') || path.endsWith('.m.js');
  }
}
