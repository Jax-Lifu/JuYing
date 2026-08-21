import '../../domain/models/unified_media.dart';

abstract final class CatalogFavoriteFilter {
  static List<MediaItem> apply(
    Iterable<MediaItem> items,
    Set<String> favoriteIds, {
    required bool enabled,
  }) {
    if (!enabled) return items.toList(growable: false);
    return items
        .where((item) => favoriteIds.contains(item.id))
        .toList(growable: false);
  }
}
