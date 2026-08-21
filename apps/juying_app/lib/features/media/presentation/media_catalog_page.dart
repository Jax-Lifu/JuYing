import 'package:flutter/material.dart';

import '../../../application/favorites/favorite_store.dart';
import '../../../application/playback/playback_launcher.dart';
import '../../../application/policy/media_access_policy.dart';
import '../../../application/policy/source_policy.dart';
import '../../../domain/models/media_source.dart';
import '../../../domain/models/unified_media.dart' hide MediaCatalogPage;
import '../../../domain/ports/catalog_initial_category.dart';
import '../../../domain/ports/media_source_adapter.dart';
import '../../../domain/ports/source_catalog_scopes.dart';
import '../../../domain/ports/source_catalog_tabs.dart';
import 'media_detail_page.dart';

class MediaCatalogPage extends StatefulWidget {
  const MediaCatalogPage({
    required this.adapter,
    required this.profileId,
    required this.isChildProfile,
    required this.playbackLauncher,
    this.childDailyLimitMinutes,
    this.initialCategory,
    this.allowedCategories,
    super.key,
  });

  final MediaSourceAdapter adapter;
  final String profileId;
  final bool isChildProfile;
  final PlaybackLauncher playbackLauncher;
  final int? childDailyLimitMinutes;
  final MediaCategory? initialCategory;
  final Set<MediaCategory>? allowedCategories;

  @override
  State<MediaCatalogPage> createState() => _MediaCatalogPageState();
}

class _MediaCatalogPageState extends State<MediaCatalogPage> {
  final FavoriteStore _favoriteStore = FavoriteStore();
  final ScrollController _scrollController = ScrollController();

  late MediaCategory _selectedCategory;
  String? _selectedSubcategoryId;
  int _currentPage = 1;
  int _totalCount = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  Object? _error;
  final List<MediaItem> _items = [];
  Set<String> _favoriteItemIds = {};

  // Scope / Site management
  List<SourceCatalogScope> _scopes = [];
  Set<String>? _availableScopeIds;
  bool _filterAvailableOnly = false;

  MediaAccessContext get _policyContext =>
      MediaAccessContext(isChildProfile: widget.isChildProfile);

  SourceCatalogScopes? get _scopedAdapter =>
      widget.adapter is SourceCatalogScopes
          ? widget.adapter as SourceCatalogScopes
          : null;

  SourceCatalogTabs? get _tabbedAdapter => widget.adapter is SourceCatalogTabs
      ? widget.adapter as SourceCatalogTabs
      : null;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ??
        (widget.adapter is CatalogInitialCategory
            ? (widget.adapter as CatalogInitialCategory).initialCatalogCategory
            : (widget.adapter.source.capabilities
                    .contains(SourceCapability.liveCatalog)
                ? MediaCategory.live
                : MediaCategory.drama));
    _scrollController.addListener(_onScroll);
    _loadFavorites();
    _loadScopes();
    _loadPage(1);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    try {
      final favorites = await _favoriteStore.load(widget.profileId);
      if (!mounted) return;
      setState(() {
        _favoriteItemIds = favorites
            .where((f) => f.sourceId == widget.adapter.source.id)
            .map((f) => f.sourceItemId)
            .toSet();
      });
    } catch (_) {}
  }

  Future<void> _loadScopes() async {
    final scoped = _scopedAdapter;
    if (scoped == null) return;
    try {
      final scopes = await scoped.catalogScopes();
      if (!mounted) return;
      setState(() => _scopes = scopes);
    } catch (_) {}
  }

  Future<void> _toggleAvailableScopesFilter(bool availableOnly) async {
    final scoped = _scopedAdapter;
    if (scoped == null) return;
    setState(() => _filterAvailableOnly = availableOnly);
    if (availableOnly) {
      try {
        final available = await scoped.availableCatalogScopeIds(
          category: _selectedCategory,
          refresh: true,
        );
        if (!mounted) return;
        setState(() => _availableScopeIds = available);
        await scoped.selectCatalogScope(null);
        _refresh();
      } catch (_) {}
    } else {
      setState(() => _availableScopeIds = null);
      _refresh();
    }
  }

  Future<void> _onScopeSelected(String? scopeId) async {
    final scoped = _scopedAdapter;
    if (scoped == null) return;
    await scoped.selectCatalogScope(scopeId);
    if (!mounted) return;
    _refresh();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _items.length < _totalCount) {
        _loadMore();
      }
    }
  }

  Future<void> _refresh() async {
    _currentPage = 1;
    await _loadPage(1);
  }

  Future<void> _loadPage(int page) async {
    setState(() {
      _isLoading = true;
      _error = null;
      if (page == 1) _items.clear();
    });

    final decision = MediaAccessPolicy.evaluateSource(
      widget.adapter.source,
      SourceAction.browse,
      context: _policyContext,
      explicitSourceSelection: true,
    );
    if (!decision.allowed) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = StateError(decision.reason ?? '当前档案不可浏览该来源');
        });
      }
      return;
    }

    try {
      final catalogPage = await widget.adapter.browse(MediaCatalogQuery(
        category: _selectedCategory,
        sourceSubcategoryId: _selectedSubcategoryId,
        page: page,
        pageSize: 48,
      ));
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _currentPage = page;
        _totalCount = catalogPage.total;
        if (page == 1) {
          _items
            ..clear()
            ..addAll(catalogPage.items);
        } else {
          _items.addAll(catalogPage.items);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _currentPage + 1;
    try {
      final catalogPage = await widget.adapter.browse(MediaCatalogQuery(
        category: _selectedCategory,
        sourceSubcategoryId: _selectedSubcategoryId,
        page: nextPage,
        pageSize: 48,
      ));
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _currentPage = nextPage;
        _totalCount = catalogPage.total;
        _items.addAll(catalogPage.items);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _openDetail(MediaItem item) async {
    if (item.category == MediaCategory.live) {
      final allLiveEpisodes = _items
          .where((i) => i.category == MediaCategory.live)
          .map((i) => MediaEpisode(
                sourceId: i.sourceId,
                sourceEpisodeId: i.sourceItemId,
                title: i.title,
                posterUri: i.posterUri,
                officialPageUri: i.defaultEpisodePageUri,
              ))
          .toList(growable: false);

      final episodes = await widget.adapter.episodes(item);
      final episode = episodes.firstOrNull ??
          MediaEpisode(
            sourceId: item.sourceId,
            sourceEpisodeId: item.sourceItemId,
            title: item.title,
            posterUri: item.posterUri,
            officialPageUri: item.defaultEpisodePageUri,
          );

      final nativeAllowed = MediaAccessPolicy.evaluateItem(
        widget.adapter.source,
        item,
        SourceAction.nativePlayback,
        context: _policyContext,
        explicitSourceSelection: true,
      );

      if (nativeAllowed.allowed) {
        try {
          final playback = await widget.adapter.resolvePlayback(episode);
          if (playback.nativeStreamUri != null && mounted) {
            await widget.playbackLauncher.launchNative(
              context,
              PlaybackLaunchRequest(
                playback: playback,
                episodes:
                    allLiveEpisodes.isNotEmpty ? allLiveEpisodes : [episode],
                resolveEpisode: widget.adapter.resolvePlayback,
                profileId: widget.profileId,
                sourceCapabilities: widget.adapter.source.capabilities,
                childDailyLimitMinutes: widget.childDailyLimitMinutes,
              ),
            );
            if (mounted) await _loadFavorites();
            return;
          }
        } catch (_) {}
      }

      final fallbackAllowed = MediaAccessPolicy.evaluateItem(
        widget.adapter.source,
        item,
        SourceAction.officialFallback,
        context: _policyContext,
        explicitSourceSelection: true,
      );

      if (fallbackAllowed.allowed) {
        try {
          final playback =
              await widget.adapter.resolveOfficialFallback(episode);
          if (mounted) {
            await widget.playbackLauncher.launchOfficial(
              context,
              PlaybackLaunchRequest(
                playback: playback,
                episodes:
                    allLiveEpisodes.isNotEmpty ? allLiveEpisodes : [episode],
                resolveEpisode: widget.adapter.resolveOfficialFallback,
                profileId: widget.profileId,
                sourceCapabilities: widget.adapter.source.capabilities,
                childDailyLimitMinutes: widget.childDailyLimitMinutes,
              ),
            );
            if (mounted) await _loadFavorites();
            return;
          }
        } catch (_) {}
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MediaDetailPage(
        item: item,
        adapter: widget.adapter,
        profileId: widget.profileId,
        isChildProfile: widget.isChildProfile,
        playbackLauncher: widget.playbackLauncher,
        childDailyLimitMinutes: widget.childDailyLimitMinutes,
      ),
    ));
    if (mounted) await _loadFavorites();
  }

  Future<void> _toggleFavorite(MediaItem item) async {
    final isFav = await _favoriteStore.toggle(
      profileId: widget.profileId,
      item: item,
    );
    if (!mounted) return;
    setState(() {
      if (isFav) {
        _favoriteItemIds.add(item.sourceItemId);
      } else {
        _favoriteItemIds.remove(item.sourceItemId);
      }
    });
  }

  List<SourceCatalogTab> _getPrimaryTabs() {
    final tabbed = _tabbedAdapter;
    if (tabbed != null) {
      return tabbed.primaryTabs
          .where((tab) =>
              widget.allowedCategories == null ||
              widget.allowedCategories!.contains(tab.category))
          .where((tab) => MediaAccessPolicy.allowsCategory(
                tab.category,
                context: _policyContext,
              ))
          .toList(growable: false);
    }
    const defaultCategories = [
      MediaCategory.drama,
      MediaCategory.movie,
      MediaCategory.animation,
      MediaCategory.documentary,
      MediaCategory.variety,
      MediaCategory.live,
      MediaCategory.other,
    ];
    return defaultCategories
        .where((cat) =>
            widget.allowedCategories == null ||
            widget.allowedCategories!.contains(cat))
        .where((cat) => MediaAccessPolicy.allowsCategory(
              cat,
              context: _policyContext,
            ))
        .map((cat) => SourceCatalogTab(
              id: cat.name,
              label: cat.label,
              category: cat,
            ))
        .toList(growable: false);
  }

  List<SourceCatalogTab> _getSubTabs() {
    final tabbed = _tabbedAdapter;
    if (tabbed == null || !tabbed.supportsSubtabs) return const [];
    return tabbed.subTabsFor(_selectedCategory, _items);
  }

  @override
  Widget build(BuildContext context) {
    final primaryTabs = _getPrimaryTabs();
    final subTabs = _getSubTabs();
    final scoped = _scopedAdapter;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.adapter.source.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Station / Scope selector banner (for TVBox multi-site sources)
          if (scoped != null && _scopes.isNotEmpty)
            _buildScopeSelector(scoped),

          // Primary category tabs
          if (primaryTabs.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: primaryTabs.map((tab) {
                  final isSelected = tab.category == _selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tab.label),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected && _selectedCategory != tab.category) {
                          setState(() {
                            _selectedCategory = tab.category;
                            _selectedSubcategoryId = null;
                          });
                          _refresh();
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

          // Subcategory filter chips
          if (subTabs.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('全部'),
                      selected: _selectedSubcategoryId == null,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedSubcategoryId = null);
                          _refresh();
                        }
                      },
                    ),
                  ),
                  ...subTabs.map((subTab) {
                    final isSelected = _selectedSubcategoryId == subTab.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(subTab.label),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedSubcategoryId = selected ? subTab.id : null;
                          });
                          _refresh();
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),

          const Divider(height: 1),

          // Main content grid
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeSelector(SourceCatalogScopes scoped) {
    final availableCount = _availableScopeIds?.length;
    final totalCount = _scopes.length;
    final scopeLabel = _filterAvailableOnly
        ? '站点（可用 $availableCount / 全部 $totalCount）'
        : '站点（$totalCount）';

    final currentScopeId = scoped.selectedCatalogScopeId;
    final currentScope = currentScopeId != null
        ? _scopes.where((s) => s.id == currentScopeId).firstOrNull
        : null;
    final currentLabel = currentScope != null
        ? '${currentScope.label} · ${currentScope.sourceKey}'
        : '自动选择可用站点';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(
        children: [
          Text(
            scopeLabel,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(width: 12),
          ChoiceChip(
            label: const Text('全部站点', style: TextStyle(fontSize: 12)),
            selected: !_filterAvailableOnly,
            onSelected: (selected) {
              if (selected) _toggleAvailableScopesFilter(false);
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('可用站点', style: TextStyle(fontSize: 12)),
            selected: _filterAvailableOnly,
            onSelected: (selected) {
              if (selected) _toggleAvailableScopesFilter(true);
            },
          ),
          const Spacer(),
          PopupMenuButton<String?>(
            initialValue: currentScopeId,
            tooltip: '切换站点',
            onSelected: _onScopeSelected,
            itemBuilder: (context) {
              final visibleScopes = _filterAvailableOnly && _availableScopeIds != null
                  ? _scopes
                      .where((s) => _availableScopeIds!.contains(s.id))
                      .toList()
                  : _scopes;
              return [
                const PopupMenuItem<String?>(
                  value: null,
                  child: Text('自动选择可用站点'),
                ),
                ...visibleScopes.map((scope) => PopupMenuItem<String?>(
                      value: scope.id,
                      child: Text('${scope.label} · ${scope.sourceKey}'),
                    )),
              ];
            },
            child: Chip(
              avatar: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: Text(
                currentLabel,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.amber),
              const SizedBox(height: 12),
              Text('加载失败：$_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text('当前分类暂无内容'),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.68,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _items.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final item = _items[index];
        final isFav = _favoriteItemIds.contains(item.sourceItemId);
        return _MediaCard(
          item: item,
          isFavorite: isFav,
          onTap: () => _openDetail(item),
          onToggleFavorite: () => _toggleFavorite(item),
        );
      },
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.item,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final MediaItem item;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLive = item.category == MediaCategory.live;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.posterUri != null
                      ? Image.network(
                          item.posterUri.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainer,
                            child: Icon(
                              isLive
                                  ? Icons.live_tv_rounded
                                  : Icons.movie_creation_outlined,
                              size: 40,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainer,
                          child: Icon(
                            isLive
                                ? Icons.live_tv_rounded
                                : Icons.movie_creation_outlined,
                            size: 40,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.3),
                          ),
                        ),
                  // Dark gradient overlay
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x88000000)],
                          stops: [0.6, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Favorite button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: Icon(
                        isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isFavorite ? Colors.redAccent : Colors.white70,
                        size: 18,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.all(6),
                        minimumSize: const Size(32, 32),
                      ),
                      onPressed: onToggleFavorite,
                    ),
                  ),
                  // Live badge
                  if (isLive)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fiber_manual_record,
                                size: 7, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              '直播',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.sourceSubcategoryLabel ??
                        item.sourceCategoryLabel ??
                        item.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
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
}