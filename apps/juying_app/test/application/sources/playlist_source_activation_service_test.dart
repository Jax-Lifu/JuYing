import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/application/sources/media_source_registry.dart';
import 'package:juying/application/sources/playlist_source_activation_service.dart';
import 'package:juying/application/sources/playlist_source_store.dart';
import 'package:juying/domain/models/playlist_source.dart';

void main() {
  final definition = PlaylistSourceDefinition(
    id: 'playlist-family',
    name: '家庭直播',
    playlistUri: Uri.parse('https://playlist.example/family.m3u'),
    rightsConfirmedAt: DateTime.utc(2026, 8, 20),
  );

  test('检测到合规 HTTPS M3U 后自动持久化并注册统一来源', () async {
    final store = PlaylistSourceStore(storage: _MemoryStorage());
    final registry = MediaSourceRegistry([]);
    final service = PlaylistSourceActivationService(
      store: store,
      registry: registry,
      client: MockClient((_) async => http.Response.bytes(utf8.encode('''
#EXTM3U
#EXTINF:-1 group-title="新闻",官方新闻
https://stream.example/live/news.m3u8
'''), 200)),
    );

    await service.detectAndActivate(definition);

    expect(registry[definition.id], isNotNull);
    expect((await store.load()).single.id, definition.id);
  });

  test('不符合 M3U 规则时既不持久化也不注册', () async {
    final store = PlaylistSourceStore(storage: _MemoryStorage());
    final registry = MediaSourceRegistry([]);
    final service = PlaylistSourceActivationService(
      store: store,
      registry: registry,
      client: MockClient(
          (_) async => http.Response('<html>not playlist</html>', 200)),
    );

    await expectLater(
      service.detectAndActivate(definition),
      throwsA(isA<FormatException>()),
    );

    expect(registry[definition.id], isNull);
    expect(await store.load(), isEmpty);
  });

  test('已保存来源会在启动时自动恢复，移除会同时注销', () async {
    final storage = _MemoryStorage();
    final store = PlaylistSourceStore(storage: storage);
    await store.upsert(definition);
    final registry = MediaSourceRegistry([]);
    final service = PlaylistSourceActivationService(
      store: store,
      registry: registry,
      client: MockClient((_) async => http.Response('#EXTM3U', 200)),
    );

    await service.restorePersisted();
    expect(registry[definition.id], isNotNull);

    await service.remove(definition.id);
    expect(registry[definition.id], isNull);
    expect(await store.load(), isEmpty);
  });
}

class _MemoryStorage implements PlaylistSourceStorage {
  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async => this.value = value;
}
