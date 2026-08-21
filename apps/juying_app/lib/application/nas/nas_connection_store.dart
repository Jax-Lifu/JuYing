import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/nas_connection.dart';

/// NAS 配置仅保存非敏感连接元数据。凭据由 [NasCredentialStore] 单独管理。
class NasConnectionStore {
  NasConnectionStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const _key = 'nas.connections.v1';
  final SharedPreferencesAsync? _preferences;

  Future<List<NasConnection>> load() async {
    try {
      final raw =
          await (_preferences ?? SharedPreferencesAsync()).getString(_key);
      if (raw == null) return const [];
      final value = jsonDecode(raw);
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((item) => _decode(Map<String, dynamic>.from(item)))
          .whereType<NasConnection>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsert(NasConnection connection) async {
    final connections = await load();
    final next = [
      connection,
      ...connections.where((item) => item.id != connection.id),
    ];
    await (_preferences ?? SharedPreferencesAsync()).setString(
      _key,
      jsonEncode(next.map(_encode).toList(growable: false)),
    );
  }

  Map<String, Object?> _encode(NasConnection connection) => {
        'id': connection.id,
        'name': connection.name,
        'protocol': connection.protocol.name,
        'endpoint': connection.endpoint.toString(),
        'credentialsRef': connection.credentialsRef,
        'lastVerifiedAt': connection.lastVerifiedAt?.toUtc().toIso8601String(),
      };

  NasConnection? _decode(Map<String, dynamic> value) {
    final id = value['id'];
    final name = value['name'];
    final endpoint = Uri.tryParse(value['endpoint']?.toString() ?? '');
    final ref = value['credentialsRef'];
    final protocol = NasProtocol.values
        .where((item) => item.name == value['protocol'])
        .firstOrNull;
    if (id is! String ||
        name is! String ||
        endpoint == null ||
        ref is! String ||
        !ref.startsWith('secure://') ||
        protocol == null) {
      return null;
    }
    return NasConnection(
      id: id,
      name: name,
      protocol: protocol,
      endpoint: endpoint,
      credentialsRef: ref,
      lastVerifiedAt:
          DateTime.tryParse(value['lastVerifiedAt']?.toString() ?? ''),
    );
  }
}
