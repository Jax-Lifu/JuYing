// JSON factories are intentionally colocated with serialization methods.
// ignore_for_file: sort_constructors_first

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Represents the four user-data domains synchronized between devices.
class SyncBundle {
  const SyncBundle({
    required this.deviceId,
    required this.updatedAtMs,
    this.history = const <Map<String, dynamic>>[],
    this.favorites = const <Map<String, dynamic>>[],
    this.subscriptions = const <Map<String, dynamic>>[],
    this.settings = const <String, dynamic>{},
  });

  final String deviceId;
  final int updatedAtMs;
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>> favorites;
  final List<Map<String, dynamic>> subscriptions;
  final Map<String, dynamic> settings;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'deviceId': deviceId,
        'updatedAtMs': updatedAtMs,
        'history': history,
        'favorites': favorites,
        'subscriptions': subscriptions,
        'settings': settings,
      };

  factory SyncBundle.fromJson(Map<String, dynamic> json) {
    return SyncBundle(
      deviceId: json['deviceId']?.toString() ?? 'unknown',
      updatedAtMs: _timestampOf(json),
      history: _mapList(json['history']),
      favorites: _mapList(json['favorites']),
      subscriptions: _mapList(json['subscriptions']),
      settings: _stringMap(json['settings']),
    );
  }
}

/// WebDAV v1 synchronization with compressed, split and atomic remote files.
///
/// The service keeps the legacy monolithic download path as a one-way migration
/// bridge. All new writes use `/JuYing/sync/v1/*.json.gz`, so partially updated
/// domains cannot corrupt unrelated user data.
class WebDavSyncService {
  WebDavSyncService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
              ),
            );

  static const String _rootDirectory = 'JuYing';
  static const String _syncDirectory = 'sync';
  static const String _versionDirectory = 'v1';
  static const List<String> _partNames = <String>[
    'history',
    'favorites',
    'subscriptions',
    'settings',
  ];

  final Dio _dio;
  // null 表示 GET 404；空字符串表示已有文件未提供 ETag，不能安全覆盖。
  final Map<String, String?> _downloadedEtags = <String, String?>{};

  /// Uploads every sync domain using Gzip and WebDAV PUT-then-MOVE semantics.
  Future<bool> uploadSyncBundle({
    required String webDavUrl,
    required String username,
    required String password,
    required SyncBundle bundle,
  }) async {
    final headers = _authorizationHeaders(username, password);
    try {
      await _ensureRemoteDirectories(webDavUrl, headers);
      final parts = <String, Object>{
        'history': _normalizeEntities(bundle.history, bundle.updatedAtMs),
        'favorites': _normalizeEntities(bundle.favorites, bundle.updatedAtMs),
        'subscriptions':
            _normalizeEntities(bundle.subscriptions, bundle.updatedAtMs),
        'settings': bundle.settings,
      };

      for (final entry in parts.entries) {
        final payload = <String, dynamic>{
          'schemaVersion': 1,
          'deviceId': bundle.deviceId,
          'updatedAt': bundle.updatedAtMs,
          'data': entry.value,
        };
        final bytes = gzip.encode(utf8.encode(jsonEncode(payload)));
        final target = _partUrl(webDavUrl, entry.key);
        await _atomicWrite(
          targetUrl: target,
          bytes: bytes,
          headers: headers,
          deviceId: bundle.deviceId,
        );
      }
      return true;
    } on Object catch (error) {
      debugPrint('[WebDAV Sync] 上传失败: ${_safeError(error)}');
      return false;
    }
  }

  /// Downloads v1 or legacy data; only an absent replica returns null.
  /// Read failures propagate so callers cannot overwrite unread remote data.
  Future<SyncBundle?> downloadSyncBundle({
    required String webDavUrl,
    required String username,
    required String password,
  }) async {
    final headers = _authorizationHeaders(username, password);
    try {
      final parts = <String, _RemotePart>{};
      final revisions = <String, String?>{};
      for (final name in _partNames) {
        final url = _partUrl(webDavUrl, name);
        final part = await _downloadPart(url, headers);
        revisions[url] = part == null ? null : part.etag ?? '';
        if (part != null) {
          final data = part.data;
          if (name == 'settings'
              ? data is! Map
              : data is! List || data.any((item) => item is! Map)) {
            throw FormatException('$name 同步数据结构无效');
          }
          parts[name] = part;
        }
      }
      if (parts.isEmpty) {
        final legacy = await _downloadLegacyBundle(webDavUrl, headers);
        _downloadedEtags.addAll(revisions);
        return legacy;
      }

      final newestPart = parts.values.fold<_RemotePart>(
        parts.values.first,
        (current, candidate) =>
            candidate.updatedAt > current.updatedAt ? candidate : current,
      );
      _downloadedEtags.addAll(revisions);
      return SyncBundle(
        deviceId: newestPart.deviceId,
        updatedAtMs: newestPart.updatedAt,
        history: _normalizeEntities(
          _mapList(parts['history']?.data),
          parts['history']?.updatedAt ?? 0,
        ),
        favorites: _normalizeEntities(
          _mapList(parts['favorites']?.data),
          parts['favorites']?.updatedAt ?? 0,
        ),
        subscriptions: _normalizeEntities(
          _mapList(parts['subscriptions']?.data),
          parts['subscriptions']?.updatedAt ?? 0,
        ),
        settings: _stringMap(parts['settings']?.data),
      );
    } on Object catch (error) {
      debugPrint('[WebDAV Sync] 下载失败: ${_safeError(error)}');
      rethrow;
    }
  }

  /// Merges both replicas with deterministic entity and field-level LWW.
  ///
  /// Tombstones are retained so an offline device cannot resurrect a deleted
  /// item. Callers may compact sufficiently old tombstones after all known
  /// devices have observed them.
  SyncBundle mergeBundles(SyncBundle local, SyncBundle remote) {
    final updatedAt = local.updatedAtMs > remote.updatedAtMs
        ? local.updatedAtMs
        : remote.updatedAtMs;
    return SyncBundle(
      deviceId: local.deviceId,
      updatedAtMs: updatedAt,
      history: _mergeEntities(
        local.history,
        remote.history,
        historyProgressAware: true,
        localFallbackTimestamp: local.updatedAtMs,
        remoteFallbackTimestamp: remote.updatedAtMs,
      ),
      favorites: _mergeEntities(
        local.favorites,
        remote.favorites,
        mergeFields: true,
        localFallbackTimestamp: local.updatedAtMs,
        remoteFallbackTimestamp: remote.updatedAtMs,
      ),
      subscriptions: _mergeEntities(
        local.subscriptions,
        remote.subscriptions,
        localFallbackTimestamp: local.updatedAtMs,
        remoteFallbackTimestamp: remote.updatedAtMs,
      ),
      settings: _mergeSettings(
        local.settings,
        remote.settings,
        local.updatedAtMs,
        remote.updatedAtMs,
      ),
    );
  }

  Future<void> _ensureRemoteDirectories(
    String baseUrl,
    Map<String, dynamic> headers,
  ) async {
    var current = _trimTrailingSlash(baseUrl);
    for (final segment in <String>[
      _rootDirectory,
      _syncDirectory,
      _versionDirectory,
    ]) {
      current = '$current/$segment';
      final response = await _dio.request<dynamic>(
        current,
        options: Options(
          method: 'MKCOL',
          headers: headers,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      // 405 is the interoperable WebDAV response for an existing collection.
      if (response.statusCode != 201 && response.statusCode != 405) {
        throw StateError('MKCOL 返回 ${response.statusCode}');
      }
    }
  }

  Future<void> _atomicWrite({
    required String targetUrl,
    required List<int> bytes,
    required Map<String, dynamic> headers,
    required String deviceId,
  }) async {
    // 必须比较参与本次合并的 GET 版本；此时重新 HEAD 会放过未合并的并发写入。
    final etag = _downloadedEtags.containsKey(targetUrl)
        ? _downloadedEtags[targetUrl]
        : await _readEtag(targetUrl, headers);
    if (etag != null && etag.isEmpty) {
      throw StateError('远端未提供 ETag，无法安全覆盖同步文件');
    }
    final safeDevice = deviceId.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
    final temporaryUrl =
        '$targetUrl.tmp-$safeDevice-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final putResponse = await _dio.put<List<int>>(
        temporaryUrl,
        data: bytes,
        options: Options(
          headers: <String, dynamic>{
            ...headers,
            'Content-Type': 'application/gzip',
            'If-None-Match': '*',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (!_isWriteSuccess(putResponse.statusCode)) {
        throw StateError('临时文件 PUT 返回 ${putResponse.statusCode}');
      }

      final moveHeaders = <String, dynamic>{
        ...headers,
        'Destination': targetUrl,
        'Overwrite': etag == null ? 'F' : 'T',
      };
      if (etag != null) {
        // A tagged If-list applies the ETag to the destination rather than the
        // temporary MOVE source, avoiding silent last-writer data loss.
        moveHeaders['If'] = '<$targetUrl> ([$etag])';
      }
      final moveResponse = await _dio.request<dynamic>(
        temporaryUrl,
        options: Options(
          method: 'MOVE',
          headers: moveHeaders,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (!_isWriteSuccess(moveResponse.statusCode)) {
        throw StateError('原子 MOVE 返回 ${moveResponse.statusCode}');
      }
      _downloadedEtags.remove(targetUrl);
    } finally {
      await _deleteTemporaryFile(temporaryUrl, headers);
    }
  }

  Future<String?> _readEtag(
    String targetUrl,
    Map<String, dynamic> headers,
  ) async {
    final response = await _dio.head<dynamic>(
      targetUrl,
      options: Options(
        headers: headers,
        validateStatus: (status) => status == 200 || status == 404,
      ),
    );
    if (response.statusCode == 404) return null;
    return response.headers.value('etag') ?? '';
  }

  Future<void> _deleteTemporaryFile(
    String temporaryUrl,
    Map<String, dynamic> headers,
  ) async {
    try {
      await _dio.delete<dynamic>(
        temporaryUrl,
        options: Options(
          headers: headers,
          validateStatus: (status) =>
              status == 200 || status == 204 || status == 404,
        ),
      );
    } on Object {
      // A failed cleanup must not mask the authoritative PUT/MOVE result.
    }
  }

  Future<_RemotePart?> _downloadPart(
    String url,
    Map<String, dynamic> headers,
  ) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: headers,
        validateStatus: (status) => status == 200 || status == 404,
      ),
    );
    if (response.statusCode == 404) return null;
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('同步文件为空');
    }
    final decoded = jsonDecode(utf8.decode(gzip.decode(bytes)));
    if (decoded is! Map) throw const FormatException('同步文件不是 JSON 对象');
    final payload = Map<String, dynamic>.from(decoded);
    return _RemotePart(
      deviceId: payload['deviceId']?.toString() ?? 'unknown',
      updatedAt: _timestampOf(payload),
      data: payload['data'],
      etag: response.headers.value('etag'),
    );
  }

  Future<SyncBundle?> _downloadLegacyBundle(
    String baseUrl,
    Map<String, dynamic> headers,
  ) async {
    final response = await _dio.get<List<int>>(
      '${_trimTrailingSlash(baseUrl)}/juying_sync.gz',
      options: Options(
        responseType: ResponseType.bytes,
        headers: headers,
        validateStatus: (status) => status == 200 || status == 404,
      ),
    );
    if (response.statusCode == 404) return null;
    if (response.data == null || response.data!.isEmpty) {
      throw const FormatException('旧同步文件为空');
    }
    final decoded = jsonDecode(utf8.decode(gzip.decode(response.data!)));
    if (decoded is! Map) throw const FormatException('旧同步文件不是 JSON 对象');
    return SyncBundle.fromJson(Map<String, dynamic>.from(decoded));
  }

  String _partUrl(String baseUrl, String partName) =>
      '${_trimTrailingSlash(baseUrl)}/$_rootDirectory/$_syncDirectory/'
      '$_versionDirectory/$partName.json.gz';

  static Map<String, dynamic> _authorizationHeaders(
    String username,
    String password,
  ) =>
      <String, dynamic>{
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      };

  static String _trimTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  static bool _isWriteSuccess(int? status) =>
      status == 200 || status == 201 || status == 204;

  static String _safeError(Object error) {
    if (error is DioException) {
      return 'HTTP ${error.response?.statusCode ?? '-'}: ${error.message}';
    }
    return error.toString();
  }
}

class _RemotePart {
  const _RemotePart({
    required this.deviceId,
    required this.updatedAt,
    required this.data,
    required this.etag,
  });

  final String deviceId;
  final int updatedAt;
  final Object? data;
  final String? etag;
}

List<Map<String, dynamic>> _mergeEntities(
  List<Map<String, dynamic>> local,
  List<Map<String, dynamic>> remote, {
  required int localFallbackTimestamp,
  required int remoteFallbackTimestamp,
  bool mergeFields = false,
  bool historyProgressAware = false,
}) {
  final merged = <String, Map<String, dynamic>>{};
  for (final raw in _normalizeEntities(local, localFallbackTimestamp)) {
    merged[_entityIdOf(raw)] = raw;
  }
  for (final raw in _normalizeEntities(remote, remoteFallbackTimestamp)) {
    final id = _entityIdOf(raw);
    final existing = merged[id];
    if (existing == null) {
      merged[id] = raw;
      continue;
    }
    if (historyProgressAware &&
        !(existing['isDeleted'] as bool) &&
        !(raw['isDeleted'] as bool)) {
      final localProgressTime = _number(existing['progressTimestamp']);
      final remoteProgressTime = _number(raw['progressTimestamp']);
      if (remoteProgressTime != localProgressTime) {
        merged[id] = remoteProgressTime > localProgressTime ? raw : existing;
        continue;
      }
    }
    if (mergeFields &&
        !(existing['isDeleted'] as bool) &&
        !(raw['isDeleted'] as bool)) {
      merged[id] = _mergeEntityFields(existing, raw);
      continue;
    }
    if (_timestampOf(raw) > _timestampOf(existing)) merged[id] = raw;
  }
  final result = merged.values.toList()
    ..sort((left, right) => _entityIdOf(left).compareTo(_entityIdOf(right)));
  return result;
}

Map<String, dynamic> _mergeEntityFields(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  final result = Map<String, dynamic>.from(local);
  final localTimes = _timestampMap(local['fieldUpdatedAt']);
  final remoteTimes = _timestampMap(remote['fieldUpdatedAt']);
  final allKeys = <String>{...local.keys, ...remote.keys}..removeAll(<String>{
      'entityId',
      'id',
      'updatedAt',
      'updatedAtMs',
      'fieldUpdatedAt',
    });
  final mergedTimes = <String, int>{};
  for (final key in allKeys) {
    final localTime = localTimes[key] ?? _timestampOf(local);
    final remoteTime = remoteTimes[key] ?? _timestampOf(remote);
    if (!local.containsKey(key) ||
        (remote.containsKey(key) && remoteTime > localTime)) {
      result[key] = remote[key];
      mergedTimes[key] = remoteTime;
    } else {
      mergedTimes[key] = localTime;
    }
  }
  result['updatedAt'] = _timestampOf(local) > _timestampOf(remote)
      ? _timestampOf(local)
      : _timestampOf(remote);
  result['fieldUpdatedAt'] = mergedTimes;
  return result;
}

Map<String, dynamic> _mergeSettings(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
  int localFallbackTimestamp,
  int remoteFallbackTimestamp,
) {
  final result = Map<String, dynamic>.from(local);
  final localTimes = _timestampMap(local['_fieldUpdatedAt']);
  final remoteTimes = _timestampMap(remote['_fieldUpdatedAt']);
  final keys = <String>{...local.keys, ...remote.keys}
    ..remove('_fieldUpdatedAt');
  final mergedTimes = <String, int>{};
  for (final key in keys) {
    final localTime = localTimes[key] ?? localFallbackTimestamp;
    final remoteTime = remoteTimes[key] ?? remoteFallbackTimestamp;
    if (!local.containsKey(key) ||
        (remote.containsKey(key) && remoteTime > localTime)) {
      result[key] = remote[key];
      mergedTimes[key] = remoteTime;
    } else {
      mergedTimes[key] = localTime;
    }
  }
  result['_fieldUpdatedAt'] = mergedTimes;
  return result;
}

List<Map<String, dynamic>> _normalizeEntities(
  List<Map<String, dynamic>> entities,
  int fallbackTimestamp,
) {
  final normalized = <Map<String, dynamic>>[];
  for (final entity in entities) {
    final id = _entityIdOf(entity);
    if (id.isEmpty) continue;
    normalized.add(<String, dynamic>{
      ...entity,
      'entityId': id,
      'updatedAt': _timestampOf(entity, fallbackTimestamp),
      'isDeleted': entity['isDeleted'] == true,
    });
  }
  return normalized;
}

String _entityIdOf(Map<String, dynamic> entity) =>
    entity['entityId']?.toString() ?? entity['id']?.toString() ?? '';

int _timestampOf(Map<String, dynamic> value, [int fallback = 0]) =>
    _number(value['updatedAt'] ?? value['updatedAtMs'], fallback);

int _number(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

Map<String, int> _timestampMap(Object? value) {
  if (value is! Map) return <String, int>{};
  return <String, int>{
    for (final entry in value.entries)
      entry.key.toString(): _number(entry.value),
  };
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

Map<String, dynamic> _stringMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
