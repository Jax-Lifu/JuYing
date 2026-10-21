import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:punycoder/punycoder.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';

/// Parsed configuration bundle from a TVBox warehouse subscription.
class TvBoxConfig {
  const TvBoxConfig({
    required this.spiderUrl,
    required this.sites,
    this.lives = const <Map<String, dynamic>>[],
    this.parses = const <Map<String, dynamic>>[],
    this.flags = const <String>[],
    this.warehouseUrls = const <String>[],
    this.isPartial = false,
    this.wallpaper,
  });

  final String spiderUrl;
  final List<TvBoxSite> sites;
  final List<Map<String, dynamic>> lives;
  final List<Map<String, dynamic>> parses;
  final List<String> flags;
  final List<String> warehouseUrls;

  /// A failed child warehouse cannot authorize deleting its cached sites.
  final bool isPartial;
  final String? wallpaper;
}

/// Ingests, decrypts, and unpacks single/multi-warehouse TVBox subscriptions.
///
/// **What**: Downloads remote TVBox configuration files, handles IDN domain names,
/// strips non-standard C-style comments (`//`, `/* */`) and trailing commas, decrypts
/// AES/Base64 obfuscated payloads, and parses site adapters, multi-warehouses, live channels, and parse rules.
///
/// **Why**: TVBox subscriptions (e.g. 饭太硬, 肥猫, 巧儿, 小胡4K) frequently contain
/// non-standard JSON with comments, trailing commas, AES-128-CBC encryption, and WebP trailer padding.
class TvBoxConfigService {
  TvBoxConfigService({
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                responseType: ResponseType.plain,
                headers: <String, dynamic>{
                  'User-Agent': 'okhttp/3.15',
                  'Accept': '*/*',
                },
                followRedirects: true,
                maxRedirects: 5,
                validateStatus: (status) => status != null && status < 500,
              ),
            );

  final Dio _dio;

  static const int _warehouseConcurrency = 4;

  /// 最近一次订阅加载失败的可展示原因，不暴露 Dio 的冗长内部堆栈。
  String? lastError;

  // Known standard magic keys used across Chinese TVBox subscriptions
  static const List<String> _magicKeys = <String>[
    '2803166298623823',
    '2401466698623823',
    '1234567890123456',
  ];

  /// Loads and unpacks a TVBox subscription URL (supporting Plain JSON, Relaxed JSON with comments, Multi-warehouse, and AES encryption).
  Future<TvBoxConfig?> loadConfig(String url) {
    lastError = null;
    return _loadConfigRecursive(url, <String>{}, 0);
  }

  Future<TvBoxConfig?> _loadConfigRecursive(
    String url,
    Set<String> visited,
    int depth,
  ) async {
    if (depth > 3) return null;
    try {
      final sanitizedUrl = _sanitizeUrl(url);
      if (!visited.add(sanitizedUrl)) return null;
      final response = await _dio.get<dynamic>(
        sanitizedUrl,
        // 图片伪装订阅必须先保留原始字节，再定位尾部 `** + Base64`；
        // 直接按文本解码会在 JPEG/WebP 二进制区提前损坏载荷。
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      final rawContent = data is List<int>
          ? utf8.decode(data, allowMalformed: true)
          : data?.toString() ?? '';

      if (rawContent.isEmpty) {
        lastError = '订阅返回了空内容';
        return null;
      }

      final root = _decodeConfig(rawContent);
      if (root == null) {
        lastError = '订阅内容不是可识别的 TVBox 配置';
        return null;
      }

      final resolvedSpider = _resolveReference(sanitizedUrl, root.spiderUrl);
      final parses = <Map<String, dynamic>>[
        for (final parser in root.parses)
          {
            ...parser,
            if (parser['url'] is String &&
                (parser['url'] as String).trim().isNotEmpty)
              'url': _resolveReference(sanitizedUrl, parser['url'] as String),
          },
      ];
      final sites = <TvBoxSite>[
        for (final site in root.sites)
          site.copyWith(
            // 在子仓扁平化及 key 消歧前记录请求来源，不接受远端自报身份。
            originId: sha256
                .convert(utf8.encode(json.encode([sanitizedUrl, site.key])))
                .toString(),
            api: site.api.isNotEmpty &&
                    !site.api.startsWith('csp_') &&
                    !site.api.startsWith('py_')
                ? _resolveReference(sanitizedUrl, site.api)
                : site.api,
            jar: site.jar.isNotEmpty
                ? _resolveReference(sanitizedUrl, site.jar)
                : site.type == 3 && site.api.startsWith('csp_')
                    ? resolvedSpider
                    : '',
            ext: _resolveExtension(sanitizedUrl, site.ext),
            parses: List<Map<String, dynamic>>.unmodifiable(parses),
            flags: root.flags,
          ),
      ];
      final lives = <Map<String, dynamic>>[...root.lives];
      final flags = <String>[...root.flags];
      var isPartial = false;
      final childUrls = root.warehouseUrls
          .map((childUrl) =>
              Uri.parse(sanitizedUrl).resolve(childUrl).toString())
          .toList(growable: false);
      // 多仓经常混有停服入口；受控并发可把总等待时间限制在批次数量，
      // 同时保留配置顺序，避免每个超时依次叠加阻塞导入界面。
      for (var start = 0;
          start < childUrls.length;
          start += _warehouseConcurrency) {
        final end = start + _warehouseConcurrency < childUrls.length
            ? start + _warehouseConcurrency
            : childUrls.length;
        final children = await Future.wait(
          childUrls.sublist(start, end).map(
                (childUrl) => _loadConfigRecursive(
                  childUrl,
                  visited,
                  depth + 1,
                ),
              ),
        );
        for (final child in children) {
          if (child == null) {
            isPartial = true;
            continue;
          }
          isPartial = isPartial || child.isPartial;
          sites.addAll(child.sites);
          lives.addAll(child.lives);
          parses.addAll(child.parses);
          flags.addAll(child.flags);
        }
      }
      final uniqueSites = <String, TvBoxSite>{};
      final origins = <String>{};
      for (final site in sites) {
        if (site.key.isEmpty || site.api.isEmpty && site.type != 4) continue;
        if (!origins.add(site.originId!)) continue;
        final existing = uniqueSites[site.key];
        if (existing == null) {
          uniqueSites[site.key] = site;
          continue;
        }
        // 不同子仓即使内容相同也保留；冲突后缀只取稳定来源，避免配置更新增殖。
        final key = '${site.key}_${site.originId}';
        uniqueSites[key] = site.copyWith(key: key);
      }
      final config = TvBoxConfig(
        spiderUrl: resolvedSpider,
        sites: uniqueSites.values.toList(growable: false),
        lives: _uniqueMaps(lives),
        parses: _uniqueMaps(parses),
        flags: flags.toSet().toList(growable: false),
        isPartial: isPartial,
        wallpaper: root.wallpaper,
      );
      lastError = null;
      return config;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      lastError =
          statusCode == null ? '网络连接失败或请求超时' : '订阅服务器返回 HTTP $statusCode';
      debugPrint('[TVBox] $lastError: $url');
    } catch (error) {
      lastError = '订阅解析失败';
      debugPrint('[TVBox] $lastError: $error');
    }
    return null;
  }

  String _resolveReference(String configUrl, String reference) {
    final clean = reference.trim();
    if (clean.isEmpty) return '';
    final separator = clean.indexOf(';md5;');
    final resource = separator < 0 ? clean : clean.substring(0, separator);
    final suffix = separator < 0 ? '' : clean.substring(separator);
    return '${Uri.parse(configUrl).resolve(resource)}$suffix';
  }

  dynamic _resolveExtension(String configUrl, dynamic ext) {
    if (ext is! String) return ext;
    final clean = ext.trim();
    // ext 也可能是内联 JSON、口令或协议参数；只展开明确的资源路径。
    if (clean.startsWith('{') || clean.startsWith('[')) return ext;
    if (clean.startsWith('./') ||
        clean.startsWith('../') ||
        clean.startsWith('/') ||
        RegExp(r'^[^\s{}]+\.(?:json|js|py|txt)(?:[?;].*)?$').hasMatch(clean)) {
      return _resolveReference(configUrl, clean);
    }
    return ext;
  }

  static List<Map<String, dynamic>> _uniqueMaps(
    List<Map<String, dynamic>> values,
  ) {
    final unique = <String, Map<String, dynamic>>{};
    for (final value in values) {
      unique.putIfAbsent(json.encode(value), () => value);
    }
    return unique.values.toList(growable: false);
  }

  TvBoxConfig? _decodeConfig(String rawContent) {
    final embedded = _extractWebpPayload(rawContent);
    if (embedded != null) {
      final embeddedJson = _tryParseJson(embedded);
      if (embeddedJson != null) return _buildConfigFromJson(embeddedJson);
    }
    final directJson = _tryParseJson(rawContent);
    if (directJson != null) return _buildConfigFromJson(directJson);

    for (final key in _magicKeys) {
      final decrypted = _decryptAesCbc(rawContent, key);
      if (decrypted == null) continue;
      final decryptedJson = _tryParseJson(decrypted);
      if (decryptedJson != null) return _buildConfigFromJson(decryptedJson);
    }
    return null;
  }

  /// 把任意国际化域名转换为 DNS 可解析的 ASCII host，避免 Dio 将中文 host
  /// 当作普通路径做百分号编码后请求不存在的地址。
  String _sanitizeUrl(String input) {
    var clean = input.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'http://$clean';
    }
    final uri = Uri.tryParse(clean);
    if (uri == null || uri.host.isEmpty) return clean;
    try {
      final unicodeHost = Uri.decodeComponent(uri.host);
      final asciiHost = domainToAscii(unicodeHost, validate: false);
      if (asciiHost.isNotEmpty) {
        clean = uri.replace(host: asciiHost).toString();
      }
    } catch (_) {
      // 非法第三方 host 保持原样交给网络层报告，不能破坏其 path/query。
    }
    return clean;
  }

  /// Tolerantly parses relaxed JSON strings by removing C-style comments, BOMs, and trailing commas.
  Map<String, dynamic>? _tryParseJson(String content) {
    try {
      final sanitized = sanitizeJson(content);
      final decoded = json.decode(sanitized);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (e) {
      debugPrint('JSON parse error after sanitization: $e');
    }
    return null;
  }

  /// Sanitizes relaxed / non-standard TVBox JSON (strips C-style comments, trailing commas, BOMs without breaking URLs).
  static String sanitizeJson(String input) {
    var text = input;

    // 1. Strip UTF-8 BOM if present
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }

    // 2. State-machine to strip // comments and /* */ comments without touching strings
    final sb = StringBuffer();
    bool inString = false;
    bool isEscaped = false;
    StringBuffer? pendingComma;
    int i = 0;
    final len = text.length;

    while (i < len) {
      final c = text[i];

      if (inString) {
        if (isEscaped) {
          sb.write(c);
          isEscaped = false;
        } else if (c == r'\') {
          sb.write(c);
          isEscaped = true;
        } else if (c == '"') {
          sb.write(c);
          inString = false;
        } else if (c.codeUnitAt(0) < 0x20) {
          // 部分订阅把换行、制表符直接写入 JSON 字符串。保留语义并转义，
          // 避免简单删除字符后把相邻标签意外拼接成另一个解析标识。
          switch (c) {
            case '\b':
              sb.write(r'\b');
            case '\t':
              sb.write(r'\t');
            case '\n':
              sb.write(r'\n');
            case '\f':
              sb.write(r'\f');
            case '\r':
              sb.write(r'\r');
            default:
              sb.write(
                r'\u' + c.codeUnitAt(0).toRadixString(16).padLeft(4, '0'),
              );
          }
        } else {
          sb.write(c);
        }
        i++;
        continue;
      }

      // Single-line comment //
      if (c == '/' && i + 1 < len && text[i + 1] == '/') {
        i += 2;
        while (i < len && text[i] != '\n' && text[i] != '\r') {
          i++;
        }
        continue;
      }

      // Multi-line comment /* ... */
      if (c == '/' && i + 1 < len && text[i + 1] == '*') {
        i += 2;
        while (i + 1 < len && !(text[i] == '*' && text[i + 1] == '/')) {
          i++;
        }
        i += 2;
        continue;
      }

      // 延迟写入字符串外的逗号，跨过空白和注释后再判断是否为尾逗号。
      // 字符串内的规则、URL 和正则表达式始终由上面的状态分支原样保留。
      if (pendingComma != null) {
        if (c.trim().isEmpty) {
          pendingComma.write(c);
          i++;
          continue;
        }
        if (c != '}' && c != ']') sb.write(pendingComma);
        pendingComma = null;
      }
      if (c == ',') {
        pendingComma = StringBuffer(',');
        i++;
        continue;
      }
      if (c == '"') {
        inString = true;
        isEscaped = false;
      }

      sb.write(c);
      i++;
    }

    if (pendingComma != null) sb.write(pendingComma);
    return sb.toString();
  }

  /// Extracts trailing base64/encrypted payload appended after WebP image data.
  String? _extractWebpPayload(String raw) {
    const marker = '**';
    final idx = raw.lastIndexOf(marker);
    if (idx != -1 && idx + 2 < raw.length) {
      final payload = raw.substring(idx + 2).trim();
      try {
        final decodedBytes = base64Decode(payload);
        return utf8.decode(decodedBytes);
      } catch (_) {
        return payload;
      }
    }
    return null;
  }

  /// Decrypts AES-128-CBC encoded strings using known TVBox encryption keys.
  String? _decryptAesCbc(String encryptedBase64, String keyStr) {
    try {
      final key = enc.Key.fromUtf8(keyStr);
      final iv = enc.IV.fromUtf8(keyStr);
      final encrypter =
          enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'));

      final decrypted = encrypter.decrypt64(encryptedBase64, iv: iv);
      return decrypted;
    } catch (_) {
      return null;
    }
  }

  TvBoxConfig _buildConfigFromJson(Map<String, dynamic> jsonMap) {
    final spider = jsonMap['spider']?.toString() ?? '';
    final rawSites = _listValue(jsonMap['sites']);
    final rawLives = _listValue(jsonMap['lives']);
    final rawParses = _listValue(jsonMap['parses']);
    final rawFlags = _listValue(jsonMap['flags']);
    final rawUrls = _listValue(jsonMap['urls']);

    final sites = <TvBoxSite>[];

    // Handle single warehouse sites
    for (final s in rawSites) {
      if (s is Map) {
        sites.add(TvBoxSite.fromJson(Map<String, dynamic>.from(s)));
      }
    }

    final warehouseUrls = <String>[];
    // 多仓条目是配置入口而不是站点 API，必须递归展开后才能进入片库。
    for (final u in rawUrls) {
      if (u is Map) {
        final subUrl = u['url']?.toString() ?? '';
        if (subUrl.isNotEmpty) warehouseUrls.add(subUrl);
      }
    }

    final lives = _mapValues(rawLives);
    final parses = _mapValues(rawParses);
    final flags = rawFlags.map((f) => f.toString()).toList();
    final wallpaper = jsonMap['wallpaper']?.toString();

    return TvBoxConfig(
      spiderUrl: spider,
      sites: sites,
      lives: lives,
      parses: parses,
      flags: flags,
      warehouseUrls: warehouseUrls,
      wallpaper: wallpaper,
    );
  }

  /// 将第三方配置的可选数组字段收敛为空数组，避免错误类型破坏其他有效站点。
  static List<dynamic> _listValue(dynamic value) {
    return value is List ? value : <dynamic>[];
  }

  /// 仅保留对象条目，同时兼容 JSON 解码器或持久层产生的动态键 Map。
  static List<Map<String, dynamic>> _mapValues(Iterable<dynamic> values) {
    return values
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
  }
}
