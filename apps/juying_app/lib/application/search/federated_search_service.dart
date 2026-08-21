import 'dart:async';

import '../../domain/models/unified_media.dart';
import '../../domain/ports/media_source_adapter.dart';
import '../policy/media_access_policy.dart';
import '../policy/source_policy.dart';
import 'media_search_clusterer.dart';

/// 单个来源在一次联邦搜索中的可解释状态。
enum SourceSearchStatus { succeeded, empty, failed, timedOut, skipped }

class SourceSearchOutcome {
  const SourceSearchOutcome({
    required this.sourceId,
    required this.sourceName,
    required this.status,
    this.resultCount = 0,
  });

  final String sourceId;
  final String sourceName;
  final SourceSearchStatus status;
  final int resultCount;
}

class FederatedSearchResult {
  const FederatedSearchResult({
    required this.query,
    required this.hits,
    required this.outcomes,
  });

  final String query;
  final List<MediaSearchHit> hits;
  final List<SourceSearchOutcome> outcomes;

  List<MediaSearchCluster> get clusters => MediaSearchClusterer.cluster(hits);

  int get succeededSourceCount => outcomes
      .where((outcome) =>
          outcome.status == SourceSearchStatus.succeeded ||
          outcome.status == SourceSearchStatus.empty)
      .length;

  int get failedSourceCount => outcomes
      .where((outcome) =>
          outcome.status == SourceSearchStatus.failed ||
          outcome.status == SourceSearchStatus.timedOut)
      .length;

  int get skippedSourceCount => outcomes
      .where((outcome) => outcome.status == SourceSearchStatus.skipped)
      .length;
}

/// 对已注册来源并发扇出搜索；任何单源故障均不能让其他来源结果丢失。
class FederatedSearchService {
  const FederatedSearchService({
    this.timeout = const Duration(seconds: 12),
  });

  final Duration timeout;

  Future<FederatedSearchResult> search({
    required String query,
    required Iterable<MediaSourceAdapter> adapters,
    String? sourceId,
    MediaAccessContext policyContext = MediaAccessContext.adult,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const FederatedSearchResult(query: '', hits: [], outcomes: []);
    }

    final selected = adapters
        .where((adapter) => sourceId == null || adapter.source.id == sourceId)
        .toList(growable: false);
    final entries = await Future.wait(selected.map(
      (adapter) => _searchOne(
        adapter: adapter,
        query: normalizedQuery,
        explicitSourceSelection: sourceId == adapter.source.id,
        policyContext: policyContext,
      ),
    ));
    final priorities = {
      for (final adapter in selected)
        adapter.source.id: adapter.source.priority,
    };
    final hits = entries.expand((entry) => entry.hits).toList(growable: false)
      ..sort((left, right) => _compareHits(left, right, priorities));
    return FederatedSearchResult(
      query: normalizedQuery,
      hits: hits,
      outcomes: entries.map((entry) => entry.outcome).toList(growable: false),
    );
  }

  Future<_SearchEntry> _searchOne({
    required MediaSourceAdapter adapter,
    required String query,
    required bool explicitSourceSelection,
    required MediaAccessContext policyContext,
  }) async {
    final source = adapter.source;
    if (!MediaAccessPolicy.evaluateSource(
      source,
      SourceAction.search,
      context: policyContext,
      explicitSourceSelection: explicitSourceSelection,
    ).allowed) {
      return _SearchEntry(
        const [],
        SourceSearchOutcome(
          sourceId: source.id,
          sourceName: source.name,
          status: SourceSearchStatus.skipped,
        ),
      );
    }
    try {
      final hits = (await adapter.search(query).timeout(timeout))
          .where(
            (hit) => MediaAccessPolicy.evaluateItem(
              source,
              hit.item,
              SourceAction.search,
              context: policyContext,
              explicitSourceSelection: explicitSourceSelection,
            ).allowed,
          )
          .toList(growable: false);
      return _SearchEntry(
        hits,
        SourceSearchOutcome(
          sourceId: source.id,
          sourceName: source.name,
          status: hits.isEmpty
              ? SourceSearchStatus.empty
              : SourceSearchStatus.succeeded,
          resultCount: hits.length,
        ),
      );
    } on TimeoutException {
      return _SearchEntry(
        const [],
        SourceSearchOutcome(
          sourceId: source.id,
          sourceName: source.name,
          status: SourceSearchStatus.timedOut,
        ),
      );
    } catch (_) {
      return _SearchEntry(
        const [],
        SourceSearchOutcome(
          sourceId: source.id,
          sourceName: source.name,
          status: SourceSearchStatus.failed,
        ),
      );
    }
  }

  static int _compareHits(
    MediaSearchHit left,
    MediaSearchHit right,
    Map<String, int> priorities,
  ) {
    final titleMatch = _isExactTitle(right) - _isExactTitle(left);
    if (titleMatch != 0) return titleMatch;
    final playable = (right.playable ? 1 : 0) - (left.playable ? 1 : 0);
    if (playable != 0) return playable;
    final priority = (priorities[right.item.sourceId] ?? 0)
        .compareTo(priorities[left.item.sourceId] ?? 0);
    if (priority != 0) return priority;
    final relevance = right.relevance.compareTo(left.relevance);
    if (relevance != 0) return relevance;
    final title = left.item.title.compareTo(right.item.title);
    return title != 0 ? title : left.item.id.compareTo(right.item.id);
  }

  static int _isExactTitle(MediaSearchHit hit) =>
      hit.item.title.trim().toLowerCase() == hit.query.trim().toLowerCase()
          ? 1
          : 0;
}

class _SearchEntry {
  const _SearchEntry(this.hits, this.outcome);

  final List<MediaSearchHit> hits;
  final SourceSearchOutcome outcome;
}
