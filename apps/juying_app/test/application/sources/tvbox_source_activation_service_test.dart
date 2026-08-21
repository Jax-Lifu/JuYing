import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/application/sources/media_source_registry.dart';
import 'package:juying/application/sources/tvbox_source_activation_service.dart';
import 'package:juying/application/sources/tvbox_source_store.dart';
import 'package:juying/domain/models/tvbox_source.dart';
import 'package:juying/domain/models/unified_media.dart';

void main() {
  final definition = TvboxSourceDefinition(
    id: 'tvbox-home',
    name: 'TVBox 直播',
    configUri: Uri.parse('http://config.example/4k.json'),
    rightsConfirmedAt: DateTime.utc(2026, 8, 20),
  );

  test('检测 TVBox 配置结构后持久化并注册统一来源', () async {
    final store = TvboxSourceStore(storage: _MemoryStorage());
    final registry = MediaSourceRegistry([]);
    final service = TvboxSourceActivationService(
      store: store,
      registry: registry,
      client: MockClient((request) async {
        if (request.url == definition.configUri) {
          return http.Response.bytes(
            utf8.encode(
              '{"lives":[{"name":"直播","url":"http://live.example/list.txt","epg":"https://epg.example/xmltv.xml"}]}',
            ),
            200,
          );
        }
        return http.Response.bytes(
            utf8.encode('新闻,#genre#\n官方新闻,http://stream.example/news.m3u8'),
            200);
      }),
    );

    await service.detectAndActivate(definition);
    final activated = registry[definition.id];
    expect(activated, isNotNull);
    expect((await store.load()).single.configUri, definition.configUri);

    final channel = (await activated!.browse(const MediaCatalogQuery(
      category: MediaCategory.live,
    )))
        .items
        .single;
    final episode = (await activated.episodes(channel)).single;
    final playback = await activated.resolvePlayback(episode);
    expect(
      playback.nativeStreamUri,
      Uri.parse('http://stream.example/news.m3u8'),
    );

    final restoredRegistry = MediaSourceRegistry([]);
    final restoredService = TvboxSourceActivationService(
      store: store,
      registry: restoredRegistry,
      client: MockClient((_) async => http.Response('', 500)),
    );
    await restoredService.restorePersisted();
    expect(restoredRegistry[definition.id], isNotNull);
  });
}

class _MemoryStorage implements TvboxSourceStorage {
  String? value;
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String value) async => this.value = value;
}
