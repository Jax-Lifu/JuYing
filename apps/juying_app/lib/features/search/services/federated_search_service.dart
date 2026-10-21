import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';

/// Aggregated search result entry containing canonical identity and associated playable source lines.
class AggregatedSearchResult {
  const AggregatedSearchResult({
    required this.item,
    this.candidates = const <PlaybackCandidate>[],
  });

  final MediaItem item;
  final List<PlaybackCandidate> candidates;

  AggregatedSearchResult copyWith({
    MediaItem? item,
    List<PlaybackCandidate>? candidates,
  }) {
    return AggregatedSearchResult(
      item: item ?? this.item,
      candidates: candidates ?? this.candidates,
    );
  }
}

/// Orchestrates cross-source federated searches with debounce, epoch isolation, and identity aggregation.
///
/// **What**: Concurrently queries CCTV official catalogs (drama, animation, documentary, special) and TVBox spiders,
/// deduplicates results under standard [MediaItem] entities, and discards obsolete responses via monotonic Epoch tokens.
///
/// **Why**: On TV remote typing, rapid key presses spawn overlapping HTTP tasks. An Epoch guard
/// guarantees that sluggish responses from previous queries never overwrite current results.
class FederatedSearchService {
  FederatedSearchService({
    CctvApiService? cctvApiService,
  }) : _cctvApiService = cctvApiService ?? CctvApiService();

  final CctvApiService _cctvApiService;

  int _searchEpochId = 0;
  Timer? _debounceTimer;

  int get currentEpochId => _searchEpochId;

  /// Initiates a debounced (300ms) federated search across all active providers.
  void searchDebounced(
    String query, {
    required void Function(List<AggregatedSearchResult> results, int epochId)
        onUpdate,
    Duration debounceDuration = const Duration(milliseconds: 300),
  }) {
    _debounceTimer?.cancel();
    // 输入变化立即使旧结果失效，不能等防抖计时结束才推进世代。
    final epoch = ++_searchEpochId;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      onUpdate(<AggregatedSearchResult>[], epoch);
      return;
    }

    _debounceTimer = Timer(debounceDuration, () {
      unawaited(executeSearch(trimmed, onUpdate: onUpdate));
    });
  }

  /// Immediately dispatches a federated search with Epoch increment.
  Future<void> executeSearch(
    String query, {
    required void Function(List<AggregatedSearchResult> results, int epochId)
        onUpdate,
  }) async {
    _debounceTimer?.cancel();
    final thisEpoch = ++_searchEpochId;
    final Map<String, AggregatedSearchResult> resultMap =
        <String, AggregatedSearchResult>{};

    debugPrint(
        '[FederatedSearch] Starting Epoch #$thisEpoch for query: "$query"');

    // 2. Concurrently query CCTV Official Catalog across categories
    final isPinyinLetter = RegExp(r'^[a-zA-Z]$').hasMatch(query);
    final letterParam = isPinyinLetter ? query.toUpperCase() : '';

    try {
      final categories = <String>['电影', '电视剧', '动画片', '纪录片', '特别节目'];
      final futures = categories.map(
        (cat) => _cctvApiService.fetchYxgAlbums(
          firstCategory: cat,
          letter: letterParam,
          page: 1,
          pageSize: 12,
        ),
      );

      final queryResults = await Future.wait(futures);
      if (thisEpoch != _searchEpochId) return; // Discard stale epoch

      final lowerQuery = query.toLowerCase();

      for (var i = 0; i < categories.length; i++) {
        final catName = categories[i];
        final res = queryResults[i];

        for (final album in res.albums) {
          // If search was keyword-based, filter by title/actors matching
          if (!isPinyinLetter) {
            final matchTitle = album.title.toLowerCase().contains(lowerQuery);
            final matchActors = album.actors.toLowerCase().contains(lowerQuery);
            if (!matchTitle && !matchActors) continue;
          }

          final mediaItem = MediaItem(
            id: 'cctv_album_${album.id}',
            title: album.title,
            year: album.year,
            rating: album.rating,
            genres: <String>[catName, if (album.area.isNotEmpty) album.area],
            overview: album.overview,
            posterUrl: album.posterUrl,
            backdropUrl: album.posterUrl,
            totalEpisodes: album.totalEpisodes,
          );

          // 列表没有剧集信息，留给详情页加载；空线路会被误认为已解析。
          // 专辑 ID 才能区分同名翻拍，也能合并多个分类返回的同一专辑。
          resultMap[album.id] = AggregatedSearchResult(
            item: mediaItem,
          );
        }
      }

      onUpdate(resultMap.values.toList(), thisEpoch);
    } catch (e) {
      debugPrint('[FederatedSearch] CCTV query error: $e');
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    ++_searchEpochId;
  }
}
