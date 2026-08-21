import 'package:http/http.dart' as http;

import '../../domain/models/playlist_source.dart';
import '../../domain/models/unified_media.dart';
import '../../infrastructure/playlist/m3u_playlist_adapter.dart';
import 'media_source_registry.dart';
import 'playlist_source_store.dart';

/// 将用户确认的清单先检测、再持久化、最后注册为统一来源。
/// 任何一个检测步骤失败都不会留下可用来源或持久化定义。
class PlaylistSourceActivationService {
  PlaylistSourceActivationService({
    required PlaylistSourceStore store,
    required MediaSourceRegistry registry,
    required http.Client client,
  })  : _store = store,
        _registry = registry,
        _client = client;

  final PlaylistSourceStore _store;
  final MediaSourceRegistry _registry;
  final http.Client _client;

  Future<void> restorePersisted() async {
    for (final definition in await _store.load()) {
      _registry.register(_adapterFor(definition));
    }
  }

  Future<void> detectAndActivate(PlaylistSourceDefinition definition) async {
    final adapter = _adapterFor(definition);
    await adapter.browse(const MediaCatalogQuery(
      category: MediaCategory.live,
      pageSize: 1,
    ));
    if (_registry[definition.id] != null) {
      throw StateError('来源 ID 已存在');
    }
    if (!_registry.register(adapter)) {
      throw StateError('来源无法注册');
    }
    try {
      await _store.upsert(definition);
    } catch (_) {
      _registry.unregister(definition.id);
      rethrow;
    }
  }

  Future<void> remove(String sourceId) async {
    await _store.remove(sourceId);
    _registry.unregister(sourceId);
  }

  M3uPlaylistAdapter _adapterFor(PlaylistSourceDefinition definition) =>
      M3uPlaylistAdapter(definition: definition, client: _client);
}
