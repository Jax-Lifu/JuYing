import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/application/sources/media_source_registry.dart';
import 'package:juying/domain/models/media_source.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/infrastructure/cctv/cctv_official_adapter.dart';
import 'package:juying/infrastructure/cctv/cctv_repository.dart';
import 'package:juying/domain/ports/source_catalog_tabs.dart';

void main() {
  test('maps a CCTV catalog result to the unified media boundary', () async {
    final repository = CctvRepository(
      client: MockClient((request) async {
        expect(request.url.host, 'api.cntv.cn');
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'data': {
              'total': 1,
              'list': [
                {
                  'id': 'album-1',
                  'title': '测试动画',
                  'url': 'https://tv.cctv.com/album.shtml',
                  'image2': 'https://p1.img.cctvpic.com/poster.jpg',
                  'video': {
                    'url': 'https://tv.cctv.com/episode.shtml',
                  },
                },
              ],
            },
          })),
          200,
        );
      }),
    );
    final adapter = CctvOfficialAdapter(repository: repository);

    final page = await adapter.browse(
      const MediaCatalogQuery(category: MediaCategory.animation),
    );

    expect(page.total, 1);
    expect(page.items.single.id, 'cctv-official:album-1');
    expect(page.items.single.category, MediaCategory.animation);
    expect(page.items.single.sourceCategoryLabel, '动画片');
  });

  test('rejects unified items that belong to another source', () async {
    final adapter = CctvOfficialAdapter(
      repository: CctvRepository(
          client: MockClient((_) async => throw UnimplementedError())),
    );
    final item = MediaItem(
      sourceId: 'other-source',
      sourceItemId: 'item-1',
      title: '其他来源',
      category: MediaCategory.animation,
      officialDetailUri: Uri.parse('https://example.com/detail'),
      defaultEpisodePageUri: Uri.parse('https://example.com/episode'),
    );

    expect(adapter.episodes(item), throwsArgumentError);
  });

  test('CCTV 只声明四个主分类，并把官方 sc 字段作为子分类查询', () async {
    Uri? requested;
    final adapter = CctvOfficialAdapter(
      repository: CctvRepository(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'data': {
                'total': 1,
                'list': [
                  {
                    'id': 'album-2',
                    'title': '测试子类',
                    'url': 'https://tv.cctv.com/album.shtml',
                    'video': {'url': 'https://tv.cctv.com/episode.shtml'},
                    'sc': '冒险',
                  },
                ],
              },
            })),
            200,
          );
        }),
      ),
    );

    final page = await adapter.browse(const MediaCatalogQuery(
      category: MediaCategory.animation,
      sourceSubcategoryId: 'cctv-sc:冒险',
    ));
    final tabs = (adapter as SourceCatalogTabs)
        .subTabsFor(MediaCategory.animation, page.items);

    expect((adapter as SourceCatalogTabs).primaryTabs.map((tab) => tab.label),
        ['电视剧', '动画片', '纪录片', '特别节目']);
    expect(requested?.queryParameters['sc'], '冒险');
    expect(tabs.single.id, 'cctv-sc:冒险');
  });

  test('CCTV 官方入口不声明原生播放时不能被通用边界绕过', () async {
    final adapter = CctvOfficialAdapter(
      repository: CctvRepository(
        client: MockClient((_) async => throw UnimplementedError()),
      ),
    );
    final episode = MediaEpisode(
      sourceId: CctvOfficialAdapter.sourceId,
      sourceEpisodeId: 'episode-1',
      title: '第 1 集',
      officialPageUri: Uri(scheme: 'https', host: 'tv.cctv.com'),
    );

    expect(
      adapter.source.capabilities,
      isNot(contains(SourceCapability.nativePublicPlayback)),
    );
    expect(
      adapter.source.capabilities,
      containsAll({
        SourceCapability.qualitySelection,
        SourceCapability.playbackSpeed,
        SourceCapability.volumeControl,
        SourceCapability.fullscreen,
        SourceCapability.continueWatching,
      }),
    );
    final registry = MediaSourceRegistry([adapter]);
    await expectLater(
      registry[CctvOfficialAdapter.sourceId]!.resolvePlayback(episode),
      throwsA(isA<StateError>()),
    );
  });
}
