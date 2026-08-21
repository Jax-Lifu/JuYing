import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/favorite_media.dart';
import '../../domain/models/unified_media.dart';

class FavoriteStore {
  FavoriteStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const _keyPrefix = 'favorites.v1.';
  final SharedPreferencesAsync? _preferences;

  Future<List<FavoriteMedia>> load(String profileId) async {
    try {
      final raw = await (_preferences ?? SharedPreferencesAsync()).getString(
        '$_keyPrefix$profileId',
      );
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final items = decoded
          .whereType<Map>()
          .map((item) => _decode(Map<String, dynamic>.from(item), profileId))
          .whereType<FavoriteMedia>()
          .toList(growable: false)
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> toggle({
    required String profileId,
    required MediaItem item,
  }) async {
    final previous = await load(profileId);
    final id = '$profileId:${item.sourceId}:${item.sourceItemId}';
    final exists = previous.any((favorite) => favorite.id == id);
    final next = exists
        ? previous
            .where((favorite) => favorite.id != id)
            .toList(growable: false)
        : [
            FavoriteMedia.fromItem(profileId: profileId, item: item),
            ...previous
          ];
    try {
      await (_preferences ?? SharedPreferencesAsync()).setString(
        '$_keyPrefix$profileId',
        jsonEncode(next.map(_encode).toList(growable: false)),
      );
    } catch (_) {
      return exists;
    }
    return !exists;
  }

  Future<void> clearProfile(String profileId) async {
    await (_preferences ?? SharedPreferencesAsync()).remove(
      '$_keyPrefix$profileId',
    );
  }

  Map<String, Object?> _encode(FavoriteMedia value) => {
        'sourceId': value.sourceId,
        'sourceItemId': value.sourceItemId,
        'title': value.title,
        'category': value.category.name,
        'officialDetailUri': value.officialDetailUri.toString(),
        'defaultEpisodePageUri': value.defaultEpisodePageUri.toString(),
        'posterUri': value.posterUri?.toString(),
        'savedAt': value.savedAt.toUtc().toIso8601String(),
      };

  FavoriteMedia? _decode(Map<String, dynamic> value, String profileId) {
    final sourceId = value['sourceId'];
    final sourceItemId = value['sourceItemId'];
    final title = value['title'];
    final category = MediaCategory.values
        .where((item) => item.name == value['category'])
        .firstOrNull;
    final detail = Uri.tryParse(value['officialDetailUri']?.toString() ?? '');
    final episodePage =
        Uri.tryParse(value['defaultEpisodePageUri']?.toString() ?? '');
    final savedAt = DateTime.tryParse(value['savedAt']?.toString() ?? '');
    if (sourceId is! String ||
        sourceItemId is! String ||
        title is! String ||
        category == null ||
        detail == null ||
        episodePage == null ||
        savedAt == null) {
      return null;
    }
    return FavoriteMedia(
      profileId: profileId,
      sourceId: sourceId,
      sourceItemId: sourceItemId,
      title: title,
      category: category,
      officialDetailUri: detail,
      defaultEpisodePageUri: episodePage,
      posterUri: Uri.tryParse(value['posterUri']?.toString() ?? ''),
      savedAt: savedAt.toLocal(),
    );
  }
}
