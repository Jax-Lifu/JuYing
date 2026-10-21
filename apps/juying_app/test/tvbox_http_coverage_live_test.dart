import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

/// Audits only the user's already-installed HTTP sources. Results never contain
/// API/media URLs, response bodies, headers, cookies, or tokens; media signatures
/// remain transport evidence and must not be reported as native playback.
void main() {
  test('installed HTTP sources expose bounded, sanitized stage evidence',
      () async {
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = originalDebugPrint);
    final preferences = File(
      '${Platform.environment['APPDATA']}/com.juying/juying/shared_preferences.json',
    );
    final raw = (jsonDecode(await preferences.readAsString())
        as Map)['flutter.tvbox_subscriptions_v2'];
    final subscriptions = (raw is String ? jsonDecode(raw) : raw) as List;
    final sites = subscriptions
        .expand((subscription) => (subscription as Map)['sites'] as List)
        .map((site) =>
            TvBoxSite.fromJson(Map<String, dynamic>.from(site as Map)))
        .where((site) => const {0, 1, 4}.contains(site.type))
        .toList(growable: false);
    final results = <Map<String, Object?>>[];
    final output = File('.dart_tool/tvbox_http_coverage.json');
    for (var index = 0; index < sites.length; index += 2) {
      final batch = sites.skip(index).take(2);
      results.addAll(await Future.wait(batch.map(_audit)));
      await output.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
        'scope': 'installed HTTP sources only; no native decoding evidence',
        'nodes': results,
      }));
      for (final result in results.skip(index)) {
        // Only the fields assembled below are allowed into tool/test output.
        originalDebugPrint(jsonEncode(result));
      }
    }
    expect(results.length, sites.length);
  },
      skip: const bool.fromEnvironment('TVBOX_HTTP_AUDIT')
          ? false
          : 'Opt in with TVBOX_HTTP_AUDIT=true; uses installed subscriptions',
      timeout: const Timeout(Duration(minutes: 12)));
}

Future<Map<String, Object?>> _audit(TvBoxSite site) async {
  final result = <String, Object?>{
    'key': site.key,
    'name': site.name,
    'type': site.type,
    'stage': 'categories',
    'requests': <Object?>[],
  };
  final requests = result['requests']! as List<Object?>;
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
    headers: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
  ));
  dio.interceptors.add(InterceptorsWrapper(
    onResponse: (response, handler) {
      final value = response.data;
      final data = value is String && value.trimLeft().startsWith('{')
          ? _json(value)
          : value;
      if (site.type == 4 && result['stage'] != 'media' && data is! Map) {
        result['protocolError'] = 'invalid_json_object';
      }
      requests.add({
        'stage': result['stage'],
        'status': response.statusCode,
        'kind': data is Map
            ? 'json'
            : value is String && value.trimLeft().startsWith('<')
                ? 'markup'
                : 'other',
        if (data is Map) ...{
          'classes': data['class'] is List ? (data['class'] as List).length : 0,
          'items': data['list'] is List ? (data['list'] as List).length : 0,
          if (result['stage'] == 'resolve') ...{
            'parse': data['parse']?.toString(),
            'jx': data['jx']?.toString(),
            'urlPresent': data['url']?.toString().isNotEmpty == true,
            'playUrlMode': _parserMode(data['playUrl']),
          },
        },
      });
      handler.next(response);
    },
    onError: (error, handler) {
      requests.add({
        'stage': result['stage'],
        'status': error.response?.statusCode,
        'error': error.type.name,
        'cause': error.error?.runtimeType.toString(),
      });
      handler.next(error);
    },
  ));
  try {
    await (() async {
      final engine = TvBoxSpiderEngine(dio: dio);
      final categories = await engine.fetchSiteCategories(site);
      result['categories'] = categories.length;
      if (categories.isEmpty) return;
      result['stage'] = 'catalog';
      final media = await engine.fetchCategoryMedia(site, categories.first.id);
      result['catalogItems'] = media.length;
      if (media.isEmpty) return;
      result['stage'] = 'detail';
      final candidates = await engine.fetchMediaCandidates(site, media.first);
      result['candidates'] = candidates.length;
      final episodes = candidates.expand((candidate) => candidate.episodes);
      result['episodes'] = episodes.length;
      if (episodes.isEmpty) return;
      result['stage'] = 'resolve';
      PlaybackEpisode episode = episodes.first;
      if (episode.resolvePlayback != null) {
        episode = await episode.resolvePlayback!();
      }
      result['requiresWebView'] = episode.requiresWebView;
      result['urlKind'] = _urlKind(episode.url);
      if (episode.requiresWebView) return;
      result['stage'] = 'media';
      final response = await dio.get<ResponseBody>(episode.url,
          options: Options(
              responseType: ResponseType.stream, headers: episode.headers));
      result['mediaStatus'] = response.statusCode;
      final mime = response.headers.value('content-type') ?? '';
      result['mediaContentType'] = mime.split(';').first;
      final bytes = await response.data!.stream.first;
      final prefix =
          utf8.decode(bytes.take(4096).toList(), allowMalformed: true);
      result['mediaEvidence'] = prefix.trimLeft().startsWith('#EXTM3U')
          ? 'hls_manifest_only'
          : prefix.toLowerCase().contains('<html') || mime.contains('text/html')
              ? 'html_not_media'
              : bytes.length > 8 &&
                      ascii.decode(bytes.sublist(4, 8), allowInvalid: true) ==
                          'ftyp'
                  ? 'mp4_header_only'
                  : 'unverified_bytes';
      result['stage'] = 'transport_checked';
    })()
        .timeout(const Duration(seconds: 45));
  } catch (error) {
    result['error'] =
        error is DioException ? error.type.name : error.runtimeType.toString();
  } finally {
    dio.close(force: true);
  }
  return result;
}

Object? _json(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

String _parserMode(Object? value) {
  final text = value?.toString() ?? '';
  if (text.isEmpty) return 'none';
  if (text.startsWith('json:')) return 'json';
  if (text.startsWith('parse:')) return 'named';
  return 'prefix';
}

String _urlKind(String value) {
  final path = Uri.tryParse(value)?.path.toLowerCase() ?? '';
  for (final extension in const ['m3u8', 'mp4', 'mpd', 'flv', 'html', 'htm']) {
    if (path.endsWith('.$extension')) return extension;
  }
  return 'other';
}
