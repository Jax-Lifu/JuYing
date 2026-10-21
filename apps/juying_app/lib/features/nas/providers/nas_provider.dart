import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/features/nas/models/nas_server_config.dart';
import 'package:juying/features/nas/models/nas_share_item.dart';
import 'package:juying/features/nas/services/lan_nas_service.dart';
import 'package:juying/features/nas/services/nas_credential_store.dart';

/// Storage key for persisting configured NAS connections.
const String _nasServersStorageKey = 'juying_persisted_nas_servers_v1';

/// Available NAS file explorer view presentation modes.
enum NasViewMode {
  grid('图标', Icons.grid_view_rounded),
  list('列表', Icons.view_list_rounded),
  details('详情', Icons.table_rows_rounded);

  const NasViewMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Provider exposing singleton [LanNasService].
final lanNasServiceProvider = Provider<LanNasService>((ref) {
  return LanNasService();
});

/// StateNotifier managing persistent list of user-configured NAS servers.
class NasServersNotifier extends StateNotifier<List<NasServerConfig>> {
  NasServersNotifier({NasCredentialStore? credentialStore})
      : _credentialStore = credentialStore ?? SecureNasCredentialStore(),
        super(const <NasServerConfig>[]) {
    _loadPersistedServers();
  }

  final NasCredentialStore _credentialStore;

  Future<void> _loadPersistedServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_nasServersStorageKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final list = json.decode(rawJson) as List<dynamic>;
        final loaded = <NasServerConfig>[];
        var migratedLegacyPassword = false;
        for (final item in list) {
          final server = NasServerConfig.fromJson(item as Map<String, dynamic>);
          final legacyPassword = server.password;
          String? securePassword;
          try {
            securePassword = await _credentialStore.readPassword(server.id);
            if ((securePassword == null || securePassword.isEmpty) &&
                legacyPassword != null &&
                legacyPassword.isNotEmpty) {
              await _credentialStore.writePassword(server.id, legacyPassword);
              securePassword = legacyPassword;
              migratedLegacyPassword = true;
            }
          } catch (e) {
            debugPrint('[NasServersNotifier] 读取安全凭据失败: $e');
          }
          loaded.add(server.copyWith(password: securePassword));
        }
        state = loaded;
        if (migratedLegacyPassword) await _persistServers(loaded);
      }
    } catch (e) {
      debugPrint(
          '[NasServersNotifier] Error loading persisted NAS servers: $e');
    }
  }

  Future<void> _persistServers(List<NasServerConfig> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(servers.map((s) => s.toJson()).toList());
      await prefs.setString(_nasServersStorageKey, jsonString);
    } catch (e) {
      debugPrint('[NasServersNotifier] Error saving NAS servers to disk: $e');
    }
  }

  Future<void> addServer(NasServerConfig server) async {
    // Avoid duplicate IDs
    final exists = state.any((s) => s.id == server.id);
    final updated = exists
        ? state.map((s) => s.id == server.id ? server : s).toList()
        : <NasServerConfig>[...state, server];

    state = updated;
    await _persistCredential(server);
    await _persistServers(updated);
  }

  Future<void> removeServer(String serverId) async {
    final updated = state.where((s) => s.id != serverId).toList();
    state = updated;
    try {
      await _credentialStore.deletePassword(serverId);
    } catch (e) {
      debugPrint('[NasServersNotifier] 删除安全凭据失败: $e');
    }
    await _persistServers(updated);
  }

  Future<void> unmountAndRemoveServer(
    NasServerConfig server,
    LanNasService service,
  ) async {
    await service.unmountServer(server);
    await removeServer(server.id);
  }

  Future<void> updateServer(NasServerConfig updatedServer) async {
    final updated =
        state.map((s) => s.id == updatedServer.id ? updatedServer : s).toList();
    state = updated;
    await _persistCredential(updatedServer);
    await _persistServers(updated);
  }

  Future<void> _persistCredential(NasServerConfig server) async {
    try {
      final password = server.password;
      if (password != null && password.isNotEmpty) {
        await _credentialStore.writePassword(server.id, password);
      } else {
        await _credentialStore.deletePassword(server.id);
      }
    } catch (e) {
      debugPrint('[NasServersNotifier] 保存安全凭据失败: $e');
    }
  }
}

final nasServersProvider =
    StateNotifierProvider<NasServersNotifier, List<NasServerConfig>>((ref) {
  return NasServersNotifier();
});

/// Currently active / connected NAS server with automatic persistence.
final activeNasServerProvider = StateProvider<NasServerConfig?>((ref) {
  final servers = ref.watch(nasServersProvider);
  if (servers.isEmpty) return null;
  return servers.first;
});

/// Currently navigated directory path inside active NAS server.
final currentNasPathProvider = StateProvider<String>((ref) => '/');

/// Current view presentation mode (grid / list / details).
final nasViewModeProvider =
    StateProvider<NasViewMode>((ref) => NasViewMode.details);

/// Fetches directory entries for the active NAS server and current path.
final nasDirectoryContentsProvider =
    FutureProvider.autoDispose<List<NasShareItem>>((ref) async {
  final service = ref.watch(lanNasServiceProvider);
  final server = ref.watch(activeNasServerProvider);
  final path = ref.watch(currentNasPathProvider);

  if (server == null) return <NasShareItem>[];
  return service.listDirectory(server, path);
});

/// Automatically scans and discovers active Samba/NFS/WebDAV devices on the local network.
final discoveredLanServersProvider =
    FutureProvider.autoDispose<List<NasServerConfig>>((ref) async {
  final service = ref.watch(lanNasServiceProvider);
  return service.discoverLanServers();
});
