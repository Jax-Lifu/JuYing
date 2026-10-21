import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:juying/core/history/playback_history_service.dart';
import 'package:juying/features/sync/services/webdav_credential_store.dart';
import 'package:juying/features/sync/services/webdav_sync_service.dart';

/// Coordinates local history persistence with bidirectional WebDAV replication.
///
/// Sync is deliberately serialized: overlapping launch/manual/playback triggers
/// otherwise race on ETags and can make a newer local position lose to itself.
class WebDavSyncCoordinator {
  WebDavSyncCoordinator({
    WebDavCredentialStore? credentialStore,
    WebDavSyncService? syncService,
    PlaybackHistoryService? historyService,
    Duration pushDebounce = const Duration(seconds: 3),
  })  : _credentialStore = credentialStore ?? SecureWebDavCredentialStore(),
        _syncService = syncService ?? WebDavSyncService(),
        _historyService = historyService ?? PlaybackHistoryService.instance,
        _pushDebounce = pushDebounce;

  static final WebDavSyncCoordinator instance = WebDavSyncCoordinator();
  static const String _deviceIdKey = 'juying_sync_device_id_v1';

  final WebDavCredentialStore _credentialStore;
  final WebDavSyncService _syncService;
  final PlaybackHistoryService _historyService;
  final Duration _pushDebounce;
  Completer<bool>? _activeSync;
  Timer? _pushTimer;
  bool _pushPending = false;

  /// Runs one pull-merge-push transaction, sharing an in-flight transaction.
  Future<bool> syncNow() async {
    final existing = _activeSync;
    if (existing != null) return existing.future;

    final active = Completer<bool>();
    _activeSync = active;
    try {
      final result = await _performSync();
      active.complete(result);
      return result;
    } on Object catch (error) {
      debugPrint('[WebDAV Sync] 自动同步失败: $error');
      active.complete(false);
      return false;
    } finally {
      if (identical(_activeSync, active)) _activeSync = null;
      if (_pushPending) {
        _pushPending = false;
        unawaited(syncNow());
      }
    }
  }

  /// Coalesces rapid seeks/route exits into one network transaction after 3s.
  void schedulePush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDebounce, () {
      _pushTimer = null;
      // 当前上传快照可能早于本次保存；保留一次后续事务，而不是复用旧结果。
      if (_activeSync != null) {
        _pushPending = true;
      } else {
        unawaited(syncNow());
      }
    });
  }

  void dispose() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _pushPending = false;
  }

  Future<bool> _performSync() async {
    final preferences = await SharedPreferences.getInstance();
    final credentials = await _credentialStore.read(
      legacyPreferences: preferences,
    );
    if (credentials == null || !credentials.isComplete) return false;

    final deviceId = await _readOrCreateDeviceId(preferences);
    final remote = await _syncService.downloadSyncBundle(
      webDavUrl: credentials.url,
      username: credentials.username,
      password: credentials.password,
    );
    late SyncBundle merged;
    await _historyService.updateHistory((history) {
      final local = SyncBundle(
        deviceId: deviceId,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        history: history.map(_historyToSyncJson).toList(growable: false),
      );
      merged =
          remote == null ? local : _syncService.mergeBundles(local, remote);
      return merged.history
          .where((item) => item['isDeleted'] != true)
          .map(PlaybackHistoryItem.fromJson)
          .toList(growable: false);
    });
    return _syncService.uploadSyncBundle(
      webDavUrl: credentials.url,
      username: credentials.username,
      password: credentials.password,
      bundle: merged,
    );
  }

  Future<String> _readOrCreateDeviceId(
    SharedPreferences preferences,
  ) async {
    final existing = preferences.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await preferences.setString(_deviceIdKey, created);
    return created;
  }

  Map<String, dynamic> _historyToSyncJson(PlaybackHistoryItem item) =>
      <String, dynamic>{
        ...item.toJson(),
        'entityId': item.id,
        'updatedAt': item.timestampMs,
        'progressTimestamp': item.timestampMs,
        'isDeleted': false,
      };
}
