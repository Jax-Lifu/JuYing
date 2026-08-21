import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'playback_history_retention.dart';
import '../../domain/models/playback_history.dart';
import '../../domain/models/unified_media.dart';

class PlaybackHistoryStore {
  PlaybackHistoryStore({
    SharedPreferencesAsync? preferences,
    DateTime Function()? now,
  })  : _preferences = preferences,
        _now = now ?? DateTime.now;

  static const defaultProfileId = 'default';
  static const _keyPrefix = 'playback.history.v1.';
  static const _maximumEntries = 40;
  final SharedPreferencesAsync? _preferences;
  final DateTime Function() _now;

  Future<List<PlaybackHistoryEntry>> load({
    String profileId = defaultProfileId,
  }) async {
    String? raw;
    try {
      raw = await (_preferences ?? SharedPreferencesAsync()).getString(
        _key(profileId),
      );
    } catch (_) {
      return const [];
    }
    if (raw == null) return const [];
    try {
      final value = jsonDecode(raw);
      if (value is! List) return const [];
      final decoded = value
          .whereType<Map>()
          .map((item) => _decode(Map<String, dynamic>.from(item), profileId))
          .whereType<PlaybackHistoryEntry>()
          .toList(growable: false);
      final entries = PlaybackHistoryRetention.apply(decoded, now: _now())
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<void> record({
    required PlaybackDescriptor playback,
    required Duration position,
    Duration? duration,
    String profileId = defaultProfileId,
  }) async {
    final previous = await load(profileId: profileId);
    final entry = PlaybackHistoryEntry.fromPlayback(
      profileId: profileId,
      playback: playback,
      position: position,
      duration: duration,
      updatedAt: _now(),
    );
    final merged = [entry, ...previous.where((item) => item.id != entry.id)]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final encoded =
        merged.take(_maximumEntries).map(_encode).toList(growable: false);
    try {
      await (_preferences ?? SharedPreferencesAsync()).setString(
        _key(profileId),
        jsonEncode(encoded),
      );
    } catch (_) {
      // 存储不可用不能影响已授权的播放会话；下次再尝试持久化即可。
    }
  }

  Future<void> clearProfile({String profileId = defaultProfileId}) async {
    try {
      await (_preferences ?? SharedPreferencesAsync()).remove(_key(profileId));
    } catch (_) {
      // 删除操作失败时由调用方保留档案，避免制造不可解释的半删除状态。
      rethrow;
    }
  }

  String _key(String profileId) => '$_keyPrefix$profileId';

  Map<String, Object?> _encode(PlaybackHistoryEntry entry) => {
        'sourceId': entry.sourceId,
        'sourceEpisodeId': entry.sourceEpisodeId,
        'title': entry.title,
        'officialPageUri': entry.officialPageUri.toString(),
        'posterUri': entry.posterUri?.toString(),
        'positionMs': entry.position.inMilliseconds,
        'durationMs': entry.duration?.inMilliseconds,
        'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
      };

  PlaybackHistoryEntry? _decode(Map<String, dynamic> value, String profileId) {
    final sourceId = value['sourceId'];
    final episodeId = value['sourceEpisodeId'];
    final title = value['title'];
    final officialPageUri =
        Uri.tryParse(value['officialPageUri']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(value['updatedAt']?.toString() ?? '');
    if (sourceId is! String ||
        episodeId is! String ||
        title is! String ||
        officialPageUri == null ||
        updatedAt == null) {
      return null;
    }
    return PlaybackHistoryEntry(
      profileId: profileId,
      sourceId: sourceId,
      sourceEpisodeId: episodeId,
      title: title,
      officialPageUri: officialPageUri,
      posterUri: _networkUri(value['posterUri']?.toString()),
      position:
          Duration(milliseconds: (value['positionMs'] as num?)?.toInt() ?? 0),
      duration: value['durationMs'] is num
          ? Duration(milliseconds: (value['durationMs'] as num).toInt())
          : null,
      updatedAt: updatedAt.toLocal(),
    );
  }

  Uri? _networkUri(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
  }
}
