import 'media_identity.dart';
import 'playable_media.dart';

/// 跨来源固定分类。来源原始分类只能在适配器内部映射到其中之一。
enum MediaCategory {
  drama('电视剧'),
  movie('电影'),
  animation('动画片'),
  documentary('纪录片'),
  variety('综艺'),
  live('直播'),
  kids('少儿'),
  other('其他');

  const MediaCategory(this.label);
  final String label;
}

/// 统一目录查询；来源筛选是同一查询流程的条件，而不是平行页面。
class MediaCatalogQuery {
  const MediaCatalogQuery({
    required this.category,
    this.page = 1,
    this.pageSize = 24,
    this.sourceSubcategoryId,
  });

  final MediaCategory category;
  final int page;
  final int pageSize;
  final String? sourceSubcategoryId;
}

class SourceCatalogTab {
  const SourceCatalogTab({
    required this.id,
    required this.label,
    required this.category,
  });

  final String id;
  final String label;
  final MediaCategory category;
}

/// 来源适配完成后的条目。跨来源边界只使用 [sourceId] + [sourceItemId]。
class MediaItem {
  const MediaItem({
    required this.sourceId,
    required this.sourceItemId,
    required this.title,
    required this.category,
    required this.officialDetailUri,
    required this.defaultEpisodePageUri,
    this.posterUri,
    this.brief,
    this.year,
    this.area,
    this.sourceCategoryLabel,
    this.sourceSubcategoryId,
    this.sourceSubcategoryLabel,
    this.episodeCount,
    this.workIdentity,
  });

  final String sourceId;
  final String sourceItemId;
  final String title;
  final MediaCategory category;
  final Uri officialDetailUri;
  final Uri defaultEpisodePageUri;
  final Uri? posterUri;
  final String? brief;
  final String? year;
  final String? area;
  final String? sourceCategoryLabel;
  final String? sourceSubcategoryId;
  final String? sourceSubcategoryLabel;
  final int? episodeCount;
  final MediaWorkIdentity? workIdentity;

  String get id => '$sourceId:$sourceItemId';
}

class MediaEpisode {
  const MediaEpisode({
    required this.sourceId,
    required this.sourceEpisodeId,
    required this.title,
    required this.officialPageUri,
    this.posterUri,
    this.brief,
    this.seasonNumber,
    this.episodeNumber,
    this.isSpecial = false,
  });

  final String sourceId;
  final String sourceEpisodeId;
  final String title;
  final Uri officialPageUri;
  final Uri? posterUri;
  final String? brief;
  final int? seasonNumber;
  final int? episodeNumber;
  final bool isSpecial;

  String get id => '$sourceId:$sourceEpisodeId';
}

class MediaCatalogPage {
  const MediaCatalogPage({
    required this.items,
    required this.page,
    required this.total,
  });

  final List<MediaItem> items;
  final int page;
  final int total;
}

class MediaSearchHit {
  const MediaSearchHit({
    required this.item,
    required this.query,
    required this.matchedField,
    this.relevance = 0,
    this.playable = false,
  });

  final MediaItem item;
  final String query;
  final String matchedField;
  final double relevance;
  final bool playable;
}

/// 播放器唯一接受的来源无关描述；长期存储不可保存 [nativeStreamUri]。
class PlaybackDescriptor {
  const PlaybackDescriptor({
    required this.sourceId,
    required this.sourceEpisodeId,
    required this.title,
    required this.officialPageUri,
    this.nativeStreamUri,
    this.expiresAt,
    this.posterUri,
    this.duration,
    this.qualityOptions = const [],
    this.httpHeaders = const {},
  });

  final String sourceId;
  final String sourceEpisodeId;
  final String title;
  final Uri officialPageUri;
  final Uri? nativeStreamUri;
  final DateTime? expiresAt;
  final Uri? posterUri;
  final Duration? duration;
  final List<PlaybackQuality> qualityOptions;
  final Map<String, String> httpHeaders;
}
