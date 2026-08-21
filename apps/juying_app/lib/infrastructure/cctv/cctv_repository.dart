import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/network/network_request_policy.dart';
import 'cctv_models.dart';
import '../../domain/models/playable_media.dart';
import 'cctv_exception.dart';
import 'cctv_parsers.dart';

class CctvRepository {
  CctvRepository({
    http.Client? client,
    this.networkPolicy = const NetworkRequestPolicy(),
    Future<void> Function(Duration delay)? wait,
  })  : _wait = wait ?? Future.delayed,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final NetworkRequestPolicy networkPolicy;
  final Future<void> Function(Duration delay) _wait;

  static const _headers = {'User-Agent': 'JuYing/0.1'};

  Future<CctvCatalogResult> fetchPrograms({
    CctvCatalogCategory category = CctvCatalogCategory.animation,
    String? subcategory,
    int page = 1,
    int pageSize = 24,
  }) async {
    final uri = Uri.https('api.cntv.cn', '/list/getVideoAlbumList', {
      'channelid': category.channelId,
      'area': '',
      'sc': subcategory ?? '',
      'fc': category.label,
      'year': '',
      'letter': '',
      'p': '$page',
      'n': '$pageSize',
      'serviceId': 'tvcctv',
      'topv': '1',
      't': 'json',
    });
    final response = await _get(uri);
    return CctvParsers.catalog(
      utf8.decode(response.bodyBytes),
      page: page,
      category: category,
    );
  }

  Future<List<CctvProgram>> searchPrograms(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    final uri = Uri.https('search.cctv.com', '/ifsearch.php', {
      'page': '1',
      'qtext': normalized,
      'sort': 'relevance',
      'pageSize': '30',
      'type': 'video',
      'vtime': '-1',
      'datepid': '1',
      'channel': '',
      'pageflag': '0',
      'qtext_str': normalized,
    });
    final response = await _get(uri);
    return CctvParsers.search(utf8.decode(response.bodyBytes));
  }

  Future<List<CctvEpisode>> fetchEpisodes(CctvProgram program) async {
    final response = await _get(program.officialPageUrl);
    final episodes = CctvParsers.episodes(
      utf8.decode(response.bodyBytes),
      programId: program.id,
    );
    if (episodes.isNotEmpty) return episodes;
    return [
      CctvEpisode(
        id: '${program.id}-default',
        title: program.episodeTitle ?? program.title,
        officialPageUrl: program.episodePageUrl,
        imageUrl: program.imageUrl,
        brief: program.brief,
      ),
    ];
  }

  Future<PlayableMedia> resolvePlayback(CctvEpisode episode) async {
    final pageResponse = await _get(episode.officialPageUrl);
    final guid = CctvParsers.pageGuid(utf8.decode(pageResponse.bodyBytes));
    final metadataUri = Uri.https(
      'vdn.apps.cntv.cn',
      '/api/getHttpVideoInfo.do',
      {'pid': guid},
    );
    final metadataResponse = await _get(metadataUri);
    final playback = CctvParsers.playback(
      utf8.decode(metadataResponse.bodyBytes),
      guid: guid,
      officialPageUri: episode.officialPageUrl,
    );
    return playback;
  }

  /// 清晰度发现是非关键增强能力，调用方必须先打开主流再异步请求它。
  Future<PlayableMedia> discoverQualities(PlayableMedia playback) async {
    try {
      final response = await _get(
        playback.streamUri,
        headers: playback.httpHeaders,
      );
      final qualities = CctvParsers.hlsQualities(
        utf8.decode(response.bodyBytes),
        baseUri: playback.streamUri,
      );
      return playback.copyWith(qualityOptions: qualities);
    } catch (_) {
      // 清晰度是附加能力；主播放列表读取失败不能阻止已授权的播放。
      return playback;
    }
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    for (var attempt = 1; attempt <= networkPolicy.maxAttempts; attempt++) {
      try {
        final response = await _client.get(uri,
            headers: {..._headers, ...headers}).timeout(networkPolicy.timeout);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        if (!networkPolicy.shouldRetryHttpStatus(response.statusCode) ||
            attempt == networkPolicy.maxAttempts) {
          throw CctvException('CCTV 服务暂时不可用（HTTP ${response.statusCode}）');
        }
      } on CctvException {
        rethrow;
      } catch (error) {
        if (attempt == networkPolicy.maxAttempts) {
          throw CctvException('连接 CCTV 服务失败，请检查网络后重试', cause: error);
        }
      }
      await _wait(networkPolicy.retryDelayFor(attempt));
    }
    throw StateError('请求重试流程意外结束');
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
