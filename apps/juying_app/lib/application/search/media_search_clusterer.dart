import '../../domain/models/media_identity.dart';
import '../../domain/models/unified_media.dart';

/// 一部聚合展示作品及其保留的来源版本。点击任一版本都不会悄悄换源。
class MediaSearchCluster {
  const MediaSearchCluster({
    required this.id,
    required this.title,
    required this.versions,
    this.identity,
  });

  final String id;
  final String title;
  final List<MediaSearchHit> versions;
  final MediaWorkIdentity? identity;

  bool get hasMultipleSources =>
      versions.map((hit) => hit.item.sourceId).toSet().length > 1;

  bool get hasMultipleVersions => versions.length > 1;
}

/// 仅对已声明可信跨来源身份的结果聚类；未知身份的同名结果保持独立。
abstract final class MediaSearchClusterer {
  static List<MediaSearchCluster> cluster(Iterable<MediaSearchHit> hits) {
    final groups = <String, List<MediaSearchHit>>{};
    final identities = <String, MediaWorkIdentity?>{};
    for (final hit in hits) {
      final identity = hit.item.workIdentity;
      final key = identity == null
          ? 'source-version:${hit.item.id}'
          : 'work:${identity.id}';
      groups.putIfAbsent(key, () => []).add(hit);
      identities[key] = identity;
    }
    return groups.entries
        .map(
          (entry) => MediaSearchCluster(
            id: entry.key,
            title: entry.value.first.item.title,
            versions: List.unmodifiable(entry.value),
            identity: identities[entry.key],
          ),
        )
        .toList(growable: false);
  }
}
