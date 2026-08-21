import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/policy/source_policy.dart';
import 'package:juying/application/search/media_search_clusterer.dart';
import 'package:juying/application/sources/media_source_registry.dart';
import 'package:juying/application/sources/validated_media_source_adapter.dart';
import 'package:juying/domain/models/media_identity.dart';
import 'package:juying/domain/models/media_source.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/domain/ports/media_source_adapter.dart';

void main() {
  test('同名作品保留两个来源版本，身份通过来源命名空间隔离', () async {
    final first = _FixtureAdapter(
      source: _source('first'),
      catalogItems: [_item('first', 'same-title')],
    );
    final second = _FixtureAdapter(
      source: _source('second'),
      catalogItems: [_item('second', 'same-title')],
    );
    final registry = MediaSourceRegistry([first, second]);

    final firstPage = await registry['first']!.browse(_query);
    final secondPage = await registry['second']!.browse(_query);

    expect(firstPage.items.single.title, secondPage.items.single.title);
    expect(firstPage.items.single.id, 'first:same-title');
    expect(secondPage.items.single.id, 'second:same-title');
  });

  test('跨来源输出会在注册表边界被拒绝', () {
    final broken = _FixtureAdapter(
      source: _source('first'),
      catalogItems: [_item('second', 'wrong-source')],
    );
    final registry = MediaSourceRegistry([broken]);

    expect(
      registry['first']!.browse(_query),
      throwsA(isA<MediaSourceContractViolation>()),
    );
  });

  test('重复来源 ID 不会静默覆盖已有适配器', () {
    expect(
      () => MediaSourceRegistry([
        _FixtureAdapter(source: _source('same')),
        _FixtureAdapter(source: _source('same')),
      ]),
      throwsArgumentError,
    );
  });

  test('来源暂停、熔断与恢复会更新所有策略入口看到的快照', () {
    final registry = MediaSourceRegistry([
      _FixtureAdapter(source: _source('managed')),
    ]);

    expect(
      registry.updateState('managed', lifecycle: SourceLifecycle.paused),
      isTrue,
    );
    expect(registry.adapters, isEmpty);
    expect(
      SourcePolicy.evaluate(
        registry['managed']!.source,
        SourceAction.browse,
        explicitSourceSelection: true,
      ).allowed,
      isFalse,
    );

    registry.updateState(
      'managed',
      lifecycle: SourceLifecycle.active,
      health: SourceHealth.unavailable,
    );
    expect(registry.adapters, hasLength(1));
    expect(
      SourcePolicy.evaluate(
        registry['managed']!.source,
        SourceAction.browse,
        explicitSourceSelection: true,
      ).reason,
      '来源当前不可用',
    );
  });

  test('注册表边界拒绝暂停来源的直接调用，不能绕过生命周期策略', () async {
    final registry = MediaSourceRegistry([
      _FixtureAdapter(
        source: _source('paused'),
        catalogItems: [_item('paused', 'item-1')],
      ),
    ]);
    registry.updateState('paused', lifecycle: SourceLifecycle.paused);

    await expectLater(
      registry['paused']!.browse(_query),
      throwsA(isA<StateError>()),
    );
  });

  test('未声明原生播放能力的来源不能生成原生播放描述', () async {
    final adapter = ValidatedMediaSourceAdapter(
      _FixtureAdapter(source: _source('official-only')),
    );
    final episode = MediaEpisode(
      sourceId: 'official-only',
      sourceEpisodeId: 'episode-1',
      title: '第 1 集',
      officialPageUri: Uri(scheme: 'https', host: 'official-only.example.com'),
    );

    await expectLater(
      adapter.resolvePlayback(episode),
      throwsA(isA<MediaSourceContractViolation>()),
    );
  });

  test('离线双来源夹具保留重排集、特别篇与来源级播放能力', () async {
    final firstItem = _item(
      'first',
      'work-a',
      workId: 'authority:work-a',
    );
    final secondItem = _item(
      'second',
      'work-a-remaster',
      workId: 'authority:work-a',
    );
    final first = _FixtureAdapter(
      source: _source(
        'first',
        capabilities: const {
          SourceCapability.browse,
          SourceCapability.episodes,
          SourceCapability.officialFallback,
        },
      ),
      catalogItems: [firstItem],
      episodeItems: [_episode('first', 'e1', 1), _episode('first', 'e2', 2)],
    );
    final second = _FixtureAdapter(
      source: _source(
        'second',
        capabilities: const {
          SourceCapability.browse,
          SourceCapability.episodes,
        },
      ),
      catalogItems: [secondItem],
      episodeItems: [
        _episode('second', 'e2', 2),
        _episode('second', 'special', null, isSpecial: true),
        _episode('second', 'e1', 1),
      ],
    );
    final registry = MediaSourceRegistry([first, second]);

    final clusters = MediaSearchClusterer.cluster([
      MediaSearchHit(item: firstItem, query: '同名作品', matchedField: 'title'),
      MediaSearchHit(
        item: secondItem,
        query: '同名作品',
        matchedField: 'title',
      ),
    ]);
    expect(clusters, hasLength(1));
    expect(clusters.single.versions.map((hit) => hit.item.id), [
      'first:work-a',
      'second:work-a-remaster',
    ]);

    expect(
      (await registry['first']!.episodes(firstItem))
          .map((episode) => episode.id),
      ['first:e1', 'first:e2'],
    );
    final secondEpisodes = await registry['second']!.episodes(secondItem);
    expect(secondEpisodes.map((episode) => episode.id), [
      'second:e2',
      'second:special',
      'second:e1',
    ]);
    expect(secondEpisodes[1].isSpecial, isTrue);

    final playable = await registry['first']!.resolveOfficialFallback(
      (await registry['first']!.episodes(firstItem)).first,
    );
    expect(playable.sourceId, 'first');
    await expectLater(
      registry['second']!.resolveOfficialFallback(secondEpisodes.first),
      throwsA(isA<StateError>()),
    );
  });

  test('连续来源故障先降级，达到阈值后自动熔断', () async {
    final registry = MediaSourceRegistry([
      _FixtureAdapter(
        source: _source('flaky'),
        error: StateError('网络失败'),
      ),
    ]);
    final adapter = registry['flaky']!;

    await expectLater(adapter.browse(_query), throwsA(isA<StateError>()));
    expect(adapter.source.health, SourceHealth.degraded);
    await expectLater(adapter.browse(_query), throwsA(isA<StateError>()));
    await expectLater(adapter.browse(_query), throwsA(isA<StateError>()));

    expect(adapter.source.health, SourceHealth.unavailable);
    expect(adapter.source.lifecycle, SourceLifecycle.circuitOpen);
    expect(registry.adapters, isEmpty);

    registry.updateState(
      'flaky',
      health: SourceHealth.healthy,
      lifecycle: SourceLifecycle.active,
    );
    expect(adapter.source.isActive, isTrue);
    expect(adapter.source.health, SourceHealth.healthy);
  });

  test('来源状态变更会通知界面，并支持用户手动恢复熔断来源', () {
    final registry = MediaSourceRegistry([
      _FixtureAdapter(source: _source('recoverable')),
    ]);
    var notifications = 0;
    registry.addListener(() => notifications += 1);

    registry.updateState(
      'recoverable',
      health: SourceHealth.unavailable,
      lifecycle: SourceLifecycle.circuitOpen,
    );
    expect(notifications, 1);
    expect(registry.adapters, isEmpty);

    expect(registry.restoreSource('recoverable'), isTrue);
    expect(notifications, 2);
    expect(registry.adapters, hasLength(1));
  });
}

const _query = MediaCatalogQuery(category: MediaCategory.animation);

MediaSource _source(
  String id, {
  Set<SourceCapability> capabilities = const {SourceCapability.browse},
}) =>
    MediaSource(
      id: id,
      name: id,
      kind: MediaSourceKind.authorizedApi,
      entryUrl: 'https://$id.example.com',
      enabled: true,
      authorization: SourceAuthorization.licensed,
      capabilities: capabilities,
    );

MediaItem _item(
  String sourceId,
  String sourceItemId, {
  String? workId,
}) =>
    MediaItem(
      sourceId: sourceId,
      sourceItemId: sourceItemId,
      title: '同名作品',
      category: MediaCategory.animation,
      officialDetailUri: Uri.parse('https://$sourceId.example.com/detail'),
      defaultEpisodePageUri: Uri.parse('https://$sourceId.example.com/episode'),
      workIdentity: workId == null
          ? null
          : MediaWorkIdentity(
              id: workId,
              evidence: MediaWorkIdentityEvidence.verifiedExternalId,
            ),
    );

MediaEpisode _episode(
  String sourceId,
  String episodeId,
  int? episodeNumber, {
  bool isSpecial = false,
}) =>
    MediaEpisode(
      sourceId: sourceId,
      sourceEpisodeId: episodeId,
      title: isSpecial ? '特别篇' : '第 $episodeNumber 集',
      officialPageUri: Uri.parse('https://$sourceId.example.com/$episodeId'),
      episodeNumber: episodeNumber,
      isSpecial: isSpecial,
    );

class _FixtureAdapter implements MediaSourceAdapter {
  _FixtureAdapter({
    required this.source,
    this.catalogItems = const [],
    this.episodeItems = const [],
    this.error,
  });

  @override
  final MediaSource source;
  final List<MediaItem> catalogItems;
  final List<MediaEpisode> episodeItems;
  final Object? error;

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) {
    if (error != null) return Future.error(error!);
    return Future.value(
      MediaCatalogPage(
          items: catalogItems, page: query.page, total: catalogItems.length),
    );
  }

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) =>
      Future.value(episodeItems);

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(MediaEpisode episode) =>
      Future.value(
        PlaybackDescriptor(
          sourceId: episode.sourceId,
          sourceEpisodeId: episode.sourceEpisodeId,
          title: episode.title,
          officialPageUri: episode.officialPageUri,
        ),
      );

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) =>
      throw UnimplementedError();

  @override
  Future<List<MediaSearchHit>> search(String query) => Future.value(const []);
}
