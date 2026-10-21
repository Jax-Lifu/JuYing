import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/cctv/models/cctv_album.dart';

/// Result object encapsulating total items and retrieved CCTV album models.
@immutable
class CctvQueryResult {
  const CctvQueryResult({
    required this.total,
    required this.albums,
  });

  final int total;
  final List<CctvAlbum> albums;
}

/// Official CCTV REST API and streaming resolution service.
///
/// **What**: Communicates with official CCTV/CNTV broadcast backend endpoints (`api.cntv.cn` and `vdn.apps.cntv.cn`)
/// to retrieve broadcast albums, episode sequences, and advertised HLS renditions.
///
/// **Why**: CCTV official archives operate under a dedicated schema completely decoupled
/// from third-party TVBox scrapers, providing broadcast-grade DRM/VDN tokenized playback.
class CctvApiService {
  CctvApiService({
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: <String, dynamic>{
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                  'Referer': 'https://tv.cctv.com/',
                  'Accept': 'application/json, text/javascript, */*',
                },
                validateStatus: (status) => status != null && status < 500,
              ),
            );

  final Dio _dio;
  final Map<String, int> _episodeCountCache = <String, int>{};

  Map<String, dynamic>? _parseResponseData(dynamic rawData) {
    if (rawData == null) return null;
    if (rawData is Map<String, dynamic>) return rawData;
    if (rawData is Map) return Map<String, dynamic>.from(rawData);
    if (rawData is String) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (e) {
        debugPrint('[CctvApiService] JSON parse error: $e');
      }
    }
    return null;
  }

  /// Fetches multi-dimensionally filtered album collections matching `tv.cctv.com/yxg`.
  Future<CctvQueryResult> fetchYxgAlbums({
    required String firstCategory, // e.g. 电影, 电视剧, 动画片, 纪录片, 特别节目
    String genre = '', // sc: e.g. 武侠, 亲子, 人文历史
    String area = '', // area: e.g. 内地（大陆）, 港澳台
    String year = '', // year: e.g. 2026, 2024
    String letter = '', // letter: e.g. A, B...
    String channelId = '', // channelid
    int page = 1,
    int pageSize = 24,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'fc': firstCategory,
        'p': page,
        'n': pageSize,
        'serviceId': 'tvcctv',
        'topv': 1,
        't': 'json',
      };

      if (genre.isNotEmpty && genre != '全部') {
        queryParams['sc'] = genre;
      }
      if (area.isNotEmpty && area != '全部') {
        queryParams['area'] = area;
      }
      if (year.isNotEmpty && year != '全部') {
        queryParams['year'] = year;
      }
      if (letter.isNotEmpty && letter != '全部') {
        queryParams['letter'] = letter;
      }
      if (channelId.isNotEmpty && channelId != '全部') {
        queryParams['channelid'] = channelId;
      }

      final response = await _dio.get<dynamic>(
        'https://api.cntv.cn/list/getVideoAlbumList',
        queryParameters: queryParams,
      );

      final data = _parseResponseData(response.data);
      if (data != null && data['data'] != null) {
        final total =
            int.tryParse(data['data']['total']?.toString() ?? '0') ?? 0;
        final list = data['data']['list'] as List? ?? <dynamic>[];
        final results = <CctvAlbum>[];

        for (final item in list) {
          if (item is! Map) continue;

          final id = item['id']?.toString() ??
              item['vsetid']?.toString() ??
              item['guid']?.toString() ??
              '';
          var title = item['title']?.toString().trim() ?? '央视节目';
          title = title.replaceAll(RegExp(r'^[《〈]|[》〉]$'), '').trim();

          final img = item['image2']?.toString() ??
              item['image']?.toString() ??
              item['image3']?.toString() ??
              '';
          final posterUrl = img.startsWith('//')
              ? 'https:$img'
              : (img.startsWith('http') ? img : '');

          final desc = item['brief']?.toString().trim() ?? '中央广播电视总台官方推荐';
          final itemYear = item['year']?.toString() ?? '2026';
          final count = int.tryParse(item['count']?.toString() ?? '1') ?? 1;
          final channel = item['channel']?.toString() ?? 'CCTV 官方';
          final sc = item['sc']?.toString() ?? '';
          final actors = item['actors']?.toString() ?? '';
          final itemArea = item['area']?.toString() ?? '';
          final vsetId = item['vsetid']?.toString();

          if (id.isNotEmpty) {
            results.add(
              CctvAlbum(
                id: id,
                title: title,
                posterUrl: posterUrl,
                overview: desc,
                category:
                    sc.isNotEmpty ? '$firstCategory · $sc' : firstCategory,
                year: itemYear,
                totalEpisodes: count,
                channelName: channel,
                actors: actors,
                area: itemArea,
                vsetId: vsetId,
              ),
            );
          }
        }
        final enrichedResults = await _enrichEpisodeCounts(results);
        return CctvQueryResult(total: total, albums: enrichedResults);
      }
    } catch (e) {
      debugPrint('[CctvApiService] fetchYxgAlbums error ($firstCategory): $e');
    }

    return const CctvQueryResult(total: 0, albums: <CctvAlbum>[]);
  }

  /// 修正央视列表接口中常见的 `count: 1` 占位值。
  ///
  /// 分集接口的 `data.total` 才是专辑维度的数量；每批最多并发六个轻量
  /// `n=1` 请求，并在服务生命周期内缓存，避免筛选和滚动时重复查询。
  Future<List<CctvAlbum>> _enrichEpisodeCounts(
    List<CctvAlbum> albums,
  ) async {
    final enriched = List<CctvAlbum>.of(albums);
    const batchSize = 6;
    for (var start = 0; start < albums.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, albums.length);
      await Future.wait(<Future<void>>[
        for (var index = start; index < end; index++)
          if (albums[index].totalEpisodes <= 1)
            () async {
              final count = await _fetchAlbumEpisodeTotal(albums[index].id);
              if (count > albums[index].totalEpisodes) {
                enriched[index] = albums[index].withTotalEpisodes(count);
              }
            }(),
      ]);
    }
    return enriched;
  }

  Future<int> _fetchAlbumEpisodeTotal(String albumId) async {
    final cached = _episodeCountCache[albumId];
    if (cached != null) return cached;
    try {
      final response = await _dio.get<dynamic>(
        'https://api.cntv.cn/NewVideo/getVideoListByAlbumIdNew',
        queryParameters: <String, dynamic>{
          'id': albumId,
          'serviceId': 'tvcctv',
          'pub': 1,
          'p': 1,
          'n': 1,
        },
      );
      final data = _parseResponseData(response.data);
      final count =
          int.tryParse(data?['data']?['total']?.toString() ?? '0') ?? 0;
      if (count > 0) _episodeCountCache[albumId] = count;
      return count;
    } catch (error) {
      debugPrint(
          '[CctvApiService] episode count lookup failed ($albumId): $error');
      return 0;
    }
  }

  /// Legacy helper method for backward compatibility.
  Future<List<CctvAlbum>> fetchAlbums({
    required String firstCategory,
    String? channelId,
    int page = 1,
    int pageSize = 24,
  }) async {
    final res = await fetchYxgAlbums(
      firstCategory: firstCategory,
      channelId: channelId ?? '',
      page: page,
      pageSize: pageSize,
    );
    return res.albums;
  }

  /// Fetches episodes and builds playable candidate routes for a CCTV album.
  Future<PlaybackCandidate?> fetchAlbumEpisodes(String albumId) async {
    final cleanId = albumId.replaceAll('cctv_album_', '').trim();
    var episodes = <_CctvEpisode>[];

    // 1. Primary: Fetch via Album ID New API
    try {
      const pageSize = 100;
      final seenUrls = <String>{};
      var idx = 1;
      // 长专辑和正片/花絮混排会超过一页；重复页必须终止，避免上游忽略分页时循环请求。
      for (var page = 1;; page++) {
        final response = await _dio.get<dynamic>(
          'https://api.cntv.cn/NewVideo/getVideoListByAlbumIdNew',
          queryParameters: <String, dynamic>{
            'id': cleanId,
            'serviceId': 'tvcctv',
            'pub': 1,
            // CNTV defaults to ten records. Drama albums interleave full episodes
            // with short clips, so the default page makes the detail page look as
            // if an entire series consists only of previews.
            'p': page,
            'n': pageSize,
          },
        );

        final data = _parseResponseData(response.data)?['data'];
        if (data is! Map) break;
        final list = data['list'] as List? ?? <dynamic>[];
        if (list.isEmpty) break;
        final previousCount = episodes.length;

        for (final raw in list) {
          if (raw is! Map) continue;
          final title = raw['title']?.toString() ?? '第$idx集';
          final guid = raw['guid']?.toString() ?? '';
          final url = raw['url']?.toString() ?? '';
          final length = raw['length']?.toString();
          final part = int.tryParse(raw['part']?.toString() ?? '') ?? idx;

          if (guid.isNotEmpty || url.isNotEmpty) {
            final episodeUrl = guid.isNotEmpty ? 'cctv_guid://$guid' : url;
            if (!seenUrls.add(episodeUrl)) continue;
            episodes.add(
              _CctvEpisode(
                duration: _parseDuration(length),
                declaredPart: int.tryParse(raw['part']?.toString() ?? ''),
                episode: PlaybackEpisode(
                  name: title,
                  url: episodeUrl,
                  sortIndex: part,
                  duration: _parseDuration(length),
                  badge:
                      length != null && length.isNotEmpty ? length : '央视 HLS',
                  headers: const <String, String>{
                    'User-Agent':
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                    'Referer': 'https://tv.cctv.com/',
                  },
                  officialPageUrl: url.isEmpty ? null : url,
                  thumbnailUrl: raw['image']?.toString(),
                ),
              ),
            );
            idx++;
          }
        }
        final total = int.tryParse(data['total']?.toString() ?? '');
        if (episodes.length == previousCount ||
            (total != null && total > 0
                ? episodes.length >= total
                : list.length < pageSize)) {
          break;
        }
      }
    } catch (e) {
      debugPrint(
          '[CctvApiService] Error in getVideoListByAlbumIdNew for $cleanId: $e');
    }

    episodes = _selectMainEpisodes(episodes);

    // 2. Secondary: If empty, fetch via VSetId API
    if (episodes.isEmpty) {
      try {
        final response = await _dio.get<dynamic>(
          'https://api.cntv.cn/NewVideo/getVideoListByVsetId',
          queryParameters: <String, dynamic>{
            'vsetId': cleanId,
            'serviceId': 'tvcctv',
          },
        );

        final data = _parseResponseData(response.data);
        if (data != null && data['data'] != null) {
          final list = data['data']['list'] as List? ?? <dynamic>[];
          var idx = 1;

          for (final raw in list) {
            if (raw is! Map) continue;
            final title = raw['title']?.toString() ?? '第$idx集';
            final guid = raw['guid']?.toString() ?? '';
            final url = raw['url']?.toString() ?? '';

            if (guid.isNotEmpty || url.isNotEmpty) {
              episodes.add(
                _CctvEpisode(
                  duration: Duration.zero,
                  declaredPart: int.tryParse(raw['part']?.toString() ?? ''),
                  episode: PlaybackEpisode(
                    name: title,
                    url: guid.isNotEmpty ? 'cctv_guid://$guid' : url,
                    sortIndex: idx,
                    badge: '官方原画',
                    headers: const <String, String>{
                      'User-Agent':
                          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                      'Referer': 'https://tv.cctv.com/',
                    },
                    officialPageUrl: url.isEmpty ? null : url,
                    thumbnailUrl: raw['image']?.toString(),
                  ),
                ),
              );
              idx++;
            }
          }
        }
      } catch (e) {
        debugPrint(
            '[CctvApiService] Error in getVideoListByVsetId for $cleanId: $e');
      }
    }

    if (episodes.isNotEmpty) {
      return PlaybackCandidate(
        sourceKey: 'cctv_official',
        sourceName: '🏛️ 央视网官方片库',
        lineName: '官方原生 HLS',
        resolution: '标清 / 流畅',
        episodes: episodes.map((item) => item.episode).toList(growable: false),
      );
    }

    // Album identifiers and media GUIDs are different namespaces. Treating an
    // unresolved album ID as a GUID used to play an unrelated fallback sample.
    return null;
  }

  /// Keeps the programme's canonical full episodes and removes CNTV's interleaved clips.
  ///
  /// CNTV uses the same album feed for full episodes, previews and highlight cuts.
  /// A declared `part` or a `第 N 集` title is authoritative; for single-programme
  /// albums without episode numbers the longest programme is the safest canonical item.
  List<_CctvEpisode> _selectMainEpisodes(List<_CctvEpisode> items) {
    if (items.isEmpty) return items;

    final numbered = items.where((item) {
      return item.declaredPart != null ||
          RegExp(r'第\s*\d+\s*集').hasMatch(item.episode.name);
    }).toList();

    var selected = numbered;
    if (selected.isEmpty) {
      final programmes = items
          .where((item) => item.duration >= const Duration(minutes: 8))
          .toList();
      selected =
          programmes.isNotEmpty ? programmes : <_CctvEpisode>[items.first];
    }

    selected.sort((a, b) {
      final aPart = a.declaredPart ?? a.episode.sortIndex;
      final bPart = b.declaredPart ?? b.episode.sortIndex;
      return aPart.compareTo(bPart);
    });

    final deduplicated = <int, _CctvEpisode>{};
    for (final item in selected) {
      final part = item.declaredPart ?? _episodeNumber(item.episode.name);
      deduplicated.putIfAbsent(part ?? item.episode.sortIndex, () => item);
    }

    return deduplicated.values.toList();
  }

  int? _episodeNumber(String title) {
    final match = RegExp(r'第\s*(\d+)\s*集').firstMatch(title);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Duration _parseDuration(String? value) {
    if (value == null || value.isEmpty) return Duration.zero;
    final parts = value.split(':').map(int.tryParse).toList();
    if (parts.any((part) => part == null)) return Duration.zero;
    if (parts.length == 3) {
      return Duration(
        hours: parts[0]!,
        minutes: parts[1]!,
        seconds: parts[2]!,
      );
    }
    if (parts.length == 2) {
      return Duration(minutes: parts[0]!, seconds: parts[1]!);
    }
    return Duration.zero;
  }

  /// Resolves a CCTV GUID into native-playable clear HLS variants.
  ///
  /// CCTV's public master playlist may advertise only the lowest rendition even
  /// when the adjacent 850 Kbps rendition exists. The official APK maps 450 to
  /// `LD` (流畅) and 850 to `STD` (标清), so both clear renditions are probed
  /// explicitly. H5E renditions use a separate resolver and preprocessing path;
  /// handing their unchanged payload to FFmpeg/libmpv produces corrupt frames.
  Future<CctvVodPlayback?> resolveCctvGuidPlayback(String guid) async {
    try {
      final cleanGuid = guid.replaceAll('cctv_guid://', '').trim();
      final response = await _dio.get<dynamic>(
        'https://vdn.apps.cntv.cn/api/getHttpVideoInfo.do',
        queryParameters: <String, dynamic>{
          'pid': cleanGuid,
          'tz': -8,
          'from': '000news',
        },
      );

      final data = _parseResponseData(response.data);

      if (data == null) return null;

      final hlsUrl = data['hls_url']?.toString();
      if (hlsUrl == null || hlsUrl.isEmpty) return null;
      final variants = await _resolveClearHlsVariants(hlsUrl);
      if (variants.isEmpty) return null;

      final video = data['video'] as Map?;
      final totalSeconds =
          double.tryParse(video?['totalLength']?.toString() ?? '') ?? 0;
      return CctvVodPlayback(
        variants: variants,
        duration: Duration(milliseconds: (totalSeconds * 1000).round()),
      );
    } catch (e) {
      debugPrint('[CctvApiService] resolveCctvGuidPlayback error: $e');
    }

    return null;
  }

  /// Resolves advertised H5E renditions without reducing the available quality.
  ///
  /// Only explicit HD resolutions qualify. If the highest rendition declares an
  /// unsupported codec, callers retain the WebView path instead of silently
  /// choosing a lower rendition. These URLs require H5E preprocessing before
  /// they reach the native player; resolving a manifest does not prove decoding.
  Future<CctvVodPlayback?> resolveCctvGuidHdPlayback(String guid) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://vdn.apps.cntv.cn/api/getHttpVideoInfo.do',
        queryParameters: <String, dynamic>{
          'pid': guid.replaceAll('cctv_guid://', '').trim(),
          'tz': -8,
          'from': '000news',
        },
      );
      if (response.statusCode != 200) return null;
      final data = _parseResponseData(response.data);
      final manifest = data?['manifest'];
      final masterUrl = manifest is Map ? manifest['hls_h5e_url'] : null;
      final masterUri = masterUrl is String ? Uri.tryParse(masterUrl) : null;
      if (masterUri == null ||
          !const <String>['http', 'https'].contains(masterUri.scheme) ||
          masterUri.host.isEmpty) {
        return null;
      }

      final master = await _dio.get<String>(
        masterUri.toString(),
        options: Options(responseType: ResponseType.plain),
      );
      if (master.statusCode != 200 || master.data == null) return null;
      final lines = const LineSplitter()
          .convert(master.data!.replaceFirst(RegExp(r'^\uFEFF'), ''))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty || lines.first != '#EXTM3U') return null;

      final variants = <({
        int height,
        int bandwidth,
        bool supported,
        CctvStreamVariant stream
      })>[];
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
        final attributes = line.substring('#EXT-X-STREAM-INF:'.length);
        final resolution = RegExp(
          r'(?:^|,)\s*RESOLUTION=(\d+)x(\d+)(?=\s*(?:,|$))',
        ).firstMatch(attributes);
        final width = int.tryParse(resolution?.group(1) ?? '') ?? 0;
        final height = int.tryParse(resolution?.group(2) ?? '') ?? 0;
        if (width <= 0 || height < 720) continue;
        final bandwidth = int.tryParse(
              RegExp(r'(?:^|,)\s*BANDWIDTH=(\d+)(?=\s*(?:,|$))')
                      .firstMatch(attributes)
                      ?.group(1) ??
                  '',
            ) ??
            0;
        if (bandwidth <= 0) return null;

        String? path;
        for (var next = index + 1; next < lines.length; next++) {
          if (lines[next].startsWith('#EXT-X-STREAM-INF:')) break;
          if (lines[next].startsWith('#')) continue;
          path = lines[next];
          break;
        }
        if (path == null) return null;
        final uri = master.realUri.resolve(path);
        if (!const <String>['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          return null;
        }

        final hasCodecs = RegExp(r'(?:^|,)\s*CODECS=').hasMatch(attributes);
        final codecs = RegExp(r'(?:^|,)\s*CODECS="([^"]+)"(?=\s*(?:,|$))')
            .firstMatch(attributes)
            ?.group(1)
            ?.split(',')
            .map((codec) => codec.trim().toLowerCase().split('.').first)
            .toSet();
        final supported = !hasCodecs ||
            (codecs != null &&
                codecs.any(const <String>{'avc1', 'avc3'}.contains) &&
                codecs.every(const <String>{
                  'avc1',
                  'avc3',
                  'mp4a',
                  'ac-3',
                  'ec-3',
                  'opus',
                  'flac',
                }.contains));
        variants.add((
          height: height,
          bandwidth: bandwidth,
          supported: supported,
          stream: CctvStreamVariant(
            id: 'h5e-${height}p-$bandwidth',
            label: height >= 2160 ? '超高清' : (height >= 1080 ? '全高清' : '高清'),
            resolution: '${height}p',
            bitrateKbps: (bandwidth / 1000).round(),
            url: uri.toString(),
            isH5e: true,
          ),
        ));
      }
      variants.sort((a, b) {
        final byHeight = b.height.compareTo(a.height);
        return byHeight != 0 ? byHeight : b.bandwidth.compareTo(a.bandwidth);
      });
      if (variants.isEmpty || !variants.first.supported) return null;

      final video = data?['video'];
      final seconds = double.tryParse(
            video is Map ? video['totalLength']?.toString() ?? '' : '',
          ) ??
          0;
      return CctvVodPlayback(
        variants: variants
            .where((variant) => variant.supported)
            .map((variant) => variant.stream)
            .toList(),
        duration: Duration(
          milliseconds:
              seconds.isFinite && seconds > 0 ? (seconds * 1000).round() : 0,
        ),
      );
    } catch (e) {
      debugPrint('[CctvApiService] resolveCctvGuidHdPlayback error: $e');
    }
    return null;
  }

  /// Resolves `cctv_guid://` into the best clear rendition for legacy callers.
  Future<String?> resolveCctvGuid(String guid) async {
    final playback = await resolveCctvGuidPlayback(guid);
    return playback?.variants.first.url;
  }

  Future<List<CctvStreamVariant>> _resolveClearHlsVariants(
    String masterUrl,
  ) async {
    final resolved = await _resolveHighestHlsVariant(<String>[masterUrl]);
    if (resolved == null) return const <CctvStreamVariant>[];

    final variants = <CctvStreamVariant>[
      CctvStreamVariant(
        id: 'ld',
        label: '流畅',
        resolution: '270p',
        bitrateKbps: 450,
        url: resolved,
      ),
    ];
    final standardUrl = _replaceCctvBitrate(resolved, 450, 850);
    if (standardUrl != null && await _isHlsMediaPlaylist(standardUrl)) {
      variants.insert(
        0,
        CctvStreamVariant(
          id: 'std',
          label: '标清',
          resolution: '360p',
          bitrateKbps: 850,
          url: standardUrl,
        ),
      );
    }
    return variants;
  }

  String? _replaceCctvBitrate(String url, int source, int target) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final marker = '/asp/hls/$source/';
    if (!uri.path.contains(marker)) return null;
    final path = uri.path
        .replaceFirst(marker, '/asp/hls/$target/')
        .replaceFirst(RegExp('/$source\\.m3u8\$'), '/$target.m3u8');
    return uri.replace(path: path).toString();
  }

  Future<bool> _isHlsMediaPlaylist(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      return response.statusCode == 200 &&
          (response.data?.contains('#EXTINF:') ?? false) &&
          (response.data?.contains('#EXT-X-ENDLIST') ?? false);
    } catch (_) {
      return false;
    }
  }

  /// Resolves CCTV master manifests before handing playback to libmpv.
  ///
  /// CNTV encodes variant entries as root-relative paths (`/asp/hls/...`).
  /// libmpv intentionally treats those as unsafe local paths when loaded from
  /// a network playlist. Resolving the highest-bandwidth child here preserves
  /// the CDN authority and leaves the final media playlist standards-compliant.
  Future<String?> _resolveHighestHlsVariant(List<String> candidates) async {
    for (final candidate in candidates) {
      try {
        final response = await _dio.get<String>(
          candidate,
          options: Options(responseType: ResponseType.plain),
        );
        if (response.statusCode != 200 || response.data == null) continue;

        final lines = const LineSplitter()
            .convert(response.data!)
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        final variants = <({int bandwidth, String path})>[];

        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
          final bandwidth = int.tryParse(
                RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '',
              ) ??
              0;
          for (var pathIndex = index + 1;
              pathIndex < lines.length;
              pathIndex++) {
            final path = lines[pathIndex];
            if (path.startsWith('#')) continue;
            variants.add((bandwidth: bandwidth, path: path));
            break;
          }
        }

        if (variants.isEmpty) {
          // Already a media playlist; relative TS segments remain anchored to
          // this network URL and are safe for libmpv to resolve normally.
          if (lines.any((line) => line.startsWith('#EXTINF:'))) {
            return candidate;
          }
          continue;
        }

        variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
        return Uri.parse(candidate).resolve(variants.first.path).toString();
      } catch (e) {
        debugPrint('[CctvApiService] HLS manifest fallback failed: $e');
      }
    }
    return null;
  }

  /// Static samples are retained for previews and tests, but never substituted
  /// into a failed network query because that would silently play the wrong show.
  List<CctvAlbum> buildPreviewAlbums() {
    return const <CctvAlbum>[
      CctvAlbum(
        id: 'VIDA8lgsyrdD1LuVvEdkr2Fd260625',
        title: '小小围棋少年',
        posterUrl:
            'https://p1.img.cctvpic.com/photoAlbum/vms/image/3bcf8b2f57b3aea5bd883355b9e62052.jpg',
        overview: '明代围棋天才少年江流儿，结识四川青城山野狐派小狐狸，历经磨难踏上寻找围棋真谛之路。',
        category: '少儿动画',
        year: '2026',
        rating: 9.3,
        totalEpisodes: 20,
        channelName: 'CCTV-14 少儿',
        firstGuid: 'a0f3f5b065eb4e81bb97c463512f58aa',
      ),
      CctvAlbum(
        id: 'VIDAanUn3LgGUcZPT5iaKy8g260810',
        title: '能有多大事',
        posterUrl:
            'https://p1.img.cctvpic.com/photoAlbum/vms/image/6420bbce036567c59fe5f617317b3185.jpg',
        overview: '五星大厨许多金退休后的生活故事，李幼斌、史兰牙主演。',
        category: '经典剧场',
        year: '2026',
        rating: 9.2,
        totalEpisodes: 30,
        channelName: 'CCTV-8 电视剧',
        actors: '李幼斌,史兰牙,袁志博',
      ),
    ];
  }
}

/// CCTV VOD metadata resolved from a single VDN response.
/// H5E variants need preprocessing before native playback.
class CctvVodPlayback {
  const CctvVodPlayback({required this.variants, required this.duration});

  final List<CctvStreamVariant> variants;
  final Duration duration;
}

/// An advertised rendition and whether native playback needs H5E preprocessing.
class CctvStreamVariant {
  const CctvStreamVariant({
    required this.id,
    required this.label,
    required this.resolution,
    required this.bitrateKbps,
    required this.url,
    this.isH5e = false,
  });

  final String id;
  final String label;
  final String resolution;
  final int bitrateKbps;
  final String url;
  final bool isH5e;

  String get displayLabel => '$label · $resolution';
}

/// Internal transport model used to separate CNTV catalogue noise from full episodes.
class _CctvEpisode {
  const _CctvEpisode({
    required this.episode,
    required this.duration,
    required this.declaredPart,
  });

  final PlaybackEpisode episode;
  final Duration duration;
  final int? declaredPart;
}
