import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/policy/media_access_policy.dart';
import 'package:juying/application/search/federated_search_service.dart';
import 'package:juying/domain/models/media_source.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/domain/ports/media_source_adapter.dart';

void main() {
  final item = MediaItem(
    sourceId: 'licensed',
    sourceItemId: 'one',
    title: '小小世界',
    category: MediaCategory.animation,
    officialDetailUri: Uri.parse('https://example.com/detail'),
    defaultEpisodePageUri: Uri.parse('https://example.com/episode'),
  );

  test('保留成功来源结果并隔离单个来源失败', () async {
    final service = FederatedSearchService();
    final result = await service.search(
      query: '小小世界',
      adapters: [
        _FakeAdapter(source: _licensedSource('licensed'), hits: [
          MediaSearchHit(item: item, query: '小小世界', matchedField: 'title'),
        ]),
        _FakeAdapter(
            source: _licensedSource('broken'), error: StateError('离线')),
      ],
    );

    expect(result.hits, hasLength(1));
    expect(result.succeededSourceCount, 1);
    expect(result.failedSourceCount, 1);
    expect(
      result.outcomes.map((outcome) => outcome.status),
      containsAll([SourceSearchStatus.succeeded, SourceSearchStatus.failed]),
    );
  });

  test('超时来源不阻塞其他来源', () async {
    final service =
        FederatedSearchService(timeout: const Duration(milliseconds: 5));
    final result = await service.search(
      query: '动画',
      adapters: [
        _FakeAdapter(source: _licensedSource('slow'), neverCompletes: true),
        _FakeAdapter(source: _licensedSource('fast')),
      ],
    );

    expect(result.succeededSourceCount, 1);
    expect(result.failedSourceCount, 1);
    expect(
      result.outcomes
          .singleWhere((outcome) => outcome.sourceId == 'slow')
          .status,
      SourceSearchStatus.timedOut,
    );
  });

  test('官方入口来源只有明确选中时才进入搜索', () async {
    final adapter = _FakeAdapter(
      source: const MediaSource(
        id: 'official',
        name: '官网',
        kind: MediaSourceKind.officialWeb,
        entryUrl: 'https://example.com',
        enabled: true,
        authorization: SourceAuthorization.officialEntryOnly,
        capabilities: {SourceCapability.search},
      ),
    );
    final service = FederatedSearchService();

    final allSources = await service.search(query: '动画', adapters: [adapter]);
    final selected = await service.search(
      query: '动画',
      adapters: [adapter],
      sourceId: 'official',
    );

    expect(allSources.skippedSourceCount, 1);
    expect(adapter.searchCalls, 1);
    expect(selected.succeededSourceCount, 1);
  });

  test('儿童档案在联邦搜索服务内过滤不安全结果', () async {
    final movie = MediaItem(
      sourceId: 'licensed',
      sourceItemId: 'movie-1',
      title: '不适合儿童的影片',
      category: MediaCategory.movie,
      officialDetailUri: Uri.parse('https://example.com/detail'),
      defaultEpisodePageUri: Uri.parse('https://example.com/episode'),
    );
    final result = await const FederatedSearchService().search(
      query: '影片',
      adapters: [
        _FakeAdapter(
          source: _licensedSource('licensed'),
          hits: [
            MediaSearchHit(item: movie, query: '影片', matchedField: 'title'),
          ],
        ),
      ],
      policyContext: const MediaAccessContext(isChildProfile: true),
    );

    expect(result.hits, isEmpty);
    expect(result.succeededSourceCount, 1);
    expect(result.outcomes.single.status, SourceSearchStatus.empty);
  });

  test('相同精确度和可播放性时优先显示优先级更高的来源', () async {
    final lowItem = MediaItem(
      sourceId: 'low-priority',
      sourceItemId: 'one',
      title: '同名节目',
      category: MediaCategory.animation,
      officialDetailUri: Uri.parse('https://example.com/low'),
      defaultEpisodePageUri: Uri.parse('https://example.com/low/episode'),
    );
    final highItem = MediaItem(
      sourceId: 'high-priority',
      sourceItemId: 'one',
      title: '同名节目',
      category: MediaCategory.animation,
      officialDetailUri: Uri.parse('https://example.com/high'),
      defaultEpisodePageUri: Uri.parse('https://example.com/high/episode'),
    );
    final result = await const FederatedSearchService().search(
      query: '同名节目',
      adapters: [
        _FakeAdapter(
          source: _licensedSource('low-priority', priority: 1),
          hits: [
            MediaSearchHit(item: lowItem, query: '同名节目', matchedField: 'title'),
          ],
        ),
        _FakeAdapter(
          source: _licensedSource('high-priority', priority: 10),
          hits: [
            MediaSearchHit(
                item: highItem, query: '同名节目', matchedField: 'title'),
          ],
        ),
      ],
    );

    expect(result.hits.map((hit) => hit.item.sourceId), [
      'high-priority',
      'low-priority',
    ]);
  });
}

MediaSource _licensedSource(String id, {int priority = 0}) => MediaSource(
      id: id,
      name: id,
      kind: MediaSourceKind.authorizedApi,
      entryUrl: 'https://example.com',
      enabled: true,
      authorization: SourceAuthorization.licensed,
      capabilities: const {SourceCapability.search},
      priority: priority,
    );

class _FakeAdapter implements MediaSourceAdapter {
  _FakeAdapter({
    required this.source,
    this.hits = const [],
    this.error,
    this.neverCompletes = false,
  });

  @override
  final MediaSource source;
  final List<MediaSearchHit> hits;
  final Object? error;
  final bool neverCompletes;
  var searchCalls = 0;

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) =>
      throw UnimplementedError();

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) =>
      throw UnimplementedError();

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) =>
      throw UnimplementedError();

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(MediaEpisode episode) =>
      throw UnimplementedError();

  @override
  Future<List<MediaSearchHit>> search(String query) {
    searchCalls += 1;
    if (neverCompletes) return Completer<List<MediaSearchHit>>().future;
    if (error != null) return Future.error(error!);
    return Future.value(hits);
  }
}
