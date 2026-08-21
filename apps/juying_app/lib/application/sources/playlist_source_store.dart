import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/playlist_source.dart';

abstract interface class PlaylistSourceStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesPlaylistSourceStorage implements PlaylistSourceStorage {
  SharedPreferencesPlaylistSourceStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}

/// 仅保存非敏感来源元数据和用户的权利确认时间，不保存播放 URL 列表。
class PlaylistSourceStore {
  PlaylistSourceStore({PlaylistSourceStorage? storage}) : _storage = storage;

  static const _key = 'sources.playlists.v1';
  final PlaylistSourceStorage? _storage;

  Future<List<PlaylistSourceDefinition>> load() async {
    try {
      final raw = await (_storage ?? SharedPreferencesPlaylistSourceStorage())
          .read(_key);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((value) => _decode(Map<String, Object?>.from(value)))
          .whereType<PlaylistSourceDefinition>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsert(PlaylistSourceDefinition source) async {
    final current = await load();
    final next = [source, ...current.where((item) => item.id != source.id)];
    await (_storage ?? SharedPreferencesPlaylistSourceStorage()).write(
      _key,
      jsonEncode(next.map(_encode).toList(growable: false)),
    );
  }

  Future<void> remove(String sourceId) async {
    final remaining = (await load())
        .where((source) => source.id != sourceId)
        .toList(growable: false);
    await (_storage ?? SharedPreferencesPlaylistSourceStorage()).write(
      _key,
      jsonEncode(remaining.map(_encode).toList(growable: false)),
    );
  }

  Map<String, Object?> _encode(PlaylistSourceDefinition source) => {
        'id': source.id,
        'name': source.name,
        'playlistUri': source.playlistUri.toString(),
        'rightsConfirmedAt': source.rightsConfirmedAt.toUtc().toIso8601String(),
        'enabled': source.enabled,
      };

  PlaylistSourceDefinition? _decode(Map<String, Object?> value) {
    final id = value['id'];
    final name = value['name'];
    final uri = Uri.tryParse(value['playlistUri']?.toString() ?? '');
    final confirmed =
        DateTime.tryParse(value['rightsConfirmedAt']?.toString() ?? '');
    final enabled = value['enabled'];
    if (id is! String ||
        !RegExp(r'^playlist-[a-z0-9-]+$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        confirmed == null ||
        enabled is! bool) {
      return null;
    }
    return PlaylistSourceDefinition(
      id: id,
      name: name,
      playlistUri: uri,
      rightsConfirmedAt: confirmed,
      enabled: enabled,
    );
  }
}
