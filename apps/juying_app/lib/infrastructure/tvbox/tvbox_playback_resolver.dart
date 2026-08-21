import 'dart:convert';

import 'package:http/http.dart' as http;

import '../network/safe_text_response_decoder.dart';
import 'tvbox_config_parser.dart';

class TvboxResolvedPlayback {
  const TvboxResolvedPlayback({
    required this.pageUri,
    this.streamUri,
    this.httpHeaders = const {},
  });

  final Uri pageUri;
  final Uri? streamUri;
  final Map<String, String> httpHeaders;
}

/// 执行配置声明的 HTTP JSON 解析，或直接回退到原生直连播放。
class TvboxPlaybackResolver {
  TvboxPlaybackResolver({
    required http.Client client,
    required List<TvboxPlaybackParser> parsers,
  })  : _client = client,
        _parsers = parsers;

  static const maxParserResponseBytes = 1024 * 1024;
  final http.Client _client;
  final List<TvboxPlaybackParser> _parsers;

  Future<TvboxResolvedPlayback> resolve(
    Uri input, {
    String flag = '',
    Map<String, String> httpHeaders = const {},
    bool forceParse = false,
  }) async {
    final looksNative = _looksLikeNativeStream(input);
    if (!forceParse && looksNative) {
      return TvboxResolvedPlayback(
        pageUri: input,
        streamUri: input,
        httpHeaders: httpHeaders,
      );
    }

    final ordered = _orderedParsers(flag);
    final jsonParsers = ordered.where((entry) => entry.type == 1).toList();
    if (jsonParsers.isNotEmpty) {
      final jsonResults = await Future.wait(
        jsonParsers
            .take(4)
            .map((parser) => _resolveJson(parser, input, httpHeaders)),
      );
      final jsonResult =
          jsonResults.whereType<TvboxResolvedPlayback>().firstOrNull;
      if (jsonResult != null) return jsonResult;
    }

    // 若非强制解析且非网页/已知门户，直接作为媒体流直连播放
    if (!forceParse &&
        !_looksLikeHtmlPage(input) &&
        !_looksLikeKnownWebPortal(input)) {
      return TvboxResolvedPlayback(
        pageUri: input,
        streamUri: input,
        httpHeaders: httpHeaders,
      );
    }

    final web = ordered.where((entry) => entry.type == 0).firstOrNull;
    return TvboxResolvedPlayback(
      pageUri: web == null ? input : _append(web.urlPrefix, input),
      streamUri: null,
      httpHeaders: {...httpHeaders, ...?web?.httpHeaders},
    );
  }

  Future<TvboxResolvedPlayback?> _resolveJson(
    TvboxPlaybackParser parser,
    Uri input,
    Map<String, String> httpHeaders,
  ) async {
    try {
      final requestUri = _append(parser.urlPrefix, input);
      final response = await _client
          .get(requestUri, headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            ...parser.httpHeaders,
          })
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (response.bodyBytes.length > maxParserResponseBytes) return null;
      final text = await SafeTextResponseDecoder.decode(
        response.bodyBytes,
        maxDecodedBytes: maxParserResponseBytes,
        contentEncoding: response.headers['content-encoding'],
      );
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;

      Uri? stream;
      Object? rawHeader;

      if (decoded['url'] != null) {
        stream = _safeUri(decoded['url']);
      } else if (decoded['data'] is Map) {
        final dataMap = decoded['data'] as Map;
        stream = _safeUri(dataMap['url']);
        rawHeader = dataMap['header'] ?? dataMap['headers'];
      } else if (decoded['data'] is String) {
        stream = _safeUri(decoded['data']);
      } else if (decoded['playurl'] != null) {
        stream = _safeUri(decoded['playurl']);
      } else if (decoded['vurl'] != null) {
        stream = _safeUri(decoded['vurl']);
      } else if (decoded['result'] is String) {
        stream = _safeUri(decoded['result']);
      }

      if (stream == null) return null;

      rawHeader ??= decoded['header'] ?? decoded['headers'];

      return TvboxResolvedPlayback(
        pageUri: stream,
        streamUri: stream,
        httpHeaders: {
          ...httpHeaders,
          ...parser.httpHeaders,
          ..._headers(rawHeader),
        },
      );
    } catch (_) {
      return null;
    }
  }

  List<TvboxPlaybackParser> _orderedParsers(String flag) {
    final normalized = flag.trim().toLowerCase();
    return <TvboxPlaybackParser>{
      ..._parsers.where(
          (entry) => normalized.isNotEmpty && entry.flags.contains(normalized)),
      ..._parsers.where((entry) => entry.flags.isEmpty),
      ..._parsers.where((entry) =>
          entry.flags.isNotEmpty && !entry.flags.contains(normalized)),
    }.toList(growable: false);
  }

  Uri _append(String prefix, Uri input) {
    final raw = input.toString();
    final encoded = Uri.encodeComponent(raw);
    return _safeUri('$prefix$encoded') ?? Uri.parse('$prefix$raw');
  }

  Uri? _safeUri(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  bool _looksLikeHtmlPage(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.endsWith('.html') ||
        path.endsWith('.htm') ||
        path.endsWith('.shtml') ||
        path.endsWith('.php') ||
        path.endsWith('.jsp') ||
        path.endsWith('.asp') ||
        path.endsWith('.aspx');
  }

  bool _looksLikeKnownWebPortal(Uri uri) {
    final host = uri.host.toLowerCase();
    const portals = [
      'v.qq.com',
      'youku.com',
      'iqiyi.com',
      'mgtv.com',
      'bilibili.com',
      'sohu.com',
      'le.com',
      '1905.com',
      'ixigua.com',
      'miguvideo.com',
      'pptv.com',
    ];
    return portals.any((portal) => host == portal || host.endsWith('.$portal'));
  }

  bool _looksLikeNativeStream(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'rtmp' || scheme == 'rtsp' || scheme == 'mms') return true;
    final path = uri.path.toLowerCase();
    final full = uri.toString().toLowerCase();

    // 网页文件或第三方视频详情页不能冒充原生流
    if (_looksLikeHtmlPage(uri)) {
      return false;
    }

    const extensions = [
      '.m3u8',
      '.mp4',
      '.mkv',
      '.flv',
      '.mpd',
      '.mp3',
      '.m4a',
      '.ts',
      '.mov',
      '.avi',
      '.webm',
      '.m3u',
    ];
    for (final ext in extensions) {
      if (path.endsWith(ext) ||
          path.contains('$ext/') ||
          full.contains('$ext?') ||
          full.contains('$ext&') ||
          full.contains('$ext#') ||
          full.contains(ext)) {
        return true;
      }
    }
    return false;
  }

  Map<String, String> _headers(Object? raw) {
    Object? decoded = raw;
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {}
    }
    if (decoded is! Map) return const {};
    final result = <String, String>{};
    for (final entry in decoded.entries) {
      final name = entry.key.toString().trim().toLowerCase();
      final value = entry.value?.toString().trim() ?? '';
      final canonical = switch (name) {
        'user-agent' => 'User-Agent',
        'origin' => 'Origin',
        'referer' || 'referrer' => 'Referer',
        _ => null,
      };
      if (canonical != null && value.isNotEmpty) {
        result[canonical] = value;
      }
    }
    return result;
  }
}
