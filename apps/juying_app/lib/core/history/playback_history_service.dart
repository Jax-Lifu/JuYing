// JSON factories are intentionally colocated with serialization methods.
// ignore_for_file: sort_constructors_first

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single playback history entry.
class PlaybackHistoryItem {
  const PlaybackHistoryItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.episodeName,
    required this.episodeIndex,
    required this.positionMs,
    required this.durationMs,
    required this.timestampMs,
  });

  final String id;
  final String title;
  final String posterUrl;
  final String episodeName;
  final int episodeIndex;
  final int positionMs;
  final int durationMs;
  final int timestampMs;

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'posterUrl': posterUrl,
        'episodeName': episodeName,
        'episodeIndex': episodeIndex,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'timestampMs': timestampMs,
      };

  factory PlaybackHistoryItem.fromJson(Map<String, dynamic> json) {
    return PlaybackHistoryItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      posterUrl: json['posterUrl']?.toString() ?? '',
      episodeName: json['episodeName']?.toString() ?? '',
      episodeIndex: (json['episodeIndex'] as num?)?.toInt() ?? 1,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      timestampMs: (json['timestampMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Service managing persistent viewing history across local storage and multi-device sync.
///
/// **What**: Records playback timestamps, episode indexes, and duration metrics into `SharedPreferences`.
///
/// **Why**: Allows users to resume watching right where they left off and synchronizes history across TV/mobile/PC.
class PlaybackHistoryService {
  PlaybackHistoryService._();
  static final PlaybackHistoryService instance = PlaybackHistoryService._();

  static const String _prefKey = 'juying_playback_history';
  Future<void> _writeTail = Future<void>.value();

  Future<List<PlaybackHistoryItem>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) return <PlaybackHistoryItem>[];

      final list = json.decode(raw) as List<dynamic>?;
      if (list == null) return <PlaybackHistoryItem>[];

      final history = list
          .whereType<Map<String, dynamic>>()
          .map(PlaybackHistoryItem.fromJson)
          .toList()
        ..sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
      return _coalesceByMedia(history);
    } catch (e) {
      debugPrint('[PlaybackHistory] Error loading history: $e');
      return <PlaybackHistoryItem>[];
    }
  }

  /// 合并旧版按“标题+集数”写入的重复项，并用同节目已有封面补齐最新进度记录。
  List<PlaybackHistoryItem> _coalesceByMedia(
    List<PlaybackHistoryItem> history,
  ) {
    final merged = <String, PlaybackHistoryItem>{};
    for (final item in history) {
      final key = item.title.trim().isEmpty ? item.id : item.title.trim();
      final latest = merged[key];
      if (latest == null) {
        merged[key] = item;
        continue;
      }
      if (latest.posterUrl.isNotEmpty || item.posterUrl.isEmpty) continue;

      // 播放位置取时间最新项，媒体身份与封面取元数据更完整的旧项。
      merged[key] = PlaybackHistoryItem(
        id: item.id,
        title: latest.title,
        posterUrl: item.posterUrl,
        episodeName: latest.episodeName,
        episodeIndex: latest.episodeIndex,
        positionMs: latest.positionMs,
        durationMs: latest.durationMs,
        timestampMs: latest.timestampMs,
      );
    }
    // 保存流程会在读取结果上执行 remove/insert，领域服务必须维持可变列表契约。
    return merged.values.toList();
  }

  Future<void> saveHistory(PlaybackHistoryItem item) {
    // 播放页切集和 WebView 回调可能在相邻帧同时写入；串行化读改写事务，
    // 防止较早的剧集在较晚完成时覆盖最新选择。
    _writeTail = _writeTail.then((_) => _saveHistoryNow(item));
    return _writeTail;
  }

  Future<void> _saveHistoryNow(PlaybackHistoryItem item) async {
    try {
      final history = await getHistory();
      final index = history.indexWhere((h) => h.id == item.id);
      if (index != -1) {
        history.removeAt(index);
      }
      history.insert(0, item);

      // Keep max 100 history entries
      if (history.length > 100) {
        history.removeRange(100, history.length);
      }

      final prefs = await SharedPreferences.getInstance();
      final raw = json.encode(history.map((h) => h.toJson()).toList());
      await prefs.setString(_prefKey, raw);
    } catch (e) {
      debugPrint('[PlaybackHistory] Error saving history: $e');
    }
  }

  /// 返回媒体最近一次播放记录，并兼容旧版本以标题和集数组合生成的 ID。
  Future<PlaybackHistoryItem?> findLatestForMedia({
    required String mediaId,
    required String title,
  }) async {
    await _writeTail;
    final history = await getHistory();
    for (final item in history) {
      if (item.id == mediaId) return item;
    }
    for (final item in history) {
      if (item.title == title) return item;
    }
    return null;
  }

  Future<void> clearHistory() async {
    await _writeTail;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  /// 在写入队列内读取并变更历史，避免网络同步用旧快照覆盖并发保存的播放进度。
  Future<void> updateHistory(
    List<PlaybackHistoryItem> Function(List<PlaybackHistoryItem>) update,
  ) {
    final write = _writeTail.then((_) async {
      final items = update(await getHistory())
        ..sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
      final normalized = _coalesceByMedia(items);
      final bounded = normalized.take(100).toList(growable: false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefKey,
        json.encode(bounded.map((item) => item.toJson()).toList()),
      );
    });
    // 当前事务仍向调用者报错，但不能阻断后续播放记录的写入。
    _writeTail = write.then<void>((_) {}, onError: (Object error) {});
    return write;
  }
}
