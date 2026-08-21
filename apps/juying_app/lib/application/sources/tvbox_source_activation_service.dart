import 'package:http/http.dart' as http;

import '../../domain/models/tvbox_source.dart';
import '../../infrastructure/tvbox/tvbox_config_adapter.dart';
import 'media_source_registry.dart';
import 'tvbox_source_store.dart';

class TvboxSourceActivationService {
  TvboxSourceActivationService(
      {required TvboxSourceStore store,
      required MediaSourceRegistry registry,
      required http.Client client})
      : _store = store,
        _registry = registry,
        _client = client;
  final TvboxSourceStore _store;
  final MediaSourceRegistry _registry;
  final http.Client _client;

  Future<void> restorePersisted() async {
    for (final definition in await _store.load()) {
      _registry.register(_adapterFor(definition));
    }
  }

  Future<void> detectAndActivate(TvboxSourceDefinition definition) async {
    final adapter = _adapterFor(definition);
    await adapter.validate();
    if (_registry[definition.id] != null || !_registry.register(adapter)) {
      throw StateError('来源 ID 已存在或无法注册');
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

  TvboxConfigAdapter _adapterFor(TvboxSourceDefinition definition) =>
      TvboxConfigAdapter(definition: definition, client: _client);
}
