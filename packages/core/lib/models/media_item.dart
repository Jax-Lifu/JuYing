/// Represents the canonical media work entity (Identity Layer) decoupled from any specific crawler site.
///
/// **Why**: Traditional TVBox implementations bind movie entities directly to source site IDs,
/// causing massive duplicates in aggregated search results. Decoupling canonical identity
/// ([MediaItem]) from playable sources ([PlaybackCandidate]) enables unified multi-source aggregation,
/// deduplication, and seamless in-place line switching.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    this.originalTitle,
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.rating,
    this.overview,
    this.genres = const <String>[],
    this.cast = const <String>[],
    this.totalEpisodes,
    this.updatedAt,
  });

  /// Global canonical ID (e.g. `tmdb_tv_12345` or `douban_movie_67890`).
  final String id;

  /// Localized title (e.g. `庆余年 第二季`).
  final String title;

  /// Original language title if available.
  final String? originalTitle;

  /// High-resolution vertical poster image URL (2:3 aspect ratio).
  final String? posterUrl;

  /// High-resolution horizontal backdrop banner image URL (16:9 aspect ratio).
  final String? backdropUrl;

  /// Release year (e.g. "2024").
  final String? year;

  /// Public rating score (e.g. 8.8 on a 10.0 scale).
  final double? rating;

  /// Full synopsis / plot overview.
  final String? overview;

  /// List of category tags (e.g. `["古装", "权谋", "剧情"]`).
  final List<String> genres;

  /// Primary cast & crew names.
  final List<String> cast;

  /// Known total episode count.
  final int? totalEpisodes;

  /// Monotonic timestamp in milliseconds for LWW sync conflict resolution.
  final int? updatedAt;

  /// Creates a copy of this [MediaItem] with updated properties.
  MediaItem copyWith({
    String? id,
    String? title,
    String? originalTitle,
    String? posterUrl,
    String? backdropUrl,
    String? year,
    double? rating,
    String? overview,
    List<String>? genres,
    List<String>? cast,
    int? totalEpisodes,
    int? updatedAt,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      overview: overview ?? this.overview,
      genres: genres ?? this.genres,
      cast: cast ?? this.cast,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
