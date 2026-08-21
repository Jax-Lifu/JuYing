import 'dart:convert';

import '../../domain/models/media_source.dart';

/// 只描述已内建、经审计的来源适配器；不会下载或执行远程配置、JAR、JS、PY。
class SourceConfiguration {
  const SourceConfiguration({required this.version, required this.sources});

  final int version;
  final List<ConfiguredMediaSource> sources;

  factory SourceConfiguration.fromJsonString(String input) {
    final decoded = jsonDecode(input);
    if (decoded is! Map<String, Object?>) {
      throw const SourceConfigurationException('来源配置根节点必须是对象');
    }
    return SourceConfiguration.fromJson(decoded);
  }

  factory SourceConfiguration.fromJson(Map<String, Object?> json) {
    _onlyKeys(json, const {'version', 'sources'}, '来源配置');
    final version = json['version'];
    final rawSources = json['sources'];
    if (version is! int || version < 1 || rawSources is! List<Object?>) {
      throw const SourceConfigurationException('来源配置缺少有效版本或来源列表');
    }
    final sources = rawSources.map((value) {
      if (value is! Map<String, Object?>) {
        throw const SourceConfigurationException('来源条目必须是对象');
      }
      return ConfiguredMediaSource.fromJson(value);
    }).toList(growable: false);
    final ids = sources.map((source) => source.source.id).toSet();
    if (ids.length != sources.length) {
      throw const SourceConfigurationException('来源 ID 不可重复');
    }
    return SourceConfiguration(version: version, sources: sources);
  }
}

class ConfiguredMediaSource {
  const ConfiguredMediaSource({
    required this.adapter,
    required this.source,
    this.credentialsRef,
  });

  /// 内建适配器键。未知键在启动时拒绝，不能退化成动态代码执行。
  final String adapter;
  final MediaSource source;
  final String? credentialsRef;

  factory ConfiguredMediaSource.fromJson(Map<String, Object?> json) {
    _onlyKeys(
        json,
        const {
          'id',
          'name',
          'kind',
          'adapter',
          'entryUrl',
          'enabled',
          'authorization',
          'capabilities',
          'credentialsRef',
          'regionCode',
          'configVersion',
          'priority',
        },
        '来源条目');
    final id = _string(json, 'id');
    if (!RegExp(r'^[a-z0-9][a-z0-9-]+$').hasMatch(id)) {
      throw const SourceConfigurationException('来源 ID 格式无效');
    }
    final entryUrl = Uri.tryParse(_string(json, 'entryUrl'));
    if (entryUrl == null || entryUrl.scheme.isEmpty || entryUrl.host.isEmpty) {
      throw const SourceConfigurationException('来源入口必须是绝对地址');
    }
    final credentialsRef = json['credentialsRef'];
    if (credentialsRef != null &&
        (credentialsRef is! String ||
            !credentialsRef.startsWith('secure://'))) {
      throw const SourceConfigurationException('凭据只能使用 secure:// 引用');
    }
    final name = json['name'];
    final sourceName = name is String
        ? name
        : name is Map<String, Object?>
            ? (name['zh-CN'] as String? ?? name['en'] as String? ?? '')
            : '';
    if (sourceName.trim().isEmpty) {
      throw const SourceConfigurationException('来源名称不能为空');
    }
    final capabilities = _capabilities(json['capabilities']);
    return ConfiguredMediaSource(
      adapter: _string(json, 'adapter'),
      credentialsRef: credentialsRef as String?,
      source: MediaSource(
        id: id,
        name: sourceName,
        kind: _kind(_string(json, 'kind')),
        entryUrl: entryUrl.toString(),
        enabled:
            json['enabled'] is bool ? json['enabled']! as bool : _invalidBool(),
        authorization: _authorization(_string(json, 'authorization')),
        capabilities: capabilities,
        regionCode: json['regionCode'] as String?,
        configVersion: _positiveInt(json, 'configVersion', fallback: 1),
        priority:
            _boundedInt(json, 'priority', fallback: 0, min: -100, max: 100),
      ),
    );
  }
}

class SourceConfigurationException implements Exception {
  const SourceConfigurationException(this.message);
  final String message;
  @override
  String toString() => 'SourceConfigurationException: $message';
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw SourceConfigurationException('缺少有效字段：$key');
  }
  return value;
}

Never _invalidBool() =>
    throw const SourceConfigurationException('enabled 必须是布尔值');

int _positiveInt(
  Map<String, Object?> json,
  String key, {
  required int fallback,
}) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is! int || value < 1) {
    throw SourceConfigurationException('$key 必须是正整数');
  }
  return value;
}

int _boundedInt(
  Map<String, Object?> json,
  String key, {
  required int fallback,
  required int min,
  required int max,
}) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is! int || value < min || value > max) {
    throw SourceConfigurationException('$key 必须在 $min 到 $max 之间');
  }
  return value;
}

void _onlyKeys(Map<String, Object?> json, Set<String> keys, String label) {
  if (json.keys.any((key) => !keys.contains(key))) {
    throw SourceConfigurationException('$label包含不支持字段');
  }
}

MediaSourceKind _kind(String value) => switch (value) {
      'officialWeb' => MediaSourceKind.officialWeb,
      'authorizedApi' => MediaSourceKind.authorizedApi,
      'nas' => MediaSourceKind.nas,
      'local' => MediaSourceKind.local,
      'custom' => MediaSourceKind.custom,
      _ => throw const SourceConfigurationException('不支持的来源类型'),
    };

SourceAuthorization _authorization(String value) => switch (value) {
      'officialEntryOnly' => SourceAuthorization.officialEntryOnly,
      'userOwned' => SourceAuthorization.userOwned,
      'licensed' => SourceAuthorization.licensed,
      'unknown' => SourceAuthorization.unknown,
      _ => throw const SourceConfigurationException('不支持的授权状态'),
    };

Set<SourceCapability> _capabilities(Object? raw) {
  if (raw is! List<Object?>) {
    throw const SourceConfigurationException('capabilities 必须是数组');
  }
  return raw.map((value) {
    if (value is! String) throw const SourceConfigurationException('能力必须是字符串');
    return switch (value) {
      'browse' => SourceCapability.browse,
      'liveCatalog' => SourceCapability.liveCatalog,
      'search' => SourceCapability.search,
      'episodes' => SourceCapability.episodes,
      'nativePublicPlayback' => SourceCapability.nativePublicPlayback,
      'officialFallback' => SourceCapability.officialFallback,
      'qualitySelection' => SourceCapability.qualitySelection,
      'playbackSpeed' => SourceCapability.playbackSpeed,
      'volumeControl' => SourceCapability.volumeControl,
      'fullscreen' => SourceCapability.fullscreen,
      'continueWatching' => SourceCapability.continueWatching,
      _ => throw SourceConfigurationException('不支持的来源能力：$value'),
    };
  }).toSet();
}
