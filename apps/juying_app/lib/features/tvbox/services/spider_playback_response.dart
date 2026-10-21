import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';

/// Resolves the selected episode through the parsers from its own warehouse.
/// Web parsers return a page for the shared WebView; JSON parsers make one HTTP
/// request. Native-extension parsers remain explicit errors, and network or
/// cancellation errors propagate unchanged so callers can own retry/exit policy.
Future<PlaybackEpisode> resolveSpiderPlayback({
  required TvBoxSite site,
  required PlaybackEpisode episode,
  required Map<String, dynamic> response,
  required Dio dio,
}) async {
  final playUrl = response['playUrl']?.toString().trim() ?? '';
  final flag = response['flag']?.toString() ?? '';
  Map<String, dynamic>? parser;
  if (playUrl.startsWith('json:')) {
    parser = {'type': 1, 'url': playUrl.substring(5)};
  } else if (playUrl.startsWith('parse:')) {
    final name = playUrl.substring(6);
    for (final candidate in site.parses) {
      if (candidate['name'] == name) {
        parser = candidate;
        break;
      }
    }
    if (parser == null) throw UnsupportedError('当前站点未配置指定解析器');
  } else if (_enabled(response['jx']) ||
      (playUrl.isEmpty &&
          site.parses.isNotEmpty &&
          site.flags.contains(flag))) {
    // Respect configured order and per-parser platform flags, without enabling
    // native JAR methods or inventing parser endpoints outside this warehouse.
    for (final candidate in site.parses) {
      final flags = _parserExt(candidate)['flag'];
      if (flags is List && flags.isNotEmpty && !flags.contains(flag)) continue;
      if (!const {0, 1}.contains(_parserType(candidate))) continue;
      parser = candidate;
      break;
    }
    if (parser == null) throw UnsupportedError('当前站点没有可用的网页或 JSON 解析器');
  }
  if (parser == null) {
    return parseSpiderPlaybackResponse(episode: episode, response: response);
  }
  final type = _parserType(parser);
  if (type != 0 && type != 1) {
    throw UnsupportedError('该解析器需要尚未支持的原生扩展');
  }
  final prefix = parser['url']?.toString().trim() ?? '';
  final target = response['url']?.toString().trim() ?? '';
  if (!_isHttpUrl(prefix) || target.isEmpty) {
    throw const FormatException('解析器或节目地址为空或无效');
  }
  final mediaHeaders = _mergeHeaders([
    episode.headers,
    _parseHeaders(response['header']),
  ]);
  // A configured parser is a separate origin. Its credentials apply only to
  // that request; media credentials must never be sent there or overwritten.
  final parserHeaders = _parseHeaders(_parserExt(parser)['header']) ?? {};
  final requestUrl = '$prefix$target';
  if (type == 0) {
    return parseSpiderPlaybackResponse(
      episode: episode,
      webHeaders: parserHeaders,
      response: {
        'url': requestUrl,
        'parse': 1,
        'header': mediaHeaders,
      },
    );
  }
  final resolved = await dio.get<dynamic>(requestUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: parserHeaders,
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
      ));
  final value = resolved.data is String
      ? json.decode(resolved.data as String)
      : resolved.data;
  if (value is! Map) throw const FormatException('JSON 解析器没有返回对象');
  final nested =
      value['data'] is Map ? value['data'] as Map : const <String, dynamic>{};
  var url = value['url']?.toString().trim() ?? '';
  if (url.isEmpty) url = nested['url']?.toString().trim() ?? '';
  if (url.isEmpty) throw const FormatException('JSON 解析器没有返回播放地址');
  return parseSpiderPlaybackResponse(episode: episode, response: {
    // JSON parser output is a resolved URL by contract, including signed URLs
    // without a suffix. Explicit parse=1 and HTML pages still require WebView.
    'parse': 0,
    ...Map<String, dynamic>.from(nested),
    ...Map<String, dynamic>.from(value),
    'url': url,
    'header': _mergeHeaders([
      mediaHeaders,
      _parseHeaders(nested['header']),
      _parseHeaders(value['header']),
      _responseHeaders(nested),
      _responseHeaders(value),
    ]),
  });
}

int _parserType(Map<String, dynamic> parser) =>
    int.tryParse(parser['type']?.toString() ?? '0') ?? -1;

Map _parserExt(Map<String, dynamic> parser) {
  final ext = parser['ext'];
  if (ext is Map) return ext;
  if (ext is String) {
    try {
      final decoded = json.decode(ext);
      if (decoded is Map) return decoded;
    } on FormatException {
      // An absent/malformed optional extension does not invent request headers.
    }
  }
  return const {};
}

Map<String, String> _responseHeaders(Map response) => {
      for (final entry in response.entries)
        if (entry.value is String &&
            const {'user-agent', 'ua', 'referer', 'cookie', 'origin'}
                .contains(entry.key.toString().toLowerCase()))
          entry.key.toString().toLowerCase() == 'ua'
              ? 'User-Agent'
              : entry.key.toString(): entry.value as String,
    };

/// Converts CatVod player results without passing unresolved web pages to mpv.
///
/// The selected episode supplies display metadata only. A player response can
/// replace its URL and headers, or require the shared WebView resolver. Global
/// and named parser modes must first pass through [resolveSpiderPlayback].
PlaybackEpisode parseSpiderPlaybackResponse({
  required PlaybackEpisode episode,
  required Map<String, dynamic> response,
  Map<String, String>? webHeaders,
}) {
  if (_enabled(response['jx'])) {
    throw UnsupportedError('该节目需要外部解析器，当前尚未接入');
  }
  final playUrl = response['playUrl']?.toString().trim() ?? '';
  if (playUrl.startsWith('json:') || playUrl.startsWith('parse:')) {
    throw UnsupportedError('该节目需要 JSON 或指定解析器，当前尚未接入');
  }
  var url = response['url']?.toString().trim() ?? '';
  final parse = _enabled(response['parse']);
  if (url.isEmpty) {
    // Some minimal spiders omit player results for a known media URL. Never
    // apply that fallback to an episode page or to a requested parsing mode.
    if (!parse && playUrl.isEmpty && _isMediaUrl(episode.url)) {
      url = episode.url;
    } else {
      throw const FormatException('Spider 没有返回可解析的播放地址');
    }
  }
  if (playUrl.isNotEmpty) {
    if (!_isHttpUrl(playUrl)) {
      throw const FormatException('Spider 返回的解析地址无效');
    }
    url = '$playUrl$url';
  }
  if (!_isHttpUrl(url)) {
    throw const FormatException('Spider 返回的播放地址无效');
  }
  final headers = _mergeHeaders([
    episode.headers,
    _parseHeaders(response['header']),
  ]);
  return PlaybackEpisode(
    name: episode.name,
    url: url,
    sortIndex: episode.sortIndex,
    duration: episode.duration,
    badge: episode.badge,
    headers: headers.isEmpty ? null : headers,
    webHeaders: webHeaders ?? episode.webHeaders,
    officialPageUrl: episode.officialPageUrl,
    thumbnailUrl: episode.thumbnailUrl,
    requiresWebView: parse ||
        playUrl.isNotEmpty ||
        RegExp(r'\.html?$', caseSensitive: false)
            .hasMatch(Uri.parse(url).path) ||
        (response['parse'] == null && !_isMediaUrl(url)),
  );
}

bool _enabled(Object? value) => value == true || value?.toString() == '1';

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      <String>{'http', 'https'}.contains(uri.scheme) &&
      uri.host.isNotEmpty;
}

bool _isMediaUrl(String value) =>
    _isHttpUrl(value) &&
    RegExp(r'\.(m3u8|mp4|mkv|flv|mpd|ts|mov|webm|m4v|avi)$',
            caseSensitive: false)
        .hasMatch(Uri.parse(value).path);

Map<String, String>? _parseHeaders(Object? value) {
  if (value is String) {
    try {
      value = json.decode(value);
    } on FormatException {
      return null;
    }
  }
  if (value is! Map) return null;
  return value.map((key, value) => MapEntry(key.toString(), value.toString()));
}

Map<String, String> _mergeHeaders(List<Map<String, String>?> layers) {
  final headers = <String, String>{};
  for (final layer in layers) {
    for (final entry in layer?.entries ?? const <MapEntry<String, String>>[]) {
      // HTTP field names are case-insensitive; two different spellings would
      // otherwise send conflicting authentication or User-Agent values to mpv.
      headers.removeWhere(
          (key, _) => key.toLowerCase() == entry.key.toLowerCase());
      headers[entry.key] = entry.value;
    }
  }
  return headers;
}
