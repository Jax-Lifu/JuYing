import 'dart:convert';

class M3uChannel {
  const M3uChannel({
    required this.id,
    required this.name,
    required this.streamUri,
    this.alternateStreamUris = const [],
    this.lineLabels = const [],
    this.group,
    this.logoUri,
    this.officialPageUri,
    this.epgChannelId,
    this.channelNumber,
    this.httpHeaders = const {},
    this.alternateHttpHeaders = const [],
  });

  final String id;
  final String name;
  final Uri streamUri;
  final List<Uri> alternateStreamUris;
  final List<String> lineLabels;
  final String? group;
  final Uri? logoUri;
  final Uri? officialPageUri;
  final String? epgChannelId;
  final String? channelNumber;
  final Map<String, String> httpHeaders;
  final List<Map<String, String>> alternateHttpHeaders;
}

abstract final class M3uPlaylistParser {
  static const maxChannels = 10000;

  static List<M3uChannel> parse(
    String input, {
    Uri? baseUri,
    Map<String, String> defaultHeaders = const {},
  }) {
    final withoutBom = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final normalized = withoutBom.trimLeft();
    if (normalized.startsWith('[')) {
      return _parseJson(normalized, baseUri, _safeHeaders(defaultHeaders));
    }
    if (_containsM3uHeader(withoutBom)) {
      return _parseM3u(withoutBom, baseUri, _safeHeaders(defaultHeaders));
    }
    return _parseTxt(withoutBom, baseUri, _safeHeaders(defaultHeaders));
  }

  static List<M3uChannel> _parseJson(
    String input,
    Uri? baseUri,
    Map<String, String> defaultHeaders,
  ) {
    final decoded = jsonDecode(input);
    if (decoded is! List) {
      throw const FormatException('直播 JSON 必须是分组数组');
    }
    final channels = <M3uChannel>[];
    for (final groupValue in decoded) {
      if (groupValue is! Map || _hasGroupPassword(groupValue['pass'])) {
        continue;
      }
      final group = groupValue['name']?.toString().trim();
      final entries = groupValue['channel'];
      if (entries is! List) continue;
      for (final channelValue in entries) {
        if (channelValue is! Map) continue;
        final name = channelValue['name']?.toString().trim() ?? '';
        final channelHeaders = {
          ...defaultHeaders,
          ..._headers(channelValue),
        };
        final lines = channelValue['urls'] is List
            ? (channelValue['urls'] as List)
                .map((value) => _line(
                      value.toString(),
                      baseUri: baseUri,
                      headers: channelHeaders,
                    ))
                .whereType<_LiveLine>()
                .toList(growable: false)
            : const <_LiveLine>[];
        if (name.isEmpty || lines.isEmpty) continue;
        channels.add(M3uChannel(
          id: base64Url.encode(utf8.encode(lines.first.uri.toString())),
          name: name,
          streamUri: lines.first.uri,
          alternateStreamUris:
              lines.skip(1).map((line) => line.uri).toList(growable: false),
          alternateHttpHeaders:
              lines.skip(1).map((line) => line.headers).toList(growable: false),
          lineLabels:
              lines.map((line) => line.label ?? '').toList(growable: false),
          group: group == null || group.isEmpty ? null : group,
          logoUri:
              _publicUri(channelValue['logo']?.toString(), baseUri: baseUri),
          epgChannelId: (channelValue['tvgId'] ?? channelValue['tvgName'])
              ?.toString()
              .trim(),
          channelNumber: channelValue['number']?.toString().trim(),
          httpHeaders: lines.first.headers,
        ));
        if (channels.length >= maxChannels) return channels;
      }
    }
    return channels;
  }

  static List<M3uChannel> _parseM3u(
    String input,
    Uri? baseUri,
    Map<String, String> defaultHeaders,
  ) {
    final lines = const LineSplitter()
        .convert(input)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final channels = <_PendingChannel>[];
    String? metadata;
    var settings = <String, String>{};
    final headerIndex = lines.indexWhere(
      (line) => line.toUpperCase().startsWith('#EXTM3U'),
    );
    for (final line in lines.skip(headerIndex + 1)) {
      if (line.startsWith('#EXTINF:')) {
        metadata = line;
        continue;
      }
      if (_isHeaderDirective(line)) {
        settings = {...settings, ..._directiveHeaders(line)};
        continue;
      }
      if (line.startsWith('#')) continue;
      if (metadata == null) continue;
      final name = _name(metadata);
      final headers = {
        ...defaultHeaders,
        if (_attribute(metadata, 'http-user-agent') case final ua?)
          'User-Agent': ua,
        ...settings,
      };
      final parsedLine = _line(line, baseUri: baseUri, headers: headers);
      if (parsedLine != null && name.isNotEmpty) {
        final group = _attribute(metadata, 'group-title');
        final existing = channels
            .where((channel) => channel.name == name && channel.group == group)
            .firstOrNull;
        final channel = existing ??
            _PendingChannel(
              name: name,
              group: group,
              logoUri: _publicUri(_attribute(metadata, 'tvg-logo'),
                  baseUri: baseUri),
              officialPageUri: _publicUri(
                _attribute(metadata, 'homepage') ??
                    _attribute(metadata, 'tvg-url'),
                baseUri: baseUri,
              ),
              epgChannelId: _attribute(metadata, 'tvg-id'),
              channelNumber: _attribute(metadata, 'tvg-chno'),
            );
        if (existing == null) channels.add(channel);
        channel.lines.add(parsedLine);
      }
      metadata = null;
      settings = <String, String>{};
      if (channels.length >= maxChannels) break;
    }
    return channels.map((channel) => channel.build()).toList(growable: false);
  }

  static List<M3uChannel> _parseTxt(
    String input,
    Uri? baseUri,
    Map<String, String> defaultHeaders,
  ) {
    final pending = <_PendingChannel>[];
    var hasTxtEntry = false;
    String? group;
    var settings = <String, String>{};
    for (final raw in const LineSplitter().convert(input)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (_isHeaderDirective(line)) {
        settings = {...settings, ..._directiveHeaders(line)};
        continue;
      }
      if (line.endsWith(',#genre#')) {
        group = line.substring(0, line.length - ',#genre#'.length).trim();
        settings = <String, String>{};
        continue;
      }
      // FongMi TXT 频道行要求播放字段包含 `://`。配置 JSON、解析器
      // 规则等文本也常含逗号和 URL，不能因为能基于 baseUri 拼出地址就
      // 被误认成直播频道。
      if (line.startsWith('{') ||
          line.startsWith('}') ||
          line.startsWith('[') ||
          line.startsWith(']') ||
          line.startsWith('"')) {
        continue;
      }
      final comma = line.indexOf(',');
      if (comma <= 0) continue;
      final name = line.substring(0, comma).trim();
      final lines = line
          .substring(comma + 1)
          .split('#')
          .where(_isAbsoluteTxtStream)
          .map((value) => _line(value,
              baseUri: baseUri, headers: {...defaultHeaders, ...settings}))
          .whereType<_LiveLine>()
          .toList(growable: false);
      if (name.isEmpty || lines.isEmpty) continue;
      hasTxtEntry = true;
      final existing = pending
          .where((channel) => channel.name == name && channel.group == group)
          .firstOrNull;
      final channel = existing ?? _PendingChannel(name: name, group: group);
      if (existing == null) pending.add(channel);
      channel.lines.addAll(lines);
      if (pending.length >= maxChannels) break;
    }
    if (!hasTxtEntry) {
      throw const FormatException('不是有效的直播清单');
    }
    return pending.map((channel) => channel.build()).toList(growable: false);
  }

  static bool _isAbsoluteTxtStream(String value) {
    final pipe = value.indexOf('|');
    final stream = (pipe < 0 ? value : value.substring(0, pipe)).trim();
    final separator = stream.lastIndexOf(r'$');
    final rawUri =
        separator > 0 ? stream.substring(0, separator).trim() : stream;
    return rawUri.startsWith('http://') || rawUri.startsWith('https://');
  }

  static String _name(String metadata) {
    final comma = metadata.lastIndexOf(',');
    return comma < 0 ? '' : metadata.substring(comma + 1).trim();
  }

  static String? _attribute(String metadata, String name) {
    final match =
        RegExp('$name="([^"]*)"', caseSensitive: false).firstMatch(metadata);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static _LiveLine? _line(
    String value, {
    Uri? baseUri,
    Map<String, String> headers = const {},
  }) {
    final pipe = value.indexOf('|');
    final rawStream = pipe < 0 ? value.trim() : value.substring(0, pipe).trim();
    final separator = rawStream.lastIndexOf(r'$');
    final uri = _publicUri(
      separator > 0 ? rawStream.substring(0, separator).trim() : rawStream,
      baseUri: baseUri,
    );
    if (!_publicHttpUri(uri)) return null;
    final label =
        separator > 0 ? rawStream.substring(separator + 1).trim() : null;
    final inlineHeaders = pipe < 0
        ? const <String, String>{}
        : _queryHeaders(value.substring(pipe + 1));
    return _LiveLine(
      uri!,
      label == null || label.isEmpty ? null : label,
      {..._safeHeaders(headers), ...inlineHeaders},
    );
  }

  static Map<String, String> _headers(Map value) {
    final result = <String, String>{};
    final headers = value['header'];
    if (headers is Map) {
      for (final entry in headers.entries) {
        final key = entry.key.toString().trim();
        final headerValue = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && headerValue.isNotEmpty) result[key] = headerValue;
      }
    }
    const aliases = {
      'ua': 'User-Agent',
      'origin': 'Origin',
      'referer': 'Referer'
    };
    for (final entry in aliases.entries) {
      final headerValue = value[entry.key]?.toString().trim() ?? '';
      if (headerValue.isNotEmpty) result[entry.value] = headerValue;
    }
    return _safeHeaders(result);
  }

  static bool _isHeaderDirective(String line) {
    final lower = line.toLowerCase();
    return lower.startsWith('ua=') ||
        lower.startsWith('origin=') ||
        lower.startsWith('referer=') ||
        lower.startsWith('referrer=') ||
        lower.startsWith('header=') ||
        lower.startsWith('#exthttp:') ||
        lower.startsWith('#extvlcopt:http-user-agent=') ||
        lower.startsWith('#extvlcopt:http-referrer=') ||
        lower.startsWith('#extvlcopt:http-origin=');
  }

  static Map<String, String> _directiveHeaders(String line) {
    final lower = line.toLowerCase();
    String afterEquals() => line
        .substring(line.indexOf('=') + 1)
        .trim()
        .replaceAll(RegExp(r'^"|"$'), '');
    if (lower.startsWith('ua=') || lower.contains('http-user-agent=')) {
      return {'User-Agent': afterEquals()};
    }
    if (lower.startsWith('origin=') || lower.contains('http-origin=')) {
      return {'Origin': afterEquals()};
    }
    if (lower.startsWith('referer=') ||
        lower.startsWith('referrer=') ||
        lower.contains('http-referrer=')) {
      return {'Referer': afterEquals()};
    }
    final separator = line.indexOf(':');
    final equals = line.indexOf('=');
    final raw = lower.startsWith('#exthttp:')
        ? line.substring(separator + 1).trim()
        : equals >= 0
            ? line.substring(equals + 1).trim()
            : '';
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? _headers({'header': decoded}) : const {};
    } catch (_) {
      return const {};
    }
  }

  static Map<String, String> _queryHeaders(String raw) {
    final result = <String, String>{};
    for (final item in raw.split('&')) {
      final separator = item.indexOf('=');
      if (separator <= 0) continue;
      try {
        result[Uri.decodeQueryComponent(item.substring(0, separator).trim())] =
            Uri.decodeQueryComponent(item.substring(separator + 1).trim());
      } catch (_) {}
    }
    return _safeHeaders(result);
  }

  static Map<String, String> _safeHeaders(Map<String, String> headers) {
    const names = {
      'user-agent': 'User-Agent',
      'origin': 'Origin',
      'referer': 'Referer',
      'referrer': 'Referer',
    };
    final result = <String, String>{};
    for (final entry in headers.entries) {
      final name = names[entry.key.trim().toLowerCase()];
      final value = entry.value.trim();
      if (name != null &&
          value.isNotEmpty &&
          !value.contains('\r') &&
          !value.contains('\n')) {
        result[name] = value;
      }
    }
    return result;
  }

  static bool _containsM3uHeader(String input) => const LineSplitter()
      .convert(input)
      .any((line) => line.trimLeft().toUpperCase().startsWith('#EXTM3U'));

  static bool _hasGroupPassword(Object? value) {
    if (value == null || value == false) return false;
    if (value is num && value == 0) return false;
    final text = value.toString().trim().toLowerCase();
    return text.isNotEmpty && text != 'false' && text != '0' && text != 'null';
  }

  static Uri? _publicUri(String? raw, {Uri? baseUri}) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null) return null;
    final resolved = parsed.hasScheme ? parsed : baseUri?.resolveUri(parsed);
    return _publicHttpUri(resolved) ? resolved : null;
  }

  static bool _publicHttpUri(Uri? uri) {
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
}

class _LiveLine {
  const _LiveLine(this.uri, this.label, this.headers);
  final Uri uri;
  final String? label;
  final Map<String, String> headers;
}

class _PendingChannel {
  _PendingChannel({
    required this.name,
    this.group,
    this.logoUri,
    this.officialPageUri,
    this.epgChannelId,
    this.channelNumber,
  });

  final String name;
  final String? group;
  final Uri? logoUri;
  final Uri? officialPageUri;
  final String? epgChannelId;
  final String? channelNumber;
  final List<_LiveLine> lines = [];

  M3uChannel build() => M3uChannel(
        id: base64Url.encode(utf8.encode(lines.first.uri.toString())),
        name: name,
        streamUri: lines.first.uri,
        alternateStreamUris:
            lines.skip(1).map((line) => line.uri).toList(growable: false),
        lineLabels:
            lines.map((line) => line.label ?? '').toList(growable: false),
        group: group,
        logoUri: logoUri,
        officialPageUri: officialPageUri,
        epgChannelId: epgChannelId,
        channelNumber: channelNumber,
        httpHeaders: lines.first.headers,
        alternateHttpHeaders:
            lines.skip(1).map((line) => line.headers).toList(growable: false),
      );
}
