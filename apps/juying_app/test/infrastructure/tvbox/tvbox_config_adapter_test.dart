import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/application/sources/media_source_registry.dart';
import 'package:juying/domain/models/tvbox_source.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/domain/ports/catalog_initial_category.dart';
import 'package:juying/domain/ports/source_catalog_scopes.dart';
import 'package:juying/infrastructure/tvbox/tvbox_config_adapter.dart';

void main() {
  final definition = TvboxSourceDefinition(
    id: 'tvbox-composite',
    name: '组合来源',
    configUri: Uri.parse('https://config.example/source.json'),
    rightsConfirmedAt: DateTime.utc(2026, 8, 20),
  );

  test('sites 与 lives 在同一来源命名空间内独立提供目录和播放', () async {
    final adapter = TvboxConfigAdapter(
      definition: definition,
      client: MockClient((request) async {
        if (request.url == definition.configUri) {
          return http.Response.bytes(
            utf8.encode('''
{
  "lives": [{"url":"https://live.example/list.m3u"}],
  "sites": [
    {"key":"json","type":1,"api":"https://api.example/vod"},
    {"key":"offline","type":1,"api":"https://offline.example/vod"}
  ]
}
'''),
            200,
          );
        }
        if (request.url.host == 'live.example') {
          return http.Response.bytes(
            utf8.encode(
                '#EXTM3U\n#EXTINF:-1,新闻\nhttps://stream.example/news.m3u8'),
            200,
          );
        }
        if (request.url.host == 'offline.example') {
          return http.Response('', 503);
        }
        final detail = request.url.queryParameters['ids'] == '11';
        return http.Response.bytes(
          utf8.encode(detail
              ? '{"list":[{"vod_id":"11","vod_name":"电影","vod_play_url":"正片\$https://stream.example/movie.m3u8"}]}'
              : '{"list":[{"vod_id":"11","vod_name":"电影","type_name":"电影"}]}'),
          200,
        );
      }),
    );
    await adapter.validate();
    final registry = MediaSourceRegistry([adapter]);
    final managed = registry[definition.id]!;
    final live = (await managed
            .browse(const MediaCatalogQuery(category: MediaCategory.live)))
        .items
        .single;
    final movie = (await managed
            .browse(const MediaCatalogQuery(category: MediaCategory.movie)))
        .items
        .single;
    final episode = (await managed.episodes(movie)).single;
    final playback = await managed.resolvePlayback(episode);

    expect(live.sourceId, definition.id);
    expect(movie.sourceId, definition.id);
    expect(movie.sourceItemId, 'json::11');
    expect(playback.nativeStreamUri,
        Uri.parse('https://stream.example/movie.m3u8'));
  });

  test('直播入口暂时不可用不会阻止保存结构有效的 TVBox 配置', () async {
    final adapter = TvboxConfigAdapter(
      definition: definition,
      client: MockClient((request) async {
        if (request.url == definition.configUri) {
          return http.Response.bytes(
            utf8.encode('''
{
  "lives": [{"url":"https://live.example/unavailable.txt"}],
  "sites": [{"key":"json","type":1,"api":"https://api.example/vod"}]
}
'''),
            200,
          );
        }
        if (request.url.host == 'live.example') return http.Response('', 404);
        return http.Response.bytes(
          utf8.encode(
              '{"list":[{"vod_id":"11","vod_name":"电影","type_name":"动作片"}]}'),
          200,
        );
      }),
    );

    await adapter.validate();

    expect((adapter as CatalogInitialCategory).initialCatalogCategory,
        MediaCategory.movie);
    expect(
      (await adapter.browse(const MediaCatalogQuery(
        category: MediaCategory.movie,
      )))
          .items
          .single
          .title,
      '电影',
    );
  });

  test('sites key 通过通用目录范围暴露并可明确选择站点', () async {
    final adapter = TvboxConfigAdapter(
      definition: definition,
      client: MockClient((request) async {
        if (request.url == definition.configUri) {
          return http.Response.bytes(
            utf8.encode('''
{"sites":[
  {"key":"alpha","name":"一号站","type":1,"api":"https://alpha.example/vod"},
  {"key":"beta","name":"二号站","type":1,"api":"https://beta.example/vod"},
  {"key":"offline","name":"失效站","type":1,"api":"https://offline.example/vod"}
]}
'''),
            200,
          );
        }
        if (request.url.host == 'offline.example') {
          return http.Response('', 503);
        }
        final key = request.url.host.startsWith('beta') ? 'beta' : 'alpha';
        return http.Response.bytes(
          utf8.encode(
            '{"list":[{"vod_id":"1","vod_name":"$key 节目","type_name":"电影","vod_play_url":"正片\$https://stream.example/$key.m3u8"}]}',
          ),
          200,
        );
      }),
    );

    final managed = MediaSourceRegistry([adapter])[definition.id]!;
    expect(managed, isA<SourceCatalogScopes>());
    final scopeProvider = managed as SourceCatalogScopes;
    final scopes = await scopeProvider.catalogScopes();
    expect(
        scopes.map((scope) => scope.sourceKey), ['alpha', 'beta', 'offline']);
    expect(scopes.map((scope) => scope.label), ['一号站', '二号站', '失效站']);
    expect(
      await scopeProvider.availableCatalogScopeIds(
        category: MediaCategory.movie,
      ),
      {'alpha', 'beta'},
    );

    await scopeProvider.selectCatalogScope('beta');
    final page = await managed.browse(
      const MediaCatalogQuery(category: MediaCategory.movie),
    );

    expect(page.items.single.title, 'beta 节目');
    expect(scopeProvider.selectedCatalogScopeId, 'beta');
  });

  test('多仓有限加载可访问子配置并保持同一来源命名空间', () async {
    final warehouseDefinition = TvboxSourceDefinition(
      id: 'tvbox-warehouse',
      name: '多仓',
      configUri: Uri.parse('https://warehouse.example/DC.txt'),
      rightsConfirmedAt: DateTime.utc(2026, 8, 20),
    );
    final adapter = TvboxConfigAdapter(
      definition: warehouseDefinition,
      client: MockClient((request) async {
        if (request.url == warehouseDefinition.configUri) {
          return http.Response.bytes(
            utf8.encode('''
{"urls":[
  {"name":"一号仓","url":"https://one.example/config.json"},
  {"name":"二号仓","url":"https://two.example/config.json"}
]}
'''),
            200,
          );
        }
        if (request.url.path.endsWith('config.json')) {
          final apiHost = request.url.host == 'one.example'
              ? 'one-api.example'
              : 'two-api.example';
          return http.Response.bytes(
            utf8.encode(
              '{"sites":[{"key":"json","type":1,"api":"https://$apiHost/vod"}]}',
            ),
            200,
          );
        }
        final id = request.url.host == 'one-api.example' ? '1' : '2';
        return http.Response.bytes(
          utf8.encode(
            '{"total":1,"list":[{"vod_id":"$id","vod_name":"节目$id","type_name":"电影"}]}',
          ),
          200,
        );
      }),
    );

    await adapter.validate();
    final scopes = await adapter.catalogScopes();
    final page = await adapter.browse(
      const MediaCatalogQuery(category: MediaCategory.movie),
    );

    expect(scopes, hasLength(2));
    expect(scopes.map((scope) => scope.label),
        containsAll(['一号仓 · json', '二号仓 · json']));
    expect(page.items.single.title, anyOf('节目1', '节目2'));
    expect(page.items.map((item) => item.sourceId).toSet(),
        {warehouseDefinition.id});
    expect(page.items.map((item) => item.sourceItemId).toSet(), hasLength(1));
    expect((adapter as CatalogInitialCategory).initialCatalogCategory,
        MediaCategory.movie);
  });
}
