import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/features/cctv/models/cctv_album.dart';
import 'package:juying/features/cctv/models/cctv_filter.dart';
import 'package:juying/features/cctv/providers/cctv_provider.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// Flagship Official CCTV Program Archive Page matching `https://tv.cctv.com/yxg/index.shtml`.
///
/// **What**: Provides complete multi-dimensional filtering across CCTV Movies, Drama,
/// Animation, Documentary, and Special Broadcast Programs alongside grid/list view switching and 4K VDN playback.
///
/// **Why**: CCTV official archives operate under a dedicated broadcast taxonomy (电视剧/动画片/纪录片/特别节目)
/// with multi-tier filters (类型/地区/年份/首字母/频道/热门标签). Replicating the authentic YXG portal
/// gives users broadcast-quality discovery without TVBox scraper unreliability.
class CctvPage extends ConsumerStatefulWidget {
  const CctvPage({super.key});

  @override
  ConsumerState<CctvPage> createState() => _CctvPageState();
}

class _CctvPageState extends ConsumerState<CctvPage> {
  final ScrollController _scrollController = ScrollController();
  int? _lastPrefetchProbe;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    _prefetchNextPageIfNeeded();
  }

  /// 在用户抵达列表尾部前静默补页，避免把网络等待暴露成列表底部转圈。
  void _prefetchNextPageIfNeeded() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.extentAfter > position.viewportDimension * 2.5) return;

    final filter = ref.read(cctvFilterProvider);
    unawaited(
      ref.read(cctvYxgNotifierProvider(filter).notifier).loadMore(),
    );
  }

  /// 首屏不足 2.5 个视口时主动补页；按筛选和结果数去重，避免每次重绘都探测。
  void _scheduleInitialPrefetch(
    CctvFilterState filter,
    CctvYxgState state,
  ) {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final probe = Object.hash(filter, state.albums.length);
    if (_lastPrefetchProbe == probe) return;
    _lastPrefetchProbe = probe;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetchNextPageIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filter = ref.watch(cctvFilterProvider);
    final yxgState = ref.watch(cctvYxgNotifierProvider(filter));
    _scheduleInitialPrefetch(filter, yxgState);

    return Scaffold(
      backgroundColor: colors.backgroundDeep,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: <Widget>[
          // 1. CCTV YXG Portal Header
          SliverToBoxAdapter(
            child: _buildPortalHeader(colors),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 6),
          ),

          // 3. 一级分类与子筛选共同吸附，长列表中始终保留完整检索上下文。
          SliverPersistentHeader(
            pinned: true,
            delegate: _CctvFilterHeaderDelegate(
              colors: colors,
              extent: _filterHeaderExtent(filter.topCategory),
              child: _buildPinnedFilterPanel(colors, filter),
            ),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 10),
          ),

          // 5. Query Results Count & View Mode Switcher
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Row(
                children: <Widget>[
                  Text(
                    '共有 ',
                    style: TextStyle(color: colors.textSecondary, fontSize: 14),
                  ),
                  Text(
                    '${yxgState.total}',
                    style: const TextStyle(
                      color: Color(0xFFE50914),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    ' 个符合条件的内容',
                    style: TextStyle(color: colors.textSecondary, fontSize: 14),
                  ),
                  const Spacer(),

                  // Reset Filter Action
                  if (filter.genre.isNotEmpty ||
                      filter.area.isNotEmpty ||
                      filter.year.isNotEmpty ||
                      filter.letter.isNotEmpty ||
                      filter.channelId.isNotEmpty ||
                      filter.tag.isNotEmpty)
                    TvFocusWrapper(
                      onTap: () {
                        ref.read(cctvFilterProvider.notifier).resetFilters();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: colors.surfaceElevation,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.refresh,
                                size: 14, color: colors.textTertiary),
                            const SizedBox(width: 4),
                            Text(
                              '重置筛选',
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Grid / List View Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceElevation,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: <Widget>[
                        TvFocusWrapper(
                          onTap: () => ref
                              .read(cctvFilterProvider.notifier)
                              .setViewMode(CctvViewMode.grid),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: filter.viewMode == CctvViewMode.grid
                                  ? colors.brandPrimary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Icon(
                              Icons.grid_view,
                              size: 16,
                              color: filter.viewMode == CctvViewMode.grid
                                  ? Colors.white
                                  : colors.textTertiary,
                            ),
                          ),
                        ),
                        TvFocusWrapper(
                          onTap: () => ref
                              .read(cctvFilterProvider.notifier)
                              .setViewMode(CctvViewMode.list),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: filter.viewMode == CctvViewMode.list
                                  ? colors.brandPrimary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Icon(
                              Icons.view_list,
                              size: 16,
                              color: filter.viewMode == CctvViewMode.list
                                  ? Colors.white
                                  : colors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 10),
          ),

          // 6. Content Section (Grid Mode vs List Mode)
          if (yxgState.isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(60),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (yxgState.errorMessage != null && yxgState.albums.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.error_outline,
                          size: 48, color: colors.statusError),
                      const SizedBox(height: 12),
                      Text(
                        '加载央视片库失败: ${yxgState.errorMessage}',
                        style: TextStyle(color: colors.statusError),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (yxgState.albums.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(60),
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.inbox, size: 48, color: colors.textTertiary),
                      const SizedBox(height: 12),
                      Text(
                        '暂无对应的筛选结果，请尝试其他类型',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (filter.viewMode == CctvViewMode.grid) ...<Widget>[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.65,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final album = yxgState.albums[index];
                    return _buildGridCard(colors, album);
                  },
                  childCount: yxgState.albums.length,
                ),
              ),
            ),
          ] else ...<Widget>[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final album = yxgState.albums[index];
                    return _buildListCard(colors, album);
                  },
                  childCount: yxgState.albums.length,
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(
            child: SizedBox(height: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildPortalHeader(AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: colors.brandPrimary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '央视片库',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                '中央广播电视总台官方节目归档',
                style: TextStyle(color: colors.textTertiary, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          TvFocusWrapper(
            onTap: () => context.go('/live'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.live_tv_rounded,
                      size: 17, color: colors.textSecondary),
                  const SizedBox(width: 7),
                  Text(
                    '央视直播',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TvFocusWrapper(
            onTap: () => context.push('/search'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search, size: 17, color: colors.textSecondary),
                  const SizedBox(width: 7),
                  Text(
                    context.tr('nav_search'),
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _filterHeaderExtent(CctvTopCategory category) {
    final rowCount = switch (category) {
      CctvTopCategory.animation => 3,
      CctvTopCategory.movie => 3,
      _ => 4,
    };
    // Windows 非整数缩放会把文字行高向上取整；预留 4px 避免吸附时出现 RenderFlex 溢出条纹。
    return 88 + rowCount * 40;
  }

  Widget _buildPinnedFilterPanel(
    AppThemeColors colors,
    CctvFilterState filter,
  ) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 46,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surfaceElevation,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: CctvTopCategory.values.map((category) {
                final isSelected = filter.topCategory == category;
                return Expanded(
                  child: TvFocusWrapper(
                    onTap: () => ref
                        .read(cctvFilterProvider.notifier)
                        .setTopCategory(category),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colors.brandPrimary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : colors.textSecondary,
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // 剩余空间由子筛选面板消费，避免字体度量变化再次破坏外层 Column 高度契约。
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.surfaceElevation),
            ),
            child: Column(
              children: <Widget>[
                _buildFilterRow(
                  label: '类型',
                  options: _getGenreOptionsForCategory(filter.topCategory),
                  selectedValue: filter.genre.isEmpty ? '全部' : filter.genre,
                  onSelected: (value) =>
                      ref.read(cctvFilterProvider.notifier).setGenre(value),
                  colors: colors,
                ),
                if (filter.topCategory == CctvTopCategory.documentary ||
                    filter.topCategory == CctvTopCategory.special)
                  _buildChannelFilterRow(
                    label: '频道',
                    channels: CctvFilterState.channels,
                    selectedId: filter.channelId,
                    onSelected: (value) => ref
                        .read(cctvFilterProvider.notifier)
                        .setChannelId(value),
                    colors: colors,
                  ),
                if (filter.topCategory == CctvTopCategory.special)
                  _buildFilterRow(
                    label: '热门标签',
                    options: CctvFilterState.specialTags,
                    selectedValue: filter.tag.isEmpty ? '全部' : filter.tag,
                    onSelected: (value) =>
                        ref.read(cctvFilterProvider.notifier).setTag(value),
                    colors: colors,
                  ),
                if (filter.topCategory == CctvTopCategory.drama ||
                    filter.topCategory == CctvTopCategory.animation)
                  _buildFilterRow(
                    label: '地区',
                    options: CctvFilterState.areas,
                    selectedValue: filter.area.isEmpty ? '全部' : filter.area,
                    onSelected: (value) =>
                        ref.read(cctvFilterProvider.notifier).setArea(value),
                    colors: colors,
                  ),
                if (filter.topCategory == CctvTopCategory.movie ||
                    filter.topCategory == CctvTopCategory.drama ||
                    filter.topCategory == CctvTopCategory.documentary)
                  _buildFilterRow(
                    label: '年份',
                    options: CctvFilterState.years,
                    selectedValue: filter.year.isEmpty ? '全部' : filter.year,
                    onSelected: (value) =>
                        ref.read(cctvFilterProvider.notifier).setYear(value),
                    colors: colors,
                  ),
                _buildFilterRow(
                  label: '首字母',
                  options: CctvFilterState.letters,
                  selectedValue: filter.letter.isEmpty ? '全部' : filter.letter,
                  onSelected: (value) =>
                      ref.read(cctvFilterProvider.notifier).setLetter(value),
                  colors: colors,
                  isLetterRow: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<String> _getGenreOptionsForCategory(CctvTopCategory cat) {
    switch (cat) {
      case CctvTopCategory.drama:
        return CctvFilterState.dramaGenres;
      case CctvTopCategory.movie:
        return CctvFilterState.movieGenres;
      case CctvTopCategory.animation:
        return CctvFilterState.animationGenres;
      case CctvTopCategory.documentary:
        return CctvFilterState.documentaryGenres;
      case CctvTopCategory.special:
        return CctvFilterState.specialGenres;
    }
  }

  Widget _buildFilterRow({
    required String label,
    required List<String> options,
    required String selectedValue,
    required ValueChanged<String> onSelected,
    required AppThemeColors colors,
    bool isLetterRow = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: options.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = (option == selectedValue) ||
                      (option == '全部' && selectedValue.isEmpty);

                  return TvFocusWrapper(
                    onTap: () => onSelected(option),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isLetterRow ? 8 : 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFE50914)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          option,
                          style: TextStyle(
                            color:
                                isSelected ? Colors.white : colors.textPrimary,
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelFilterRow({
    required String label,
    required List<Map<String, String>> channels,
    required String selectedId,
    required ValueChanged<String> onSelected,
    required AppThemeColors colors,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: channels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final ch = channels[index];
                  final name = ch['name'] ?? '';
                  final id = ch['id'] ?? '';
                  final isSelected =
                      (id == selectedId) || (id.isEmpty && selectedId.isEmpty);

                  return TvFocusWrapper(
                    onTap: () => onSelected(id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFE50914)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          name,
                          style: TextStyle(
                            color:
                                isSelected ? Colors.white : colors.textPrimary,
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCard(AppThemeColors colors, CctvAlbum album) {
    final mediaItem = album.toMediaItem();

    return TvFocusWrapper(
      onTap: () {
        context.push('/detail', extra: mediaItem);
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.surfaceElevation),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.network(
                    album.posterUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: colors.surfaceElevation,
                      child:
                          Icon(Icons.tv, color: colors.textTertiary, size: 36),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${album.totalEpisodes}集全',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914).withAlpha(220),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        album.channelName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.actors.isNotEmpty
                        ? '主演: ${album.actors}'
                        : album.overview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListCard(AppThemeColors colors, CctvAlbum album) {
    final mediaItem = album.toMediaItem();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TvFocusWrapper(
        onTap: () {
          context.push('/detail', extra: mediaItem);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.surfaceElevation),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Poster
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 100,
                  height: 140,
                  child: Image.network(
                    album.posterUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: colors.surfaceElevation,
                      child:
                          Icon(Icons.tv, color: colors.textTertiary, size: 32),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Info Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            album.title,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            album.channelName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Text(
                          '集数: ',
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 12),
                        ),
                        Text(
                          '${album.totalEpisodes}集',
                          style: TextStyle(
                              color: colors.textPrimary, fontSize: 12),
                        ),
                        if (album.year.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 16),
                          Text(
                            '年份: ',
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 12),
                          ),
                          Text(
                            album.year,
                            style: TextStyle(
                                color: colors.textPrimary, fontSize: 12),
                          ),
                        ],
                        if (album.category.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 16),
                          Text(
                            '分类: ',
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 12),
                          ),
                          Text(
                            album.category,
                            style: TextStyle(
                                color: colors.textPrimary, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                    if (album.actors.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        '主演: ${album.actors}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '简介: ${album.overview}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                          height: 1.3),
                    ),
                  ],
                ),
              ),

              // Detail Chevron Button
              const SizedBox(width: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.surfaceElevation,
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: colors.brandPrimary.withAlpha(80)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '详情',
                        style: TextStyle(
                          color: colors.brandPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right,
                          size: 16, color: colors.brandPrimary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 将一级分类和子筛选作为同一个吸附上下文，避免筛选条件滚出视口。
class _CctvFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CctvFilterHeaderDelegate({
    required this.colors,
    required this.extent,
    required this.child,
  });

  final AppThemeColors colors;
  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: colors.backgroundDeep,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 7, 24, 7),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: overlapsContent
                ? <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withAlpha(90),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_CctvFilterHeaderDelegate oldDelegate) {
    return oldDelegate.colors != colors ||
        oldDelegate.extent != extent ||
        oldDelegate.child != child;
  }
}
