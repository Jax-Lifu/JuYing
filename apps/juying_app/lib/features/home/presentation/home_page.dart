import 'dart:async';
import 'package:flutter/material.dart';

import '../../../application/favorites/favorite_store.dart';
import '../../../application/playback/playback_history_store.dart';
import '../../../application/playback/playback_launcher.dart';
import '../../../application/playback/playback_preference_store.dart';
import '../../../application/policy/media_access_policy.dart';
import '../../../application/policy/source_policy.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/app_strings.dart';
import '../../../domain/models/favorite_media.dart';
import '../../../domain/models/media_source.dart';
import '../../../domain/models/playback_history.dart';
import '../../../domain/models/unified_media.dart' hide MediaCatalogPage;
import '../../../domain/ports/media_source_adapter.dart';
import '../../media/presentation/media_catalog_page.dart';
import '../../media/presentation/media_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.config,
    required this.adapters,
    required this.historyStore,
    required this.playbackLauncher,
    required this.profileId,
    required this.isChildProfile,
    this.childDailyLimitMinutes,
    required this.onOpenProfiles,
    required this.onRetrySource,
    this.onNavigateTab,
    super.key,
  });

  final AppConfig config;
  final List<MediaSourceAdapter> adapters;
  final PlaybackHistoryStore historyStore;
  final PlaybackLauncher playbackLauncher;
  final String profileId;
  final bool isChildProfile;
  final int? childDailyLimitMinutes;
  final VoidCallback onOpenProfiles;
  final VoidCallback onRetrySource;
  final ValueChanged<int>? onNavigateTab;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FavoriteStore _favoriteStore = FavoriteStore();
  final PlaybackPreferenceStore _preferenceStore = PlaybackPreferenceStore();
  late Future<List<PlaybackHistoryEntry>> _history =
      widget.historyStore.load(profileId: widget.profileId);
  late Future<List<FavoriteMedia>> _favorites =
      _favoriteStore.load(widget.profileId);

  void _reloadHistory() => setState(() {
        _history = widget.historyStore.load(profileId: widget.profileId);
        _favorites = _favoriteStore.load(widget.profileId);
      });

  MediaSourceAdapter get _defaultAdapter => widget.adapters.first;

  MediaSourceAdapter? get _liveAdapter => widget.adapters
      .where((a) =>
          a.source.id == 'cctv-live-official' ||
          a.source.capabilities.contains(SourceCapability.liveCatalog))
      .firstOrNull;

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) _reloadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        // App Header
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            strings.appName,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.flash_on_rounded,
                                    color: theme.colorScheme.primary, size: 13),
                                const SizedBox(width: 2),
                                Text(
                                  'PRO',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.frameworkPreview,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => widget.onNavigateTab?.call(1),
                  tooltip: '搜索影片与频道',
                  icon: const Icon(Icons.search_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: widget.onOpenProfiles,
                  tooltip: '切换家庭成员',
                  icon: const Icon(Icons.person_rounded),
                ),
              ],
            ),
          ),
        ),

        // Spotlight Hero Banner
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          sliver: SliverToBoxAdapter(
            child: _Spotlight(
              config: widget.config,
              adapter: _defaultAdapter,
              liveAdapter: _liveAdapter,
              profileId: widget.profileId,
              isChildProfile: widget.isChildProfile,
              childDailyLimitMinutes: widget.childDailyLimitMinutes,
              onRetrySource: widget.onRetrySource,
              onOpenLive: _openLiveDirectly,
              playbackLauncher: widget.playbackLauncher,
            ),
          ),
        ),

        // Section: Continue Watching
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(28, 16, 28, 10),
          sliver: SliverToBoxAdapter(
            child: _SectionHeader(title: '继续观看', icon: Icons.history_rounded),
          ),
        ),
        SliverToBoxAdapter(
          child: _ContinueWatching(
            history: _history,
            onRetry: _reloadHistory,
            onOpen: _openHistory,
          ),
        ),

        // Section: My Favorites
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(28, 26, 28, 10),
          sliver: SliverToBoxAdapter(
            child: _SectionHeader(
                title: '我的收藏', icon: Icons.favorite_border_rounded),
          ),
        ),
        SliverToBoxAdapter(
          child: _Favorites(
            favorites: _favorites,
            isChildProfile: widget.isChildProfile,
            onOpen: _openFavorite,
          ),
        ),

        // Section: Family & Quick Space
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(28, 26, 28, 12),
          sliver: SliverToBoxAdapter(
            child:
                _SectionHeader(title: '快捷空间', icon: Icons.dashboard_rounded),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 36),
          sliver: SliverToBoxAdapter(
            child: _QuickActions(
              onOpenLive: _openLiveDirectly,
              onOpenProfiles: widget.onOpenProfiles,
              onNavigateTab: widget.onNavigateTab,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openHistory(PlaybackHistoryEntry entry) async {
    final adapter = _adapterFor(entry.sourceId);
    if (adapter == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该观看记录的来源已被移除')),
        );
      }
      return;
    }
    final policyContext =
        MediaAccessContext(isChildProfile: widget.isChildProfile);
    final episode = MediaEpisode(
      sourceId: entry.sourceId,
      sourceEpisodeId: entry.sourceEpisodeId,
      title: entry.title,
      officialPageUri: entry.officialPageUri,
    );
    final nativeAllowed = MediaAccessPolicy.evaluateSource(
      adapter.source,
      SourceAction.nativePlayback,
      context: policyContext,
      explicitSourceSelection: true,
    );
    if (nativeAllowed.allowed) {
      try {
        final playback = await adapter.resolvePlayback(episode);
        if (playback.nativeStreamUri != null && mounted) {
          await widget.playbackLauncher.launchNative(
            context,
            PlaybackLaunchRequest(
              playback: playback,
              episodes: const [],
              resolveEpisode: adapter.resolvePlayback,
              profileId: widget.profileId,
              sourceCapabilities: adapter.source.capabilities,
              childDailyLimitMinutes: widget.childDailyLimitMinutes,
            ),
          );
          return;
        }
      } catch (_) {}
    }
    final fallbackAllowed = MediaAccessPolicy.evaluateSource(
      adapter.source,
      SourceAction.officialFallback,
      context: policyContext,
      explicitSourceSelection: true,
    );
    if (!fallbackAllowed.allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(fallbackAllowed.reason ?? '当前来源不可续播')),
        );
      }
      return;
    }
    try {
      final playback = await adapter.resolveOfficialFallback(episode);
      if (!mounted) return;
      await widget.playbackLauncher.launchOfficial(
        context,
        PlaybackLaunchRequest(
          playback: playback,
          episodes: const [],
          resolveEpisode: adapter.resolveOfficialFallback,
          profileId: widget.profileId,
          sourceCapabilities: adapter.source.capabilities,
          childDailyLimitMinutes: widget.childDailyLimitMinutes,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法恢复该观看记录')),
        );
      }
    }
  }

  MediaSourceAdapter? _adapterFor(String sourceId) {
    for (final adapter in widget.adapters) {
      if (adapter.source.id == sourceId) return adapter;
    }
    return null;
  }

  Future<void> _openFavorite(FavoriteMedia favorite) async {
    final adapter = _adapterFor(favorite.sourceId);
    if (adapter == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该收藏的来源已被移除')),
        );
      }
      return;
    }
    final item = MediaItem(
      sourceId: favorite.sourceId,
      sourceItemId: favorite.sourceItemId,
      title: favorite.title,
      category: favorite.category,
      officialDetailUri: favorite.officialDetailUri,
      defaultEpisodePageUri: favorite.defaultEpisodePageUri,
      posterUri: favorite.posterUri,
    );
    if (!MediaAccessPolicy.evaluateItem(
      adapter.source,
      item,
      SourceAction.episodes,
      context: MediaAccessContext(isChildProfile: widget.isChildProfile),
      explicitSourceSelection: true,
    ).allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前儿童档案不可浏览该内容')),
        );
      }
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MediaDetailPage(
        item: item,
        adapter: adapter,
        profileId: widget.profileId,
        isChildProfile: widget.isChildProfile,
        playbackLauncher: widget.playbackLauncher,
        childDailyLimitMinutes: widget.childDailyLimitMinutes,
      ),
    ));
    if (mounted) _reloadHistory();
  }

  Future<void> _openLiveDirectly([MediaSourceAdapter? targetAdapter]) async {
    final adapter = targetAdapter ?? _liveAdapter;
    if (adapter == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无可用直播来源')),
        );
      }
      return;
    }

    final decision = MediaAccessPolicy.evaluateSource(
      adapter.source,
      SourceAction.browse,
      context: MediaAccessContext(isChildProfile: widget.isChildProfile),
      explicitSourceSelection: true,
    );
    if (!decision.allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(decision.reason ?? '当前档案不可浏览该直播来源')),
        );
      }
      return;
    }

    try {
      final page = await adapter.browse(
        const MediaCatalogQuery(category: MediaCategory.live, pageSize: 500),
      );
      if (!mounted) return;
      if (page.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该直播来源暂无可用频道')),
        );
        return;
      }

      final lastChannelId = await _preferenceStore.getLastLiveChannel(
        profileId: widget.profileId,
        sourceId: adapter.source.id,
      );

      MediaItem? targetItem;
      if (lastChannelId != null) {
        targetItem = page.items
            .where((item) => item.sourceItemId == lastChannelId)
            .firstOrNull;
      }
      targetItem ??= page.items.where((item) {
        final id = item.sourceItemId.toLowerCase();
        final title = item.title.toLowerCase();
        return id == 'cctv1' ||
            id.contains('cctv-1') ||
            title.contains('cctv-1') ||
            title.contains('cctv1') ||
            title.contains('cctv 1');
      }).firstOrNull;
      targetItem ??= page.items.first;

      final allEpisodes = page.items
          .map((item) => MediaEpisode(
                sourceId: item.sourceId,
                sourceEpisodeId: item.sourceItemId,
                title: item.title,
                posterUri: item.posterUri,
                officialPageUri: item.defaultEpisodePageUri,
              ))
          .toList(growable: false);

      final targetEpisode = allEpisodes.firstWhere(
        (ep) => ep.sourceEpisodeId == targetItem!.sourceItemId,
        orElse: () => allEpisodes.first,
      );

      final nativeDecision = MediaAccessPolicy.evaluateSource(
        adapter.source,
        SourceAction.nativePlayback,
        context: MediaAccessContext(isChildProfile: widget.isChildProfile),
        explicitSourceSelection: true,
      );

      if (nativeDecision.allowed) {
        try {
          final playback = await adapter.resolvePlayback(targetEpisode);
          if (playback.nativeStreamUri != null && mounted) {
            await widget.playbackLauncher.launchNative(
              context,
              PlaybackLaunchRequest(
                playback: playback,
                episodes: allEpisodes,
                resolveEpisode: adapter.resolvePlayback,
                profileId: widget.profileId,
                sourceCapabilities: adapter.source.capabilities,
                childDailyLimitMinutes: widget.childDailyLimitMinutes,
              ),
            );
            return;
          }
        } catch (_) {}
      }

      final fallbackDecision = MediaAccessPolicy.evaluateSource(
        adapter.source,
        SourceAction.officialFallback,
        context: MediaAccessContext(isChildProfile: widget.isChildProfile),
        explicitSourceSelection: true,
      );

      if (fallbackDecision.allowed) {
        try {
          final playback =
              await adapter.resolveOfficialFallback(targetEpisode);
          if (mounted) {
            await widget.playbackLauncher.launchOfficial(
              context,
              PlaybackLaunchRequest(
                playback: playback,
                episodes: allEpisodes,
                resolveEpisode: adapter.resolveOfficialFallback,
                profileId: widget.profileId,
                sourceCapabilities: adapter.source.capabilities,
                childDailyLimitMinutes: widget.childDailyLimitMinutes,
              ),
            );
            return;
          }
        } catch (_) {}
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载直播失败：$error')),
        );
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Spotlight extends StatelessWidget {
  const _Spotlight({
    required this.config,
    required this.adapter,
    this.liveAdapter,
    required this.profileId,
    required this.isChildProfile,
    this.childDailyLimitMinutes,
    required this.onRetrySource,
    required this.onOpenLive,
    required this.playbackLauncher,
  });

  final AppConfig config;
  final MediaSourceAdapter adapter;
  final MediaSourceAdapter? liveAdapter;
  final String profileId;
  final bool isChildProfile;
  final int? childDailyLimitMinutes;
  final VoidCallback onRetrySource;
  final Future<void> Function([MediaSourceAdapter? targetAdapter]) onOpenLive;
  final PlaybackLauncher playbackLauncher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 260),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.28),
            const Color(0xFF141720),
            const Color(0xFF0D0F14),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fiber_manual_record,
                            color: Colors.redAccent, size: 8),
                        SizedBox(width: 6),
                        Text(
                          '官方旗舰 · 电视直播与全网片库',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '中央广播电视总台 · CCTV 直播',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '直连 CCTV-1 ~ CCTV-17 原生高清 HLS 流媒体，支持画幅切换、数字选台与频道记忆。',
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => onOpenLive(liveAdapter),
                        icon: const Icon(Icons.play_circle_fill_rounded,
                            size: 20),
                        label: const Text('进入电视直播'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
                          elevation: 8,
                          shadowColor:
                              theme.colorScheme.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _sourceCanBrowse(adapter)
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => MediaCatalogPage(
                                      adapter: adapter,
                                      profileId: profileId,
                                      isChildProfile: isChildProfile,
                                      playbackLauncher: playbackLauncher,
                                      childDailyLimitMinutes:
                                          childDailyLimitMinutes,
                                    ),
                                  ),
                                )
                            : onRetrySource,
                        icon: const Icon(Icons.grid_view_rounded, size: 18),
                        label: Text(_sourceCanBrowse(adapter)
                            ? '浏览 CCTV 片库'
                            : '恢复来源后重试'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (constraints.maxWidth > 580) ...[
              const SizedBox(width: 32),
              Expanded(
                flex: 2,
                child: Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => onOpenLive(liveAdapter),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Icon(
                        Icons.live_tv_rounded,
                        size: 96,
                        color: theme.colorScheme.primary.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  bool _sourceCanBrowse(MediaSourceAdapter adapter) =>
      adapter.source.isActive &&
      adapter.source.health != SourceHealth.unavailable;
}

class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching({
    required this.history,
    required this.onRetry,
    required this.onOpen,
  });

  final Future<List<PlaybackHistoryEntry>> history;
  final VoidCallback onRetry;
  final ValueChanged<PlaybackHistoryEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlaybackHistoryEntry>>(
      future: history,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return SizedBox(
            height: 120,
            child: Center(
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新加载观看记录'),
              ),
            ),
          );
        }
        final entries = snapshot.requireData.take(12).toList(growable: false);
        if (entries.isEmpty) {
          return Container(
            height: 110,
            margin: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.movie_outlined, color: Colors.white38, size: 24),
                  SizedBox(width: 10),
                  Text('播放节目后，会在这里记录观看进度与自动续播',
                      style: TextStyle(color: Colors.white60)),
                ],
              ),
            ),
          );
        }
        return SizedBox(
          height: 168,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, index) => _HistoryCard(
              entry: entries[index],
              onTap: () => onOpen(entries[index]),
            ),
          ),
        );
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry, required this.onTap});
  final PlaybackHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = entry.duration ?? Duration.zero;
    final progress = duration > Duration.zero
        ? (entry.position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with Progress bar
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  entry.posterUri == null
                      ? Container(
                          color: theme.colorScheme.surfaceContainer,
                          child: Center(
                            child: Icon(Icons.movie_rounded,
                                size: 36,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.3)),
                          ),
                        )
                      : Image.network(
                          entry.posterUri.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainer,
                            child: const Center(
                                child: Icon(Icons.movie_rounded, size: 36)),
                          ),
                        ),
                  // Gradient Overlay
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x99000000)],
                        ),
                      ),
                    ),
                  ),
                  // Center play icon
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black45,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 24),
                    ),
                  ),
                  // Bottom Progress Bar
                  if (progress > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary),
                      ),
                    ),
                ],
              ),
            ),
            // Title & Position
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '已播至 ${_formatDuration(entry.position)}',
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

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Favorites extends StatelessWidget {
  const _Favorites({
    required this.favorites,
    required this.isChildProfile,
    required this.onOpen,
  });

  final Future<List<FavoriteMedia>> favorites;
  final bool isChildProfile;
  final ValueChanged<FavoriteMedia> onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FavoriteMedia>>(
      future: favorites,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final entries = (snapshot.data ?? const <FavoriteMedia>[])
            .where(
              (favorite) => MediaAccessPolicy.allowsCategory(
                favorite.category,
                context: MediaAccessContext(isChildProfile: isChildProfile),
              ),
            )
            .take(12)
            .toList(growable: false);

        if (entries.isEmpty) {
          return Container(
            height: 100,
            margin: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_outline_rounded,
                      color: Colors.white38, size: 24),
                  SizedBox(width: 10),
                  Text('在影片详情中点击收藏，即可在这里快速访问',
                      style: TextStyle(color: Colors.white60)),
                ],
              ),
            ),
          );
        }

        return SizedBox(
          height: 168,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, index) => _FavoriteCard(
              favorite: entries[index],
              onTap: () => onOpen(entries[index]),
            ),
          ),
        );
      },
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.favorite, required this.onTap});
  final FavoriteMedia favorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
                  favorite.posterUri == null
                      ? Container(
                          color: theme.colorScheme.surfaceContainer,
                          child: Center(
                            child: Icon(Icons.favorite_rounded,
                                size: 36,
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.5)),
                          ),
                        )
                      : Image.network(
                          favorite.posterUri.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainer,
                            child: const Center(
                                child: Icon(Icons.favorite_rounded, size: 36)),
                          ),
                        ),
                  // Tag
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        favorite.category.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
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
                    favorite.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '来源：${favorite.sourceId}',
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

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onOpenLive,
    required this.onOpenProfiles,
    this.onNavigateTab,
  });

  final VoidCallback onOpenLive;
  final VoidCallback onOpenProfiles;
  final ValueChanged<int>? onNavigateTab;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 720;
      return GridView.count(
        crossAxisCount: isWide ? 4 : 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: isWide ? 1.9 : 1.6,
        children: [
          _ActionCard(
            icon: Icons.live_tv_rounded,
            title: '电视直播',
            subtitle: '央视与卫视直连换台',
            accentColor: const Color(0xFFFA3E3E),
            onTap: onOpenLive,
          ),
          _ActionCard(
            icon: Icons.child_care_rounded,
            title: '儿童空间',
            subtitle: '分级过滤与使用时限',
            accentColor: const Color(0xFFFFA000),
            onTap: onOpenProfiles,
          ),
          _ActionCard(
            icon: Icons.dns_rounded,
            title: '家庭 NAS',
            subtitle: 'Samba / NFS / WebDAV',
            accentColor: const Color(0xFF00B0FF),
            onTap: () => onNavigateTab?.call(3),
          ),
          _ActionCard(
            icon: Icons.tune_rounded,
            title: '来源配置',
            subtitle: 'TVBox、IPTV 与诊断',
            accentColor: const Color(0xFF7C4DFF),
            onTap: () => onNavigateTab?.call(4),
          ),
        ],
      );
    });
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: accentColor.withValues(alpha: 0.3), width: 1),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
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
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
