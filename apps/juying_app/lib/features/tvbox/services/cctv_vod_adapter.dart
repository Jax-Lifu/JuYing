import 'package:dio/dio.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';

/// Bridges the TVBox candidate layer to JuYing's single CCTV official adapter.
///
/// Keeping catalogue and playback parsing in [CctvApiService] prevents the
/// TVBox search path and CCTV专区 from drifting onto different CNTV fields or
/// pagination rules.
class CctvVodAdapter {
  CctvVodAdapter({Dio? dio}) : _service = CctvApiService(dio: dio);

  final CctvApiService _service;

  static const String channelAnimation = 'CHAL1460955899450127';
  static const String channelDrama = 'CHAL1460955924871139';
  static const String channelDocumentary = 'CHAL1460955853485115';
  static const String channelSpecial = 'CHAL1460955909280133';
  // 电影由 fc 维度直接检索；CNTV 没有要求固定 channelid。
  static const String channelMovie = '';

  /// Fetches official albums and maps them onto the shared canonical identity.
  Future<List<MediaItem>> fetchAlbumList({
    required String channelId,
    required String firstCategory,
    String subCategory = '',
    String area = '',
    String letter = '',
    int page = 1,
    int pageSize = 24,
  }) async {
    final result = await _service.fetchYxgAlbums(
      firstCategory: firstCategory,
      genre: subCategory,
      area: area,
      letter: letter,
      channelId: channelId,
      page: page,
      pageSize: pageSize,
    );
    return result.albums.map((album) => album.toMediaItem()).toList();
  }

  /// Resolves an album into the same official candidate used by CCTV专区.
  Future<PlaybackCandidate?> fetchAlbumEpisodes(String albumId) {
    return _service.fetchAlbumEpisodes(albumId);
  }

  /// Exchanges the stable CCTV GUID for a current VDN HLS manifest.
  Future<String?> resolveCctvGuid(String guid) {
    return _service.resolveCctvGuid(guid);
  }
}
