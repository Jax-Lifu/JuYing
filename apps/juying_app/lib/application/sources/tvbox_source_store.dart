import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/tvbox_source.dart';

abstract interface class TvboxSourceStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesTvboxSourceStorage implements TvboxSourceStorage {
  SharedPreferencesTvboxSourceStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}

/// 只持久化配置入口与权利确认时间；不保存直播清单或播放地址。
class TvboxSourceStore {
  TvboxSourceStore({TvboxSourceStorage? storage}) : _storage = storage;
  static const _key = 'sources.tvbox-live.v1';
  final TvboxSourceStorage? _storage;

  Future<List<TvboxSourceDefinition>> load() async {
    try {
      final raw =
          await (_storage ?? SharedPreferencesTvboxSourceStorage()).read(_key);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((value) => _decode(Map<String, Object?>.from(value)))
          .whereType<TvboxSourceDefinition>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsert(TvboxSourceDefinition source) async {
    final current = await load();
    final next = [source, ...current.where((item) => item.id != source.id)];
    await (_storage ?? SharedPreferencesTvboxSourceStorage())
        .write(_key, jsonEncode(next.map(_encode).toList(growable: false)));
  }

  Future<void> remove(String sourceId) async {
    final remaining = (await load())
        .where((source) => source.id != sourceId)
        .toList(growable: false);
    await (_storage ?? SharedPreferencesTvboxSourceStorage()).write(
        _key, jsonEncode(remaining.map(_encode).toList(growable: false)));
  }

  Map<String, Object?> _encode(TvboxSourceDefinition source) => {
        'id': source.id,
        'name': source.name,
        'configUri': source.configUri.toString(),
        'rightsConfirmedAt': source.rightsConfirmedAt.toUtc().toIso8601String(),
        if (source.epgTemplate != null) 'epgTemplate': source.epgTemplate,
        'enabled': source.enabled,
      };

  TvboxSourceDefinition? _decode(Map<String, Object?> value) {
    final id = value['id'];
    final name = value['name'];
    final uri = Uri.tryParse(value['configUri']?.toString() ?? '');
    final confirmed =
        DateTime.tryParse(value['rightsConfirmedAt']?.toString() ?? '');
    final enabled = value['enabled'];
    final epgTemplate = value['epgTemplate']?.toString();
    if (id is! String ||
        !RegExp(r'^tvbox-[a-z0-9-]+$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        confirmed == null ||
        enabled is! bool ||
        (epgTemplate != null && !_validEpgTemplate(epgTemplate))) {
      return null;
    }
    return TvboxSourceDefinition(
        id: id,
        name: name,
        configUri: uri,
        rightsConfirmedAt: confirmed,
        epgTemplate: epgTemplate,
        enabled: enabled);
  }

  bool _validEpgTemplate(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }
}
