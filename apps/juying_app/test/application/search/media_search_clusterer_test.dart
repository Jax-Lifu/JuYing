import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/search/media_search_clusterer.dart';
import 'package:juying/domain/models/media_identity.dart';
import 'package:juying/domain/models/unified_media.dart';

void main() {
  test('可信作品身份聚类展示，但保留来源版本和播放身份', () {
    final clusters = MediaSearchClusterer.cluster([
      _hit('first', 'cut-a', workId: 'authority:work-100'),
      _hit('second', 'cut-b', workId: 'authority:work-100'),
    ]);

    expect(clusters, hasLength(1));
    expect(clusters.single.hasMultipleSources, isTrue);
    expect(
      clusters.single.versions.map((hit) => hit.item.id),
      ['first:cut-a', 'second:cut-b'],
    );
  });

  test('同名、重排集或特别篇没有可信身份时绝不自动合并', () {
    final clusters = MediaSearchClusterer.cluster([
      _hit('first', 'series-original'),
      _hit('second', 'series-remaster'),
      _hit('second', 'series-special'),
    ]);

    expect(clusters, hasLength(3));
    expect(clusters.every((cluster) => !cluster.hasMultipleSources), isTrue);
  });
}

MediaSearchHit _hit(String sourceId, String itemId, {String? workId}) {
  final item = MediaItem(
    sourceId: sourceId,
    sourceItemId: itemId,
    title: '同名节目',
    category: MediaCategory.animation,
    officialDetailUri: Uri.parse('https://$sourceId.example.com/$itemId'),
    defaultEpisodePageUri:
        Uri.parse('https://$sourceId.example.com/$itemId/episode'),
    workIdentity: workId == null
        ? null
        : MediaWorkIdentity(
            id: workId,
            evidence: MediaWorkIdentityEvidence.verifiedExternalId,
          ),
  );
  return MediaSearchHit(item: item, query: '同名节目', matchedField: 'title');
}
