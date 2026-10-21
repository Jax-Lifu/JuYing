import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/cctv_vod_adapter.dart';

/// Clean-room Dart replacements for known Python Spider identities.
///
/// Arbitrary Python cannot be executed safely and consistently on every Flutter target. Stable
/// upstream identities are therefore mapped to native Dart protocol clients, preserving CatVod
/// behavior without bundling CPython or allowing scripts filesystem/process access.
class PythonCompatSpiderAdapter {
  PythonCompatSpiderAdapter({CctvVodAdapter? cctvAdapter})
      : _cctvAdapter = cctvAdapter ?? CctvVodAdapter();

  final CctvVodAdapter _cctvAdapter;

  static bool supports(TvBoxSite site) {
    final api = site.api.trim().toLowerCase();
    final ext = site.ext?.toString().toLowerCase() ?? '';
    return api == 'py_cctv_full' ||
        (api.startsWith('py_cctv') && ext.contains('央视'));
  }

  Future<List<TvBoxCategory>> fetchCategories(TvBoxSite site) async {
    return const <TvBoxCategory>[
      TvBoxCategory(id: 'cctv_movie_电影', name: '电影'),
      TvBoxCategory(id: 'CHAL1460955899450127_动画片', name: '少儿动画'),
      TvBoxCategory(id: 'CHAL1460955924871139_电视剧', name: '电视剧'),
      TvBoxCategory(id: 'CHAL1460955853485115_纪录片', name: '纪录片'),
      TvBoxCategory(id: 'CHAL1460955909280133_特别节目', name: '特别节目'),
    ];
  }

  Future<List<MediaItem>> fetchCategory(
    TvBoxSite site,
    String categoryId, {
    int page = 1,
    int pageSize = 20,
  }) {
    var channelId = CctvVodAdapter.channelAnimation;
    var category = '动画片';
    if (categoryId.contains('电影')) {
      channelId = CctvVodAdapter.channelMovie;
      category = '电影';
    } else if (categoryId.contains('电视剧')) {
      channelId = CctvVodAdapter.channelDrama;
      category = '电视剧';
    } else if (categoryId.contains('纪录片')) {
      channelId = CctvVodAdapter.channelDocumentary;
      category = '纪录片';
    } else if (categoryId.contains('特别节目')) {
      channelId = CctvVodAdapter.channelSpecial;
      category = '特别节目';
    }
    return _cctvAdapter.fetchAlbumList(
      channelId: channelId,
      firstCategory: category,
      page: page,
      pageSize: pageSize,
    );
  }

  Future<List<PlaybackCandidate>> fetchCandidates(MediaItem item) async {
    final albumId = item.id.replaceFirst('cctv_album_', '');
    final candidate = await _cctvAdapter.fetchAlbumEpisodes(albumId);
    return candidate == null
        ? const <PlaybackCandidate>[]
        : <PlaybackCandidate>[candidate];
  }
}
