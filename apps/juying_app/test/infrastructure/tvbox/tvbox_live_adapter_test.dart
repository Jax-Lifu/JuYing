import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/domain/models/media_source.dart';
import 'package:juying/domain/models/tvbox_source.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/infrastructure/tvbox/tvbox_live_adapter.dart';

void main() {
  test('JSON 多线路映射为同频道可见的播放器线路选项', () async {
    final definition = TvboxSourceDefinition(
      id: 'tvbox-lines',
      name: '多线路直播',
      configUri: Uri.parse('https://config.example/live.json'),
      rightsConfirmedAt: DateTime.utc(2026, 8, 20),
    );
    final adapter = TvboxLiveAdapter(
      definition: definition,
      client: MockClient((request) async {
        if (request.url == definition.configUri) {
          return http.Response.bytes(
            utf8.encode(
                '{"lives":[{"url":"https://live.example/source.json"}]}'),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(
              '[{"name":"新闻","channel":[{"name":"频道","number":"100","urls":["https://stream.example/primary.m3u8\$主线","https://stream.example/backup.m3u8\$备用"]}]}]'),
          200,
        );
      }),
    );

    final item = (await adapter
            .browse(const MediaCatalogQuery(category: MediaCategory.live)))
        .items
        .single;
    final episode = (await adapter.episodes(item)).single;
    final playback = await adapter.resolvePlayback(episode);

    expect(adapter.source.capabilities,
        contains(SourceCapability.qualitySelection));
    expect(playback.nativeStreamUri,
        Uri.parse('https://stream.example/primary.m3u8'));
    expect(playback.qualityOptions, hasLength(2));
    expect(playback.qualityOptions.first.label, '主线');
    expect(playback.qualityOptions.last.label, '备用');
    expect(playback.qualityOptions.last.streamUri,
        Uri.parse('https://stream.example/backup.m3u8'));
    expect(item.brief, '频道 100');
  });

  test('内嵌分组直播保留播放所需请求头', () async {
    final definition = TvboxSourceDefinition(
      id: 'tvbox-inline-live',
      name: '内嵌直播',
      configUri: Uri.parse('https://config.example/inline.json'),
      rightsConfirmedAt: DateTime.utc(2026, 8, 20),
    );
    final adapter = TvboxLiveAdapter(
      definition: definition,
      client: MockClient((request) async => http.Response.bytes(
            utf8.encode(
              '{"lives":[{"name":"内嵌","groups":[{"name":"新闻","channel":[{"name":"官方频道","urls":["https://stream.example/news.m3u8"],"ua":"JuYing-Test","header":{"Referer":"https://official.example/"}}]}]}]}',
            ),
            200,
          )),
    );

    final item = (await adapter
            .browse(const MediaCatalogQuery(category: MediaCategory.live)))
        .items
        .single;
    final playback =
        await adapter.resolvePlayback((await adapter.episodes(item)).single);

    expect(playback.nativeStreamUri,
        Uri.parse('https://stream.example/news.m3u8'));
    expect(playback.httpHeaders, {
      'User-Agent': 'JuYing-Test',
      'Referer': 'https://official.example/',
    });
  });

  test('公开 XMLTV 节目单映射为来源内频道节目', () async {
    final definition = TvboxSourceDefinition(
      id: 'tvbox-guide',
      name: '节目单直播',
      configUri: Uri.parse('https://config.example/guide.json'),
      rightsConfirmedAt: DateTime.utc(2026, 8, 20),
    );
    final adapter = TvboxLiveAdapter(
      definition: definition,
      client: MockClient((request) async {
        if (request.url == definition.configUri) {
          return http.Response.bytes(
            utf8.encode(
                '{"lives":[{"url":"https://live.example/source.json","epg":"https://epg.example/xmltv.xml"}]}'),
            200,
          );
        }
        if (request.url.host == 'live.example') {
          return http.Response.bytes(
            utf8.encode(
                '[{"name":"新闻","channel":[{"name":"频道","tvgId":"NEWS","urls":["https://stream.example/news.m3u8"]}]}]'),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(
              '<tv><programme channel="NEWS" start="20260820100000 +0800" stop="20260820110000 +0800"><title>新闻直播</title></programme></tv>'),
          200,
        );
      }),
    );

    final item = (await adapter
            .browse(const MediaCatalogQuery(category: MediaCategory.live)))
        .items
        .single;
    final programs = await adapter.programGuide(item);

    expect(adapter.source.capabilities,
        contains(SourceCapability.liveProgramGuide));
    expect(programs.single.title, '新闻直播');
    expect(programs.single.sourceItemId, item.sourceItemId);
  });

  test('压缩 XMLTV 节目单映射为来源内频道节目', () async {
    final definition = TvboxSourceDefinition(
      id: 'tvbox-compressed-guide',
      name: '压缩节目单直播',
      configUri: Uri.parse('https://config.example/compressed-guide.json'),
      rightsConfirmedAt: DateTime.utc(2026, 8, 20),
    );
    final adapter = TvboxLiveAdapter(
      definition: definition,
      client: MockClient((request) async {
        if (request.url == definition.configUri) {
          return http.Response.bytes(
            utf8.encode(
                '{"lives":[{"url":"https://live.example/source.json","epg":"https://epg.example/xmltv.xml.gz"}]}'),
            200,
          );
        }
        if (request.url.host == 'live.example') {
          return http.Response.bytes(
            utf8.encode(
                '[{"name":"新闻","channel":[{"name":"频道","tvgId":"NEWS","urls":["https://stream.example/news.m3u8"]}]}]'),
            200,
          );
        }
        return http.Response.bytes(
          gzip.encode(
            utf8.encode(
                '<tv><programme channel="NEWS" start="20260820100000 +0800" stop="20260820110000 +0800"><title>压缩新闻</title></programme></tv>'),
          ),
          200,
          headers: {'content-encoding': 'gzip'},
        );
      }),
    );

    final item = (await adapter
            .browse(const MediaCatalogQuery(category: MediaCategory.live)))
        .items
        .single;
    final programs = await adapter.programGuide(item);

    expect(programs.single.title, '压缩新闻');
  });

  test('节目单在刷新间隔内按频道复用有效结果', () async {
    final definition = TvboxSourceDefinition(
      id: 'tvbox-guide-cache',
      name: '节目单缓存直播',
      configUri: Uri.parse('https://config.example/guide-cache.json'),
      rightsConfirmedAt: DateTime.utc(2026, 8, 20),
    );
    var epgRequestCount = 0;
    final adapter = TvboxLiveAdapter(
      definition: definition,
      client: MockClient((request) async {
        if (request.url == definition.configUri) {
          return http.Response.bytes(
            utf8.encode(
                '{"lives":[{"url":"https://live.example/source.json","epg":"https://epg.example/xmltv.xml"}]}'),
            200,
          );
        }
        if (request.url.host == 'live.example') {
          return http.Response.bytes(
            utf8.encode(
                '[{"name":"新闻","channel":[{"name":"频道","tvgId":"NEWS","urls":["https://stream.example/news.m3u8"]}]}]'),
            200,
          );
        }
        epgRequestCount += 1;
        return http.Response.bytes(
          utf8.encode(
              '<tv><programme channel="NEWS" start="20260820100000 +0800" stop="20260820110000 +0800"><title>缓存新闻</title></programme></tv>'),
          200,
        );
      }),
    );

    final item = (await adapter
            .browse(const MediaCatalogQuery(category: MediaCategory.live)))
        .items
        .single;
    final first = await adapter.programGuide(item);
    final second = await adapter.programGuide(item);

    expect(first.single.title, '缓存新闻');
    expect(second.single.title, '缓存新闻');
    expect(epgRequestCount, 1);
  });

  test('合并配置内所有直连清单，并按频道读取节目单', () async {
    final definition = TvboxSourceDefinition(
      id: 'tvbox-many-lives',
      name: '多清单直播',
      configUri: Uri.parse('https://config.example/many-lives.json'),
      rightsConfirmedAt: DateTime.utc(2026, 8, 20),
    );
    final adapter = TvboxLiveAdapter(
      definition: definition,
      client: MockClient((request) async {
        switch (request.url.host) {
          case 'config.example':
            return http.Response.bytes(
              utf8.encode(
                  '{"lives":[{"url":"https://one.example/live.json","epg":"https://one-guide.example/guide.xml"},{"url":"https://two.example/live.json","epg":"https://two-guide.example/guide.xml"}]}'),
              200,
            );
          case 'one.example':
            return http.Response.bytes(
              utf8.encode(
                  '[{"name":"新闻","channel":[{"name":"第一频道","tvgId":"ONE","urls":["https://stream.example/one.m3u8"]}]}]'),
              200,
            );
          case 'two.example':
            return http.Response.bytes(
              utf8.encode(
                  '[{"name":"体育","channel":[{"name":"第二频道","tvgId":"TWO","urls":["https://stream.example/two.m3u8"]}]}]'),
              200,
            );
          case 'one-guide.example':
            return http.Response.bytes(
              utf8.encode(
                  '<tv><programme channel="ONE" start="20260820100000 +0800" stop="20260820110000 +0800"><title>第一节目</title></programme></tv>'),
              200,
            );
          default:
            return http.Response.bytes(
              utf8.encode(
                  '<tv><programme channel="TWO" start="20260820100000 +0800" stop="20260820110000 +0800"><title>第二节目</title></programme></tv>'),
              200,
            );
        }
      }),
    );

    final items = (await adapter
            .browse(const MediaCatalogQuery(category: MediaCategory.live)))
        .items;
    final first = items.singleWhere((item) => item.title == '第一频道');
    final second = items.singleWhere((item) => item.title == '第二频道');

    expect(items, hasLength(2));
    expect((await adapter.programGuide(first)).single.title, '第一节目');
    expect((await adapter.programGuide(second)).single.title, '第二节目');
  });
}
