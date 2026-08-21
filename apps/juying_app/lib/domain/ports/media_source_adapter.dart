import '../models/media_source.dart';
import '../models/unified_media.dart';

/// 每个来源的唯一接入边界。实现可认识来源字段，调用方只能使用统一模型。
abstract interface class MediaSourceAdapter {
  MediaSource get source;

  Future<MediaCatalogPage> browse(MediaCatalogQuery query);
  Future<List<MediaSearchHit>> search(String query);
  Future<List<MediaEpisode>> episodes(MediaItem item);
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode);

  /// 原生播放不适用时，返回可在官方页面中使用的授权播放描述。
  Future<PlaybackDescriptor> resolveOfficialFallback(MediaEpisode episode);
}
