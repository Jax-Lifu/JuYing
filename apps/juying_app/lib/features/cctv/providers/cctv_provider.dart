import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:juying/features/cctv/models/cctv_album.dart';
import 'package:juying/features/cctv/models/cctv_category.dart';
import 'package:juying/features/cctv/models/cctv_channel.dart';
import 'package:juying/features/cctv/models/cctv_filter.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';

/// Provider exposing singleton [CctvApiService].
final cctvApiServiceProvider = Provider<CctvApiService>((ref) {
  return CctvApiService();
});

/// StateNotifier managing current multi-dimensional filter selection.
class CctvFilterNotifier extends StateNotifier<CctvFilterState> {
  CctvFilterNotifier() : super(const CctvFilterState());

  void setTopCategory(CctvTopCategory category) {
    if (state.topCategory != category) {
      state = CctvFilterState(
        topCategory: category,
        viewMode: state.viewMode,
      );
    }
  }

  void setGenre(String genre) {
    state = state.copyWith(genre: genre == '全部' ? '' : genre);
  }

  void setArea(String area) {
    state = state.copyWith(area: area == '全部' ? '' : area);
  }

  void setYear(String year) {
    state = state.copyWith(year: year == '全部' ? '' : year);
  }

  void setLetter(String letter) {
    state = state.copyWith(letter: letter == '全部' ? '' : letter);
  }

  void setChannelId(String channelId) {
    state = state.copyWith(channelId: channelId == '全部' ? '' : channelId);
  }

  void setTag(String tag) {
    state = state.copyWith(tag: tag == '全部' ? '' : tag);
  }

  void setViewMode(CctvViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }

  void resetFilters() {
    state = CctvFilterState(
      topCategory: state.topCategory,
      viewMode: state.viewMode,
    );
  }
}

final cctvFilterProvider =
    StateNotifierProvider<CctvFilterNotifier, CctvFilterState>((ref) {
  return CctvFilterNotifier();
});

/// State holding paginated CCTV YXG archive albums and query metrics.
class CctvYxgState {
  const CctvYxgState({
    this.albums = const <CctvAlbum>[],
    this.total = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.errorMessage,
  });

  final List<CctvAlbum> albums;
  final int total;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int currentPage;
  final String? errorMessage;

  CctvYxgState copyWith({
    List<CctvAlbum>? albums,
    int? total,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? currentPage,
    String? errorMessage,
  }) {
    return CctvYxgState(
      albums: albums ?? this.albums,
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      errorMessage: errorMessage,
    );
  }
}

class CctvYxgNotifier extends StateNotifier<CctvYxgState> {
  CctvYxgNotifier(this._service, this._filter) : super(const CctvYxgState()) {
    loadFirstPage();
  }

  final CctvApiService _service;
  final CctvFilterState _filter;

  Future<void> loadFirstPage() async {
    state = state.copyWith(isLoading: true, errorMessage: null, currentPage: 1);
    try {
      final effectiveGenre = _filter.topCategory == CctvTopCategory.special &&
              _filter.tag.isNotEmpty
          ? _filter.tag
          : _filter.genre;

      final result = await _service.fetchYxgAlbums(
        firstCategory: _filter.topCategory.fc,
        genre: effectiveGenre,
        area: _filter.area,
        year: _filter.year,
        letter: _filter.letter,
        channelId: _filter.channelId,
        page: 1,
        pageSize: 24,
      );

      // 切换筛选会销毁旧 provider，迟到的响应必须随旧页面丢弃。
      if (!mounted) return;
      state = state.copyWith(
        albums: result.albums,
        total: result.total,
        isLoading: false,
        hasMore:
            result.albums.length >= 24 && result.albums.length < result.total,
        currentPage: 1,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);
    final nextPage = state.currentPage + 1;

    try {
      final effectiveGenre = _filter.topCategory == CctvTopCategory.special &&
              _filter.tag.isNotEmpty
          ? _filter.tag
          : _filter.genre;

      final result = await _service.fetchYxgAlbums(
        firstCategory: _filter.topCategory.fc,
        genre: effectiveGenre,
        area: _filter.area,
        year: _filter.year,
        letter: _filter.letter,
        channelId: _filter.channelId,
        page: nextPage,
        pageSize: 24,
      );

      if (!mounted) return;
      if (result.albums.isEmpty) {
        state = state.copyWith(isLoadingMore: false, hasMore: false);
      } else {
        final combined = <CctvAlbum>[...state.albums, ...result.albums];
        state = state.copyWith(
          albums: combined,
          total: result.total > 0 ? result.total : state.total,
          isLoadingMore: false,
          hasMore: combined.length <
                  (result.total > 0 ? result.total : combined.length + 1) &&
              result.albums.length >= 24,
          currentPage: nextPage,
        );
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final cctvYxgNotifierProvider = StateNotifierProvider.autoDispose
    .family<CctvYxgNotifier, CctvYxgState, CctvFilterState>((ref, filter) {
  final service = ref.watch(cctvApiServiceProvider);
  return CctvYxgNotifier(service, filter);
});

/// List of flagship CCTV categories for backward compatibility.
final cctvCategoriesProvider = Provider<List<CctvCategory>>((ref) {
  return CctvCategory.presetCategories;
});

class ActiveCctvCategoryNotifier extends StateNotifier<CctvCategory> {
  ActiveCctvCategoryNotifier() : super(CctvCategory.presetCategories.first);

  void selectCategory(CctvCategory category) {
    if (state.id != category.id) {
      state = category;
    }
  }
}

final activeCctvCategoryProvider =
    StateNotifierProvider<ActiveCctvCategoryNotifier, CctvCategory>((ref) {
  return ActiveCctvCategoryNotifier();
});

final cctvAlbumsProvider =
    FutureProvider.autoDispose<List<CctvAlbum>>((ref) async {
  final service = ref.watch(cctvApiServiceProvider);
  final activeCat = ref.watch(activeCctvCategoryProvider);

  return service.fetchAlbums(
    channelId: activeCat.channelId,
    firstCategory: activeCat.firstCategory,
    page: 1,
    pageSize: 30,
  );
});

/// Full list of official CCTV live channels (1-17, 4K).
final cctvLiveChannelsProvider = Provider<List<CctvChannel>>((ref) {
  return CctvChannel.officialChannels;
});
