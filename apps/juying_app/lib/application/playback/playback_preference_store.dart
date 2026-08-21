import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 与具体存储实现解耦，便于验证播放偏好不会跨档案或跨来源混用。
abstract interface class PlaybackPreferenceStorage {
  Future<String?> readString(String key);
  Future<double?> readDouble(String key);
  Future<void> writeString(String key, String value);
  Future<List<String>?> readStringList(String key);
  Future<void> writeStringList(String key, List<String> value);
  Future<void> remove(String key);
}

class SharedPreferencesPlaybackPreferenceStorage
    implements PlaybackPreferenceStorage {
  SharedPreferencesPlaybackPreferenceStorage({SharedPreferencesAsync? prefs})
      : _customPrefs = prefs;

  final SharedPreferencesAsync? _customPrefs;
  SharedPreferencesAsync get _prefs => _customPrefs ?? SharedPreferencesAsync();

  @override
  Future<String?> readString(String key) => _prefs.getString(key);

  @override
  Future<double?> readDouble(String key) => _prefs.getDouble(key);

  @override
  Future<void> writeString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<List<String>?> readStringList(String key) => _prefs.getStringList(key);

  @override
  Future<void> writeStringList(String key, List<String> value) =>
      _prefs.setStringList(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// 不保存流 URL、Cookie 或来源页面的播放器偏好。
class PlaybackPreferences {
  const PlaybackPreferences({
    this.qualityId,
    this.speed = 1,
    this.volume = 1,
  });

  final String? qualityId;
  final double speed;
  final double volume;

  PlaybackPreferences copyWith({
    String? qualityId,
    double? speed,
    double? volume,
  }) =>
      PlaybackPreferences(
        qualityId: qualityId ?? this.qualityId,
        speed: speed ?? this.speed,
        volume: volume ?? this.volume,
      );

  Map<String, Object?> toJson() => {
        'qualityId': qualityId,
        'speed': speed,
        'volume': volume,
      };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> value) {
    final quality = value['qualityId'];
    final speed = (value['speed'] as num?)?.toDouble() ?? 1;
    final volume = (value['volume'] as num?)?.toDouble() ?? 1;
    return PlaybackPreferences(
      qualityId:
          quality is String && quality.trim().isNotEmpty ? quality : null,
      speed: _clamp(speed, min: 0.5, max: 3),
      volume: _clamp(volume, min: 0, max: 1),
    );
  }

  static double _clamp(double value,
      {required double min, required double max}) {
    if (!value.isFinite) return min;
    return value.clamp(min, max).toDouble();
  }
}

/// 偏好键通过 profileId + sourceId 隔离，质量 ID 只在该来源语义内解释。
class PlaybackPreferenceStore {
  PlaybackPreferenceStore({PlaybackPreferenceStorage? storage})
      : _storage = storage ?? SharedPreferencesPlaybackPreferenceStorage();

  static const _keyPrefix = 'playback.preferences.v1.';
  static const _sourcesKeyPrefix = 'playback.preferences.sources.v1.';
  final PlaybackPreferenceStorage _storage;

  Future<PlaybackPreferences> load({
    required String profileId,
    required String sourceId,
  }) async {
    try {
      final raw = await _storage.readString(_key(profileId, sourceId));
      if (raw != null) {
        final value = jsonDecode(raw);
        if (value is Map) {
          return PlaybackPreferences.fromJson(Map<String, dynamic>.from(value));
        }
      }
      final migrated = await _readLegacy(sourceId);
      if (migrated != null) {
        await save(profileId: profileId, sourceId: sourceId, value: migrated);
        return migrated;
      }
    } catch (_) {
      // 偏好存储故障不能阻断一次已经授权的播放会话。
    }
    return const PlaybackPreferences();
  }

  Future<void> save({
    required String profileId,
    required String sourceId,
    required PlaybackPreferences value,
  }) async {
    try {
      await _storage.writeString(
        _key(profileId, sourceId),
        jsonEncode(value.toJson()),
      );
      final sources =
          await _storage.readStringList(_sourcesKey(profileId)) ?? const [];
      if (!sources.contains(sourceId)) {
        await _storage.writeStringList(
          _sourcesKey(profileId),
          [...sources, sourceId],
        );
      }
    } catch (_) {
      // 仅影响下次启动时的偏好恢复，不影响当前会话。
    }
  }

  Future<void> update({
    required String profileId,
    required String sourceId,
    String? qualityId,
    double? speed,
    double? volume,
  }) async {
    final current = await load(profileId: profileId, sourceId: sourceId);
    await save(
      profileId: profileId,
      sourceId: sourceId,
      value: current.copyWith(
        qualityId: qualityId,
        speed: speed,
        volume: volume,
      ),
    );
  }

  Future<String?> getLastLiveChannel({
    required String profileId,
    required String sourceId,
  }) async {
    try {
      return await _storage
          .readString('${_keyPrefix}last_live.$profileId.$sourceId');
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastLiveChannel({
    required String profileId,
    required String sourceId,
    required String channelId,
  }) async {
    try {
      await _storage.writeString(
        '${_keyPrefix}last_live.$profileId.$sourceId',
        channelId,
      );
    } catch (_) {}
  }

  Future<void> clear({
    required String profileId,
    required String sourceId,
  }) async {
    await _storage.remove(_key(profileId, sourceId));
    final sources =
        await _storage.readStringList(_sourcesKey(profileId)) ?? const [];
    if (sources.contains(sourceId)) {
      await _storage.writeStringList(
        _sourcesKey(profileId),
        sources.where((entry) => entry != sourceId).toList(growable: false),
      );
    }
  }

  Future<void> clearProfile(String profileId) async {
    final sources =
        await _storage.readStringList(_sourcesKey(profileId)) ?? const [];
    for (final sourceId in sources) {
      await _storage.remove(_key(profileId, sourceId));
    }
    await _storage.remove(_sourcesKey(profileId));
  }

  String _key(String profileId, String sourceId) =>
      '$_keyPrefix$profileId.$sourceId';

  String _sourcesKey(String profileId) => '$_sourcesKeyPrefix$profileId';

  Future<PlaybackPreferences?> _readLegacy(String sourceId) async {
    final raw = await _storage.readString('$_keyPrefix$sourceId');
    if (raw != null) {
      final value = jsonDecode(raw);
      if (value is Map) {
        return PlaybackPreferences.fromJson(Map<String, dynamic>.from(value));
      }
    }
    final legacyQuality =
        await _storage.readString('playback.quality.$sourceId.official');
    final legacySpeed = await _storage.readDouble('playback.speed.$sourceId');
    final legacyVolume = await _storage.readDouble('playback.volume.$sourceId');
    if (legacyQuality != null || legacySpeed != null || legacyVolume != null) {
      return PlaybackPreferences(
        qualityId: legacyQuality,
        speed: PlaybackPreferences._clamp(legacySpeed ?? 1, min: 0.5, max: 3),
        volume: PlaybackPreferences._clamp(legacyVolume ?? 1, min: 0, max: 1),
      );
    }
    return null;
  }
}
