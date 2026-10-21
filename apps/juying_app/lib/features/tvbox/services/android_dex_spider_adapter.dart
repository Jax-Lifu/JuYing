import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/spider_playback_response.dart';

/// Flutter-side adapter for the Android CatVod JAR/Dex host.
///
/// The domain layer only exchanges standard CatVod JSON. Android-specific class loading and
/// reflection stay behind a method channel, so Windows and other platforms keep the same TVBox
/// models without pretending they can execute Android bytecode.
class AndroidDexSpiderAdapter {
  AndroidDexSpiderAdapter({
    MethodChannel? channel,
    bool? runtimeOverride,
    Dio? dio,
  })  : _channel = channel ?? _defaultChannel,
        _dio =
            dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
        _runtimeOverride = runtimeOverride;

  static const MethodChannel _defaultChannel =
      MethodChannel('com.flytech.juying/tvbox_dex');

  final MethodChannel _channel;
  final Dio _dio;
  final bool? _runtimeOverride;

  static bool get isPlatformAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool supports(TvBoxSite site) =>
      (_runtimeOverride ?? isPlatformAvailable) &&
      site.type == 3 &&
      site.api.trim().toLowerCase().startsWith('csp_') &&
      site.api.trim().toLowerCase() != 'csp_bili' &&
      site.jar.trim().isNotEmpty;

  Future<List<TvBoxCategory>> fetchCategories(TvBoxSite site) async {
    final root = await _invoke(site, 'home');
    final classes = root['class'];
    if (classes is! List) return site.categories;
    final categories = classes
        .whereType<Map>()
        .map((item) => TvBoxCategory.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
        .toList(growable: false);
    return categories.isEmpty ? site.categories : categories;
  }

  Future<List<MediaItem>> fetchCategory(
    TvBoxSite site,
    String categoryId, {
    int page = 1,
  }) async {
    return _parseMedia(
      await _invoke(
        site,
        'category',
        <String, dynamic>{'tid': categoryId, 'page': page},
      ),
    );
  }

  Future<List<MediaItem>> search(
    TvBoxSite site,
    String keyword, {
    int page = 1,
  }) async {
    return _parseMedia(
      await _invoke(
        site,
        'search',
        <String, dynamic>{'keyword': keyword, 'page': page},
      ),
    );
  }

  Future<List<PlaybackCandidate>> fetchCandidates(
    TvBoxSite site,
    MediaItem item,
  ) async {
    final detailRoot = await _invoke(
      site,
      'detail',
      <String, dynamic>{'id': item.id},
    );
    final list = detailRoot['list'];
    if (list is! List || list.isEmpty || list.first is! Map) {
      return const <PlaybackCandidate>[];
    }
    final detail = Map<String, dynamic>.from(list.first as Map);
    final flags = (detail['vod_play_from']?.toString() ?? '').split(r'$$$');
    final groups = (detail['vod_play_url']?.toString() ?? '').split(r'$$$');
    final candidates = <PlaybackCandidate>[];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final flag =
          groupIndex < flags.length && flags[groupIndex].trim().isNotEmpty
              ? flags[groupIndex].trim()
              : '线路 ${groupIndex + 1}';
      final episodes = <PlaybackEpisode>[];
      for (final rawEpisode in groups[groupIndex].split('#')) {
        final separator = rawEpisode.indexOf(r'$');
        final name =
            separator > 0 ? rawEpisode.substring(0, separator).trim() : '播放';
        final playId = separator > 0
            ? rawEpisode.substring(separator + 1).trim()
            : rawEpisode.trim();
        if (playId.isEmpty) continue;
        final episode = PlaybackEpisode(
          name: name.isEmpty ? '播放' : name,
          url: playId,
          sortIndex: episodes.length + 1,
        );
        episodes.add(
          PlaybackEpisode(
            name: episode.name,
            url: episode.url,
            sortIndex: episode.sortIndex,
            // Resolving only the selected episode keeps expiring tokens fresh.
            resolvePlayback: () => _resolvePlayback(site, flag, episode),
          ),
        );
      }
      if (episodes.isNotEmpty) {
        candidates.add(
          PlaybackCandidate(
            sourceKey: '${site.key}_dex_$groupIndex',
            sourceName: site.name,
            lineName: flag,
            episodes: episodes,
          ),
        );
      }
    }
    return candidates;
  }

  Future<PlaybackEpisode> _resolvePlayback(
    TvBoxSite site,
    String flag,
    PlaybackEpisode episode,
  ) async {
    final root = await _invoke(
      site,
      'player',
      <String, dynamic>{
        'flag': flag,
        'id': episode.url,
        'flags': site.flags,
      },
    );
    return resolveSpiderPlayback(
      site: site,
      episode: episode,
      response: {...root, 'flag': root['flag'] ?? flag},
      dio: _dio,
    );
  }

  Future<Map<String, dynamic>> _invoke(
    TvBoxSite site,
    String operation, [
    Map<String, dynamic> arguments = const <String, dynamic>{},
  ]) async {
    final result = await _channel.invokeMethod<String>(
      'invoke',
      <String, dynamic>{
        'siteKey': site.key,
        'api': site.api,
        'jar': site.jar,
        'extend': _encodeExtend(site.ext),
        'operation': operation,
        'arguments': arguments,
      },
    ).timeout(const Duration(seconds: 35));
    if (result == null || result.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = json.decode(result);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('CatVod Spider did not return a JSON object');
  }

  static List<MediaItem> _parseMedia(Map<String, dynamic> root) {
    final list = root['list'];
    if (list is! List) return const <MediaItem>[];
    return list
        .whereType<Map>()
        .map((raw) {
          final item = Map<String, dynamic>.from(raw);
          return MediaItem(
            id: item['vod_id']?.toString().trim() ?? '',
            title: item['vod_name']?.toString().trim() ?? '未知节目',
            posterUrl: _emptyToNull(item['vod_pic']),
            overview: _emptyToNull(
              item['vod_content'] ?? item['vod_blurb'] ?? item['vod_remarks'],
            ),
            year: _emptyToNull(item['vod_year']),
            rating: double.tryParse(item['vod_score']?.toString() ?? ''),
            genres: (item['vod_class']?.toString() ?? '')
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false),
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  static String _encodeExtend(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return json.encode(value);
  }

  static String? _emptyToNull(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
