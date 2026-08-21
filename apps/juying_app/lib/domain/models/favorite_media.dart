import 'unified_media.dart';

/// 收藏只引用来源内稳定条目，不保存任何临时播放 URI。
class FavoriteMedia {
  const FavoriteMedia({
    required this.profileId,
    required this.sourceId,
    required this.sourceItemId,
    required this.title,
    required this.category,
    required this.officialDetailUri,
    required this.defaultEpisodePageUri,
    required this.savedAt,
    this.posterUri,
  });

  final String profileId;
  final String sourceId;
  final String sourceItemId;
  final String title;
  final MediaCategory category;
  final Uri officialDetailUri;
  final Uri defaultEpisodePageUri;
  final Uri? posterUri;
  final DateTime savedAt;

  String get id => '$profileId:$sourceId:$sourceItemId';

  factory FavoriteMedia.fromItem({
    required String profileId,
    required MediaItem item,
    DateTime? savedAt,
  }) =>
      FavoriteMedia(
        profileId: profileId,
        sourceId: item.sourceId,
        sourceItemId: item.sourceItemId,
        title: item.title,
        category: item.category,
        officialDetailUri: item.officialDetailUri,
        defaultEpisodePageUri: item.defaultEpisodePageUri,
        posterUri: item.posterUri,
        savedAt: savedAt ?? DateTime.now(),
      );
}
