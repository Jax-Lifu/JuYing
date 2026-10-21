import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/core/history/playback_history_service.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/detail/presentation/video_detail_page.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/models/tvbox_subscription.dart';
import 'package:juying/features/tvbox/providers/tvbox_provider.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// Aggregated media discovery home page featuring TVBox multi-site switching and hero spotlights.
///
/// **What**: Dynamically queries the active TVBox site (CCTV official, FanTaiYing, FeiMao, QiaoEr, Douban),
/// rendering responsive category tabs, continue watching history, and high-density media poster shelves.
///
/// **Why**: Media aggregation clients allow seamless switching across multiple TVBox spider backends
/// without reloading the application shell or losing playback state.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, this.spiderEngine});

  /// 可替换数据入口，便于离线验证加载失败与切源请求的先后顺序。
  final TvBoxSpiderEngine? spiderEngine;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final TvBoxSpiderEngine _spiderEngine =
      widget.spiderEngine ?? TvBoxSpiderEngine();
  final ScrollController _scrollController = ScrollController();
  int _selectedCategoryIndex = 0;
  List<MediaItem> _shelfItems = <MediaItem>[];
  List<TvBoxCategory> _runtimeCategories = <TvBoxCategory>[];
  List<PlaybackHistoryItem> _historyList = <PlaybackHistoryItem>[];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _loadGeneration = 0;
  String? _loadedSiteKey;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();
      _loadActiveSiteData();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadMoreCategoryData();
    }
  }

  Future<void> _loadHistory() async {
    final history = await PlaybackHistoryService.instance.getHistory();
    if (mounted) {
      setState(() {
        _historyList = history;
      });
    }
  }

  String? _historyPreviewUrl(PlaybackHistoryItem history) {
    if (history.posterUrl.isNotEmpty) return history.posterUrl;
    for (final item in _shelfItems) {
      if (item.id != history.id && item.title != history.title) continue;
      final preview = item.backdropUrl ?? item.posterUrl;
      if (preview != null && preview.isNotEmpty) return preview;
    }
    return null;
  }

  Future<void> _loadActiveSiteData({bool resetCategory = false}) async {
    final activeSite = ref.read(activeTvBoxSiteProvider);
    final generation = ++_loadGeneration;
    _loadedSiteKey = activeSite.key;
    if (resetCategory) {
      _selectedCategoryIndex = 0;
      _runtimeCategories = <TvBoxCategory>[];
    }
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _hasMore = true;
      _isLoadingMore = false;
      _shelfItems = <MediaItem>[];
    });

    try {
      final categories = await _spiderEngine.fetchSiteCategories(activeSite);
      if (!mounted || generation != _loadGeneration) return;
      final catId =
          categories.isNotEmpty && _selectedCategoryIndex < categories.length
              ? categories[_selectedCategoryIndex].id
              : 'default';

      final items = await _spiderEngine.fetchCategoryMedia(
        activeSite,
        catId,
        page: 1,
      );

      if (mounted &&
          generation == _loadGeneration &&
          ref.read(activeTvBoxSiteProvider).key == activeSite.key) {
        setState(() {
          _shelfItems = items;
          _runtimeCategories = categories;
          _isLoading = false;
          _hasMore = items.length >= 8;
        });
      }
    } catch (_) {
      // 失败沿用空列表的重试入口；旧源的迟到异常不能结束新源的加载。
      if (!mounted ||
          generation != _loadGeneration ||
          ref.read(activeTvBoxSiteProvider).key != activeSite.key) {
        return;
      }
      setState(() {
        _isLoading = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _loadMoreCategoryData() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final activeSite = ref.read(activeTvBoxSiteProvider);
    final generation = _loadGeneration;
    final categories = _runtimeCategories;
    final catId =
        categories.isNotEmpty && _selectedCategoryIndex < categories.length
            ? categories[_selectedCategoryIndex].id
            : 'default';
    final nextPage = _currentPage + 1;

    setState(() => _isLoadingMore = true);

    try {
      final newItems = await _spiderEngine.fetchCategoryMedia(
        activeSite,
        catId,
        page: nextPage,
      );

      if (!mounted || generation != _loadGeneration) return;

      if (newItems.isEmpty) {
        setState(() {
          _isLoadingMore = false;
          _hasMore = false;
        });
        return;
      }

      final existingIds = _shelfItems.map((item) => item.id).toSet();
      final deduplicated =
          newItems.where((item) => !existingIds.contains(item.id)).toList();

      setState(() {
        _currentPage = nextPage;
        _shelfItems.addAll(deduplicated);
        _isLoadingMore = false;
        if (newItems.length < 8 || deduplicated.isEmpty) {
          _hasMore = false;
        }
      });
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _switchSite(TvBoxSite site) {
    if (!site.isRuntimeSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(site.spiderRuntimeCapability.reason)),
      );
      return;
    }
    ref.read(activeTvBoxSiteProvider.notifier).selectSite(site);
    _loadActiveSiteData(resetCategory: true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeSite = ref.watch(activeTvBoxSiteProvider);
    final subscriptions = ref.watch(tvBoxSubscriptionsProvider);
    final categories = _runtimeCategories;
    final heroItem = _shelfItems.firstOrNull;
    if (_loadedSiteKey != activeSite.key) {
      _loadedSiteKey = activeSite.key;
      _selectedCategoryIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadActiveSiteData();
      });
    }

    final activeCategoryName =
        categories.isNotEmpty && _selectedCategoryIndex < categories.length
            ? categories[_selectedCategoryIndex].name
            : '全部推荐';

    return Scaffold(
      backgroundColor: colors.backgroundDeep,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: <Widget>[
          // Top Bar with TVBox Active Site Switcher Pill
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: <Widget>[
                  Text(
                    '🎬 聚映',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    context.tr('home_switch_site'),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TvFocusWrapper(
                    onTap: () =>
                        _showSiteSelectorModal(subscriptions, activeSite),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.surfaceElevation,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colors.brandPrimary.withAlpha(120),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            activeSite.type == 4
                                ? Icons.verified_user
                                : Icons.hub,
                            size: 14,
                            color: colors.brandAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            activeSite.name,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 16,
                            color: colors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Hero Spotlight Banner (Only on first tab if heroItem exists)
          if (_selectedCategoryIndex == 0 && heroItem != null)
            SliverToBoxAdapter(
              child: _buildHeroBanner(colors, heroItem),
            ),

          // Continue Watching Shelf (if history exists)
          if (_historyList.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildContinueWatchingShelf(colors, _historyList),
            ),

          // Category Navigation Bar
          if (categories.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                height: 48,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = _selectedCategoryIndex == index;

                    return TvFocusWrapper(
                      onTap: () {
                        if (_selectedCategoryIndex == index) return;
                        setState(() {
                          _selectedCategoryIndex = index;
                        });
                        _loadActiveSiteData();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.brandPrimary
                              : colors.surfaceElevation,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            cat.name,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : colors.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Category Header Title
          if (!_isLoading && _shelfItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: <Widget>[
                    Text(
                      '${activeSite.name} · $activeCategoryName',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceElevation,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '已加载 ${_shelfItems.length} 部',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Media Content Grid / State
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (_shelfItems.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.video_library_outlined,
                        color: colors.textTertiary,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${activeSite.name} 暂未返回可播放内容',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '该站源可能正在维护或网络波动，建议切换至其他可用站源',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.brandPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                            ),
                            onPressed: () => _showSiteSelectorModal(
                              subscriptions,
                              activeSite,
                            ),
                            icon: const Icon(Icons.swap_horiz,
                                color: Colors.white, size: 18),
                            label: const Text('切换可用站源',
                                style: TextStyle(color: Colors.white)),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.textPrimary,
                              side: BorderSide(color: colors.surfaceElevation),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                            ),
                            onPressed: _loadActiveSiteData,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('重试刷新'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...<Widget>[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _calculateCrossAxisCount(context),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = _shelfItems[index];
                    return _buildMediaGridCard(colors, item);
                  },
                  childCount: _shelfItems.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildPaginationFooter(colors),
            ),
          ],

          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
        ],
      ),
    );
  }

  void _showSiteSelectorModal(
    List<TvBoxSubscription> subscriptions,
    TvBoxSite activeSite,
  ) {
    final colors = context.colors;
    TvBoxSubscription? selectedSubscription;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surfaceCard,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final selected = selectedSubscription;
            return Container(
              padding: const EdgeInsets.all(20),
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (selected != null)
                        IconButton(
                          onPressed: () => setModalState(
                            () => selectedSubscription = null,
                          ),
                          icon: Icon(
                            Icons.arrow_back,
                            color: colors.textPrimary,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          selected?.name ?? '选择 TVBox 订阅',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    selected == null
                        ? '先选择订阅，再选择其中可用的站点'
                        : '${selected.supportedSiteCount}/${selected.sites.length} 个站点可用',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: selected?.sites.length ?? subscriptions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (selected == null) {
                          final subscription = subscriptions[index];
                          final isActive = subscription.sites.any(
                            (site) => site.key == activeSite.key,
                          );
                          return TvFocusWrapper(
                            onTap: () => setModalState(
                              () => selectedSubscription = subscription,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? colors.brandPrimary.withAlpha(42)
                                    : colors.surfaceElevation,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isActive
                                      ? colors.brandPrimary
                                      : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    subscription.isBuiltIn
                                        ? Icons.verified_outlined
                                        : Icons.subscriptions_outlined,
                                    color: isActive
                                        ? colors.focusBorder
                                        : colors.textTertiary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      subscription.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${subscription.supportedSiteCount}/${subscription.sites.length}',
                                    style: TextStyle(
                                      color: colors.textTertiary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: colors.textTertiary,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        // Sort sites: runtime supported sites first for immediate availability
                        final sites = List<TvBoxSite>.from(selected.sites)
                          ..sort((a, b) {
                            if (a.isRuntimeSupported == b.isRuntimeSupported) {
                              return 0;
                            }
                            return a.isRuntimeSupported ? -1 : 1;
                          });
                        final site = sites[index];
                        final isSelected = site.key == activeSite.key;
                        final isFirstSupported =
                            index == 0 && site.isRuntimeSupported;
                        final isFirstUnsupported = !site.isRuntimeSupported &&
                            (index == 0 || sites[index - 1].isRuntimeSupported);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (isFirstSupported) ...<Widget>[
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 6,
                                ),
                                child: Text(
                                  '🟢 可用站点 (${selected.supportedSiteCount})',
                                  style: TextStyle(
                                    color: colors.brandAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            if (isFirstUnsupported) ...<Widget>[
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  top: 10,
                                  bottom: 6,
                                ),
                                child: Text(
                                  '⏳ 待适配 Android 原生站源 (${selected.sites.length - selected.supportedSiteCount})',
                                  style: TextStyle(
                                    color: colors.textTertiary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            TvFocusWrapper(
                              onTap: () {
                                Navigator.of(context).pop();
                                _switchSite(site);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? colors.brandPrimary.withAlpha(50)
                                      : colors.surfaceElevation,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? colors.brandPrimary
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      color: isSelected
                                          ? colors.focusBorder
                                          : site.isRuntimeSupported
                                              ? colors.textTertiary
                                              : colors.statusError,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        site.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      site.isRuntimeSupported
                                          ? site.adapterLabel
                                          : site.spiderRuntimeCapability.label,
                                      style: TextStyle(
                                        color: site.isRuntimeSupported
                                            ? colors.brandAccent
                                            : colors.statusError,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContinueWatchingShelf(
      AppThemeColors colors, List<PlaybackHistoryItem> history) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '🕒 继续观看 (Continue Watching)',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              InkWell(
                onTap: () async {
                  await PlaybackHistoryService.instance.clearHistory();
                  await _loadHistory();
                },
                child: Text(
                  '清空记录',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 116,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            scrollDirection: Axis.horizontal,
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = history[index];
              final progressPct = (item.progress * 100).toInt();
              final previewUrl = _historyPreviewUrl(item);

              return TvFocusWrapper(
                onTap: () {
                  final mediaItem = MediaItem(
                    id: item.id,
                    title: item.title,
                    overview: '继续播放：${item.episodeName}',
                    posterUrl: previewUrl,
                    backdropUrl: previewUrl,
                  );
                  Navigator.of(context, rootNavigator: true)
                      .push(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (context) => VideoDetailPage(
                            mediaItem: mediaItem,
                          ),
                        ),
                      )
                      .then((_) => _loadHistory());
                },
                child: Container(
                  width: 292,
                  decoration: BoxDecoration(
                    color: colors.surfaceCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.surfaceElevation),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 122,
                        height: double.infinity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            if (previewUrl != null)
                              Image.network(
                                previewUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => ColoredBox(
                                  color: colors.surfaceElevation,
                                  child: Icon(
                                    Icons.movie_outlined,
                                    color: colors.textTertiary,
                                  ),
                                ),
                              )
                            else
                              ColoredBox(
                                color: colors.surfaceElevation,
                                child: Icon(
                                  Icons.movie_outlined,
                                  color: colors.textTertiary,
                                ),
                              ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    Colors.transparent,
                                    Colors.black.withAlpha(95),
                                  ],
                                ),
                              ),
                            ),
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 30,
                                shadows: <Shadow>[
                                  Shadow(color: Colors.black87, blurRadius: 8),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.episodeName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 11,
                                  height: 1.25,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '已观看 $progressPct%',
                                style: TextStyle(
                                  color: colors.textTertiary,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: item.progress,
                                  backgroundColor: colors.surfaceElevation,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    colors.brandPrimary,
                                  ),
                                  minHeight: 3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeroBanner(AppThemeColors colors, MediaItem heroItem) {
    return Container(
      height: 340,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colors.surfaceCard,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: <Widget>[
            // Backdrop Image
            if (heroItem.backdropUrl != null || heroItem.posterUrl != null)
              Positioned.fill(
                child: Image.network(
                  heroItem.backdropUrl ?? heroItem.posterUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),

            // Gradient Overlay
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: <Color>[
                      Colors.black12,
                      Colors.black87,
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              left: 32,
              bottom: 32,
              right: 32,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.brandPrimary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.tr('home_top_pick'),
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '⭐ ${context.tr('home_official_4k')}',
                        style: TextStyle(
                          color: colors.brandAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    heroItem.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    heroItem.overview ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      TvFocusWrapper(
                        autofocus: true,
                        onTap: () {
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (context) => VideoDetailPage(
                                mediaItem: heroItem,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: colors.brandPrimary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.play_arrow, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                context.tr('home_play_now'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TvFocusWrapper(
                        onTap: () {
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (context) => VideoDetailPage(
                                mediaItem: heroItem,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.info_outline,
                                  color: Colors.white),
                              const SizedBox(width: 6),
                              Text(context.tr('home_detail'),
                                  style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _calculateCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1400) return 7;
    if (width >= 1100) return 6;
    if (width >= 850) return 5;
    if (width >= 600) return 4;
    if (width >= 400) return 3;
    return 2;
  }

  Widget _buildMediaGridCard(AppThemeColors colors, MediaItem item) {
    final poster = item.posterUrl;
    final rating = item.rating;
    final genre = item.genres.firstOrNull;

    return TvFocusWrapper(
      onTap: () {
        Navigator.of(context, rootNavigator: true)
            .push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (context) => VideoDetailPage(
                  mediaItem: item,
                ),
              ),
            )
            .then((_) => _loadHistory());
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
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
                  if (poster != null && poster.isNotEmpty)
                    Image.network(
                      poster,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: colors.surfaceElevation,
                        child: Center(
                          child: Icon(
                            Icons.movie_outlined,
                            color: colors.textTertiary,
                            size: 32,
                          ),
                        ),
                      ),
                    )
                  else
                    ColoredBox(
                      color: colors.surfaceElevation,
                      child: Center(
                        child: Icon(
                          Icons.movie_outlined,
                          color: colors.textTertiary,
                          size: 32,
                        ),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.transparent,
                          Colors.black.withAlpha(120),
                        ],
                      ),
                    ),
                  ),
                  if (rating != null && rating > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(180),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '⭐ ${rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (genre != null && genre.isNotEmpty)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.brandPrimary.withAlpha(200),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          genre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                item.overview?.isNotEmpty == true
                    ? item.overview!
                    : item.year?.isNotEmpty == true
                        ? item.year!
                        : '高清点播',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationFooter(AppThemeColors colors) {
    if (_isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                '正在加载更多影片 (第 ${_currentPage + 1} 页)...',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasMore && _shelfItems.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '— 已加载全部内容 (共 ${_shelfItems.length} 部影片) —',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    if (_hasMore && !_isLoadingMore && _shelfItems.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TvFocusWrapper(
            onTap: _loadMoreCategoryData,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceElevation,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.surfaceElevation),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.arrow_downward,
                    size: 16,
                    color: colors.brandAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '加载下一页 (第 ${_currentPage + 1} 页)',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox(height: 24);
  }
}
