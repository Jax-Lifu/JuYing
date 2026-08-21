import 'dart:convert';

class TvboxLiveEntry {
  const TvboxLiveEntry({
    required this.name,
    this.playlistUri,
    this.inlinePlaylist,
    this.epgTemplate,
    this.httpHeaders = const {},
  });

  final String name;
  final Uri? playlistUri;
  final String? inlinePlaylist;
  final String? epgTemplate;
  final Map<String, String> httpHeaders;
}

class TvboxStandardSite {
  const TvboxStandardSite({
    required this.key,
    required this.name,
    required this.type,
    required this.apiUri,
    this.ext,
    this.httpHeaders = const {},
  });

  final String key;
  final String name;
  final int type;
  final Uri apiUri;
  final String? ext;
  final Map<String, String> httpHeaders;
}

abstract interface class TvboxExecutableSite {
  String get key;
  String get name;
  Uri get apiUri;
  String get ext;
  Map<String, String> get httpHeaders;
}

class TvboxJavascriptSite implements TvboxExecutableSite {
  const TvboxJavascriptSite({
    required this.key,
    required this.name,
    required this.apiUri,
    required this.ext,
    this.httpHeaders = const {},
  });

  @override
  final String key;
  @override
  final String name;
  @override
  final Uri apiUri;
  @override
  final String ext;
  @override
  final Map<String, String> httpHeaders;
}

class TvboxCspSite implements TvboxExecutableSite {
  const TvboxCspSite({
    required this.key,
    required this.name,
    required this.apiUri,
    required this.ext,
    required this.className,
    required this.jarUri,
    this.jarMd5,
    this.httpHeaders = const {},
  });

  @override
  final String key;
  @override
  final String name;
  @override
  final Uri apiUri;
  @override
  final String ext;
  final String className;
  final Uri jarUri;
  final String? jarMd5;
  @override
  final Map<String, String> httpHeaders;
}

class TvboxRepositoryEntry {
  const TvboxRepositoryEntry({required this.name, required this.configUri});

  final String name;
  final Uri configUri;
}

class TvboxPlaybackParser {
  const TvboxPlaybackParser({
    required this.name,
    required this.type,
    required this.urlPrefix,
    this.flags = const {},
    this.httpHeaders = const {},
  });

  final String name;
  final int type;
  final String urlPrefix;
  final Set<String> flags;
  final Map<String, String> httpHeaders;
}

/// 读取直接直播清单和标准 HTTP 数据接口，不解释可执行字段。
abstract final class TvboxConfigParser {
  /// type=1 为 JSON API，type=0 为受控 WebView 播放页。
  /// type=2/3/4 依赖 FongMi 内建聚合器或 JAR，当前不冒充为普通 HTTP 解析器。
  static List<TvboxPlaybackParser> parsePlaybackParsers(
    String input, {
    Uri? baseUri,
  }) {
    final decoded = _decode(input);
    final parses = decoded['parses'];
    if (parses is! List) return const [];
    final results = <TvboxPlaybackParser>[];
    final seen = <String>{};
    for (final value in parses) {
      if (value is! Map) continue;
      final type = value['type'] is int
          ? value['type'] as int
          : int.tryParse(value['type']?.toString() ?? '');
      if (type != 0 && type != 1) continue;
      final raw = value['url']?.toString().trim() ?? '';
      final parsed = Uri.tryParse(raw);
      final endpoint = parsed == null
          ? null
          : parsed.hasScheme
              ? parsed
              : baseUri?.resolveUri(parsed);
      if (!_isDirectHttpUri(endpoint) || !seen.add('$type|$endpoint')) continue;
      final ext = value['ext'];
      final flags = ext is Map && ext['flag'] is List
          ? (ext['flag'] as List)
              .map((entry) => entry.toString().trim().toLowerCase())
              .where((entry) => entry.isNotEmpty)
              .toSet()
          : const <String>{};
      final name = value['name']?.toString().trim() ?? '';
      results.add(TvboxPlaybackParser(
        name: name.isEmpty ? endpoint!.host : name,
        type: type!,
        urlPrefix: endpoint.toString(),
        flags: flags,
        httpHeaders: ext is Map ? _headers(ext) : const {},
      ));
    }
    return results;
  }

  static List<TvboxRepositoryEntry> parseRepositories(
    String input, {
    Uri? baseUri,
  }) {
    final decoded = _decode(input);
    final urls = decoded['urls'];
    if (urls is! List) return const [];
    final seen = <String>{};
    final results = <TvboxRepositoryEntry>[];
    for (final value in urls) {
      if (value is! Map) continue;
      final parsed = Uri.tryParse(value['url']?.toString().trim() ?? '');
      final uri = parsed == null
          ? null
          : parsed.hasScheme
              ? parsed
              : baseUri?.resolveUri(parsed);
      if (!_isDirectHttpUri(uri) || !seen.add(uri.toString())) continue;
      final name = value['name']?.toString().trim() ?? '';
      results.add(TvboxRepositoryEntry(
        name: name.isEmpty ? uri!.host : name,
        configUri: uri!,
      ));
    }
    return results;
  }

  static List<TvboxLiveEntry> parseDirectLives(
    String input, {
    Uri? baseUri,
  }) {
    final decoded = _decode(input);
    final lives = decoded['lives'];
    if (lives is! List) return const [];
    final results = <TvboxLiveEntry>[];
    for (final value in lives) {
      if (value is! Map) continue;
      final url = value['url']?.toString().trim() ?? '';
      final parsedUri = Uri.tryParse(url);
      final uri = parsedUri == null
          ? null
          : parsedUri.hasScheme
              ? parsedUri
              : baseUri?.resolveUri(parsedUri);
      final groups = value['groups'];
      final inlinePlaylist = groups is List ? jsonEncode(groups) : null;
      if (!_isDirectHttpUri(uri) && inlinePlaylist == null) continue;
      final name = value['name']?.toString().trim();
      results.add(TvboxLiveEntry(
        name: name == null || name.isEmpty ? 'TVBox 直播' : name,
        playlistUri: _isDirectHttpUri(uri) ? uri : null,
        inlinePlaylist: inlinePlaylist,
        epgTemplate: _epgTemplate(value['epg']?.toString(), baseUri),
        httpHeaders: _headers(value),
      ));
    }
    return results;
  }

  /// 提取可由内建 HTTP 客户端访问的声明式 XML/JSON 接口。
  static List<TvboxStandardSite> parseStandardSites(
    String input, {
    Uri? baseUri,
  }) {
    final decoded = _decode(input);
    final sites = decoded['sites'];
    if (sites is! List) return const [];
    final keys = <String>{};
    final results = <TvboxStandardSite>[];
    for (final value in sites) {
      if (value is! Map) continue;
      final type = switch (value['type']) {
        int() => value['type'] as int,
        String() => int.tryParse(value['type'] as String),
        _ => null,
      };
      if (type != 0 && type != 1 && type != 4) continue;
      final key = value['key']?.toString().trim() ?? '';
      final parsedApi = Uri.tryParse(value['api']?.toString().trim() ?? '');
      final api = parsedApi == null
          ? null
          : parsedApi.hasScheme
              ? parsedApi
              : baseUri?.resolveUri(parsedApi);
      if (key.isEmpty || !keys.add(key) || !_isDirectHttpUri(api)) continue;
      final name = value['name']?.toString().trim();
      results.add(TvboxStandardSite(
        key: key,
        name: name == null || name.isEmpty ? key : name,
        type: type!,
        apiUri: api!,
        ext: _extension(value['ext']),
        httpHeaders: _headers(value),
      ));
    }
    return results;
  }

  /// 只接入纯 HTTP(S) JavaScript/DRPY 站点。`csp_*`、`py_*` 与携带 JAR
  /// 的站点需要各自的运行时，不能误交给 JavaScript 宿主。
  static List<TvboxJavascriptSite> parseJavascriptSites(
    String input, {
    Uri? baseUri,
  }) {
    final decoded = _decode(input);
    final sites = decoded['sites'];
    if (sites is! List) return const [];
    final keys = <String>{};
    final results = <TvboxJavascriptSite>[];
    for (final value in sites) {
      if (value is! Map) continue;
      final type = switch (value['type']) {
        int() => value['type'] as int,
        String() => int.tryParse(value['type'] as String),
        _ => null,
      };
      if (type != 3 || _blank(value['jar']?.toString()) != null) continue;
      final key = value['key']?.toString().trim() ?? '';
      final rawApi = value['api']?.toString().trim() ?? '';
      if (rawApi.startsWith('csp_') || rawApi.startsWith('py_')) continue;
      final parsedApi = Uri.tryParse(rawApi);
      final api = parsedApi == null
          ? null
          : parsedApi.hasScheme
              ? parsedApi
              : baseUri?.resolveUri(parsedApi);
      final ext = _extension(value['ext']);
      if (key.isEmpty ||
          !keys.add(key) ||
          !_isDirectHttpUri(api) ||
          ext == null) {
        continue;
      }
      final name = value['name']?.toString().trim();
      results.add(TvboxJavascriptSite(
        key: key,
        name: name == null || name.isEmpty ? key : name,
        apiUri: api!,
        ext: _resolveExtension(ext, baseUri),
        httpHeaders: _headers(value),
      ));
    }
    return results;
  }

  static List<TvboxCspSite> parseCspSites(
    String input, {
    Uri? baseUri,
  }) {
    final decoded = _decode(input);
    final sites = decoded['sites'];
    if (sites is! List) return const [];
    final globalJar = _jar(decoded['spider'], baseUri);
    final keys = <String>{};
    final results = <TvboxCspSite>[];
    for (final value in sites) {
      if (value is! Map) continue;
      final type = value['type'] is int
          ? value['type'] as int
          : int.tryParse(value['type']?.toString() ?? '');
      final api = value['api']?.toString().trim() ?? '';
      if (type != 3 || !api.startsWith('csp_')) continue;
      final key = value['key']?.toString().trim() ?? '';
      final jar = _jar(value['jar'], baseUri) ?? globalJar;
      if (key.isEmpty || !keys.add(key) || jar == null) continue;
      final name = value['name']?.toString().trim() ?? '';
      results.add(TvboxCspSite(
        key: key,
        name: name.isEmpty ? key : name,
        apiUri: jar.$1,
        ext: _resolveExtension(_extension(value['ext']) ?? '', baseUri),
        className: 'com.github.catvod.spider.${api.substring(4)}',
        jarUri: jar.$1,
        jarMd5: jar.$2,
        httpHeaders: _headers(value),
      ));
    }
    return results;
  }

  static (Uri, String?)? _jar(Object? raw, Uri? baseUri) {
    final value = _blank(raw?.toString());
    if (value == null) return null;
    final parts = value.split(';');
    final parsed = Uri.tryParse(parts.first.trim());
    final uri = parsed == null
        ? null
        : parsed.hasScheme
            ? parsed
            : baseUri?.resolveUri(parsed);
    if (!_isDirectHttpUri(uri)) return null;
    String? md5;
    for (var index = 1; index < parts.length; index++) {
      final candidate = parts[index].trim();
      if (RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(candidate)) {
        md5 = candidate.toLowerCase();
      }
    }
    return (uri!, md5);
  }

  static Map _decode(String input) {
    final normalized = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final decoded = jsonDecode(_stripCommentsAndTrailingCommas(normalized));
    if (decoded is! Map) {
      throw const FormatException('TVBox 配置根节点必须是对象');
    }
    return decoded;
  }

  static String? _epgTemplate(String? value, Uri? baseUri) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = Uri.tryParse(value.trim());
    final uri = parsed == null
        ? null
        : parsed.hasScheme
            ? parsed
            : baseUri?.resolveUri(parsed);
    return _isDirectHttpUri(uri) ? uri.toString() : null;
  }

  static String? _blank(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static String? _extension(Object? value) {
    if (value is Map || value is List) return jsonEncode(value);
    return _blank(value?.toString());
  }

  static String _resolveExtension(String value, Uri? baseUri) {
    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.hasScheme || baseUri == null) return value;
    // JSON/脚本文本不是相对 URL；只解析看起来像路径的扩展值。
    if (value.startsWith('./') ||
        value.startsWith('../') ||
        value.startsWith('/')) {
      return baseUri.resolveUri(parsed).toString();
    }
    return value;
  }

  static Map<String, String> _headers(Map value) {
    final result = <String, String>{};
    final header = value['header'];
    if (header is Map) {
      for (final entry in header.entries) {
        final name = entry.key.toString().trim().toLowerCase();
        final headerValue = entry.value?.toString().trim() ?? '';
        final canonical = switch (name) {
          'user-agent' => 'User-Agent',
          'origin' => 'Origin',
          'referer' || 'referrer' => 'Referer',
          _ => null,
        };
        if (canonical != null && headerValue.isNotEmpty) {
          result[canonical] = headerValue;
        }
      }
    }
    const aliases = {
      'ua': 'User-Agent',
      'origin': 'Origin',
      'referer': 'Referer',
    };
    for (final alias in aliases.entries) {
      final headerValue = value[alias.key]?.toString().trim() ?? '';
      if (headerValue.isNotEmpty) result[alias.value] = headerValue;
    }
    return result;
  }

  static bool _isDirectHttpUri(Uri? uri) {
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host != 'localhost' &&
        host != '::1' &&
        !host.startsWith('127.') &&
        !host.startsWith('10.') &&
        !host.startsWith('192.168.') &&
        !RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(host);
  }

  static String _stripCommentsAndTrailingCommas(String input) {
    final withoutComments = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var index = 0; index < input.length; index++) {
      final current = input[index];
      final next = index + 1 < input.length ? input[index + 1] : '';
      if (inString) {
        if (current.codeUnitAt(0) < 0x20) {
          withoutComments.write(switch (current) {
            '\n' => r'\n',
            '\r' => r'\r',
            '\t' => r'\t',
            _ =>
              '\\u${current.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
          });
          escaped = false;
          continue;
        }
        withoutComments.write(current);
        if (escaped) {
          escaped = false;
        } else if (current == r'\') {
          escaped = true;
        } else if (current == '"') {
          inString = false;
        }
        continue;
      }
      if (current == '"') {
        inString = true;
        withoutComments.write(current);
      } else if (current == '/' && next == '/') {
        while (index + 1 < input.length && input[index + 1] != '\n') {
          index++;
        }
      } else if (current == '/' && next == '*') {
        index += 2;
        while (index < input.length &&
            !(input[index] == '*' &&
                index + 1 < input.length &&
                input[index + 1] == '/')) {
          index++;
        }
        if (index < input.length) index++;
      } else {
        withoutComments.write(current);
      }
    }

    final output = StringBuffer();
    final text = withoutComments.toString();
    inString = false;
    escaped = false;
    for (var index = 0; index < text.length; index++) {
      final current = text[index];
      if (inString) {
        output.write(current);
        if (escaped) {
          escaped = false;
        } else if (current == r'\') {
          escaped = true;
        } else if (current == '"') {
          inString = false;
        }
        continue;
      }
      if (current == '"') {
        inString = true;
        output.write(current);
      } else if (current == ',') {
        var cursor = index + 1;
        while (cursor < text.length && text[cursor].trim().isEmpty) {
          cursor++;
        }
        if (cursor >= text.length ||
            (text[cursor] != '}' && text[cursor] != ']')) {
          output.write(current);
        }
      } else {
        output.write(current);
      }
    }
    return output.toString();
  }
}
