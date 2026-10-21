import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/core/history/playback_history_service.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';
import 'package:juying/features/download/presentation/download_page.dart';
import 'package:juying/features/download/services/offline_download_manager.dart';
import 'package:juying/features/player/presentation/cctv_official_web_player_page.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';
import 'package:juying/features/player/presentation/web_media_resolver.dart';
import 'package:juying/features/tvbox/providers/tvbox_provider.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// Media detail page showcasing canonical metadata and decoupled multi-source TVBox/CCTV candidates.
///
/// **What**: Displays TMDB/Douban canonical identity (posters, cast, synopsis, genres)
/// alongside multiple candidate playback lines ([PlaybackCandidate]), episode matrix, and offline download caching.
///
/// **Why**: Media aggregation clients decouple canonical media identity from candidate streaming sources.
/// Users can switch between 4K official feeds, TVBox spider lines, and backup routes without losing viewing state.
class VideoDetailPage extends ConsumerStatefulWidget {
  const VideoDetailPage({
    super.key,
    required this.mediaItem,
    this.candidates = const <PlaybackCandidate>[],
  });

  final MediaItem mediaItem;
  final List<PlaybackCandidate> candidates;

  @override
  ConsumerState<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends ConsumerState<VideoDetailPage> {
  int _selectedCandidateIndex = 0;
  List<PlaybackCandidate> _effectiveCandidates = <PlaybackCandidate>[];
  bool _isLoadingEpisodes = true;
  bool _isLoadingHistory = true;
  String? _episodeLoadError;
  PlaybackHistoryItem? _lastPlayback;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlaybackHistory());
    unawaited(_loadCandidateEpisodes());
  }

  Future<void> _loadPlaybackHistory() async {
    final history = await PlaybackHistoryService.instance.findLatestForMedia(
      mediaId: widget.mediaItem.id,
      title: widget.mediaItem.title,
    );
    if (mounted) {
      setState(() {
        _lastPlayback = history;
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _loadCandidateEpisodes() async {
    if (widget.candidates.isNotEmpty) {
      setState(() {
        _effectiveCandidates = widget.candidates;
        _isLoadingEpisodes = false;
      });
      return;
    }

    if (widget.mediaItem.id.startsWith('cctv_album_')) {
      final albumId = widget.mediaItem.id.replaceFirst('cctv_album_', '');
      final cctvCandidate = await CctvApiService().fetchAlbumEpisodes(albumId);
      final list = <PlaybackCandidate>[];
      if (cctvCandidate != null) {
        list.add(cctvCandidate);
      }
      if (mounted) {
        setState(() {
          _effectiveCandidates = list;
          _isLoadingEpisodes = false;
        });
      }
      return;
    }

    final activeSite = ref.read(activeTvBoxSiteProvider);
    final spiderEngine = TvBoxSpiderEngine();

    try {
      final resolvedCandidates =
          await spiderEngine.fetchMediaCandidates(activeSite, widget.mediaItem);

      if (mounted) {
        setState(() {
          _effectiveCandidates = resolvedCandidates;
          _isLoadingEpisodes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _episodeLoadError = '无法从站点加载剧集: $e';
          _isLoadingEpisodes = false;
        });
      }
    }
  }

  Future<void> _playEpisode(PlaybackEpisode episode,
      {bool resume = false}) async {
    if (_effectiveCandidates.isEmpty) return;
    final initialPosition = resume ? _resumePosition(episode) : Duration.zero;
    _rememberEpisode(episode, position: initialPosition);
    final candidate = _effectiveCandidates[_selectedCandidateIndex];
    final officialPageUrl = episode.officialPageUrl;
    final useNativeCctv = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        episode.url.startsWith('cctv_guid://');
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => officialPageUrl != null && !useNativeCctv
            ? CctvOfficialWebPlayerPage(
                title: widget.mediaItem.title,
                currentEpisode: episode,
                initialPosition: initialPosition,
                episodes: candidate.episodes,
                onEpisodeChanged: _rememberEpisode,
              )
            : VideoPlayerPage(
                title: widget.mediaItem.title,
                currentEpisode: episode,
                initialPosition: initialPosition,
                mediaId: widget.mediaItem.id,
                posterUrl: episode.thumbnailUrl ?? widget.mediaItem.posterUrl,
                candidate: candidate,
                allCandidates: _effectiveCandidates,
                onEpisodeChanged: _rememberEpisode,
              ),
      ),
    );
    if (mounted) await _loadPlaybackHistory();
  }

  /// 只有明确续播同一集且保存位置仍在有效时长内，才恢复偏移。
  Duration _resumePosition(PlaybackEpisode episode) {
    final history = _lastPlayback;
    if (history == null || !_matchesHistory(episode)) {
      return Duration.zero;
    }
    final durationMs = episode.duration > Duration.zero
        ? episode.duration.inMilliseconds
        : history.durationMs;
    return history.positionMs > 0 && history.positionMs < durationMs
        ? Duration(milliseconds: history.positionMs)
        : Duration.zero;
  }

  PlaybackEpisode _resumeEpisode(PlaybackCandidate candidate) {
    return candidate.episodes.firstWhere(
      _matchesHistory,
      orElse: () => candidate.episodes.first,
    );
  }

  bool _matchesHistory(PlaybackEpisode episode) {
    final history = _lastPlayback;
    return history != null &&
        episode.matchesIdentity(
          name: history.episodeName,
          sortIndex: history.episodeIndex,
        );
  }

  /// 选择剧集即记录，WebView 内选集与自动连播也通过回调进入同一条链路。
  void _rememberEpisode(PlaybackEpisode episode, {Duration? position}) {
    final previous = _lastPlayback;
    final sameEpisode = _matchesHistory(episode);
    final history = PlaybackHistoryItem(
      id: widget.mediaItem.id,
      title: widget.mediaItem.title,
      posterUrl: widget.mediaItem.posterUrl ?? '',
      episodeName: episode.name,
      episodeIndex: episode.sortIndex,
      positionMs:
          position?.inMilliseconds ?? (sameEpisode ? previous!.positionMs : 0),
      durationMs: episode.duration.inMilliseconds > 0
          ? episode.duration.inMilliseconds
          : sameEpisode
              ? previous!.durationMs
              : 0,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (mounted) setState(() => _lastPlayback = history);
    unawaited(PlaybackHistoryService.instance.saveHistory(history));
  }

  String _downloadTaskId(PlaybackEpisode episode) =>
      '${widget.mediaItem.id}_ep${episode.sortIndex}';

  Future<void> _enqueueDownloadEpisodes(
    List<PlaybackEpisode> episodes,
  ) async {
    final manager = OfflineDownloadManager.instance;
    final pending = episodes.where((episode) {
      final id = _downloadTaskId(episode);
      return !manager.tasks.any((task) => task.id == id);
    }).toList(growable: false);
    if (pending.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在准备 ${pending.length} 集缓存任务…')),
    );
    final docDir = await getApplicationDocumentsDirectory();
    final downloadPath =
        '${docDir.path}${Platform.pathSeparator}juying_downloads';
    var queuedCount = 0;
    var failedCount = 0;

    // CCTV 的 GUID 需要逐集换取当前有效地址；串行解析避免批量选择时瞬间
    // 冲击 VDN 接口，实际切片下载仍由下载管理器并发执行。
    for (final episode in pending) {
      if (!mounted) return;
      final taskId = _downloadTaskId(episode);
      if (manager.tasks.any((task) => task.id == taskId)) continue;
      try {
        var resolvedEpisode = episode.resolvePlayback == null
            ? episode
            : await episode.resolvePlayback!();
        if (!mounted) return;
        if (resolvedEpisode.requiresWebView) {
          resolvedEpisode = await resolveWebMedia(context, resolvedEpisode);
        }
        if (!mounted) return;
        var playUrl = resolvedEpisode.url;
        if (playUrl.startsWith('cctv_guid://')) {
          final guid = playUrl.replaceFirst('cctv_guid://', '');
          final resolved = await CctvApiService().resolveCctvGuid(guid);
          if (resolved == null || resolved.isEmpty) {
            failedCount++;
            continue;
          }
          playUrl = resolved;
        }
        if (!mounted) return;
        manager.enqueueTask(
          id: taskId,
          title: widget.mediaItem.title,
          episodeName: episode.name,
          m3u8Url: playUrl,
          headers: resolvedEpisode.headers,
          targetDirectory: downloadPath,
        );
        queuedCount++;
      } on WebMediaResolutionCancelled {
        break;
      } catch (_) {
        failedCount++;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context
            .tr('download_prepare_result')
            .replaceAll('{queued}', '$queuedCount')
            .replaceAll('{failed}', '$failedCount')),
        action: SnackBarAction(
          label: '查看下载',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const DownloadPage(),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showDownloadModal(PlaybackCandidate candidate) async {
    final docDir = await getApplicationDocumentsDirectory();
    final downloadPath =
        '${docDir.path}${Platform.pathSeparator}juying_downloads';
    final cachedIds = <String>{};
    for (final episode in candidate.episodes) {
      final taskId = _downloadTaskId(episode);
      final outputFile = File(
        '$downloadPath${Platform.pathSeparator}$taskId'
        '${Platform.pathSeparator}$taskId.mp4',
      );
      if (await outputFile.exists()) cachedIds.add(taskId);
    }
    if (!mounted) return;

    final selected = await showModalBottomSheet<List<PlaybackEpisode>>(
      context: context,
      backgroundColor: context.colors.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _DownloadEpisodeSelectionSheet(
        mediaId: widget.mediaItem.id,
        episodes: candidate.episodes,
        cachedIds: cachedIds,
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _enqueueDownloadEpisodes(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeCandidate = _effectiveCandidates.isNotEmpty
        ? _effectiveCandidates[_selectedCandidateIndex]
        : null;

    return Scaffold(
      backgroundColor: colors.backgroundDeep,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Blurred Backdrop Image
          if (widget.mediaItem.backdropUrl != null ||
              widget.mediaItem.posterUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.15,
                child: Image.network(
                  widget.mediaItem.backdropUrl ?? widget.mediaItem.posterUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),

          // Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    colors.backgroundDeep.withAlpha(200),
                    colors.backgroundDeep,
                  ],
                ),
              ),
            ),
          ),

          // Content Scroll View
          SafeArea(
            child: CustomScrollView(
              slivers: <Widget>[
                SliverAppBar(
                  pinned: true,
                  backgroundColor: colors.backgroundDeep.withAlpha(245),
                  foregroundColor: colors.textPrimary,
                  elevation: 0,
                  scrolledUnderElevation: 4,
                  leading: IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  title: Text(
                    widget.mediaItem.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  actions: <Widget>[
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => const DownloadPage(),
                          ),
                        );
                      },
                      icon: Icon(
                        Icons.download_rounded,
                        size: 17,
                        color: colors.brandAccent,
                      ),
                      label: Text(
                        '离线缓存',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),

                // Hero Metadata Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Poster Card
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 180,
                            height: 250,
                            child: widget.mediaItem.posterUrl != null
                                ? Image.network(
                                    widget.mediaItem.posterUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: colors.surfaceElevation,
                                      child: Icon(Icons.movie,
                                          color: colors.textTertiary, size: 48),
                                    ),
                                  )
                                : Container(
                                    color: colors.surfaceElevation,
                                    child: Icon(Icons.movie,
                                        color: colors.textTertiary, size: 48),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 24),

                        // Title, Year, Genres, Cast, Description
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                widget.mediaItem.title,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  if (widget.mediaItem.rating != null &&
                                      widget.mediaItem.rating! > 0) ...<Widget>[
                                    Icon(Icons.star,
                                        size: 18, color: colors.brandAccent),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.mediaItem.rating!
                                          .toStringAsFixed(1),
                                      style: TextStyle(
                                        color: colors.brandAccent,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  if (widget.mediaItem.year !=
                                      null) ...<Widget>[
                                    Text(
                                      widget.mediaItem.year!,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  if (widget.mediaItem.totalEpisodes != null &&
                                      widget.mediaItem.totalEpisodes! > 0)
                                    Text(
                                      '${widget.mediaItem.totalEpisodes} 集全',
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 14,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Genres Pills
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: <Widget>[
                                  for (final g in widget.mediaItem.genres)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colors.surfaceElevation,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        g,
                                        style: TextStyle(
                                          color: colors.textTertiary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Overview text
                              Text(
                                widget.mediaItem.overview ??
                                    context.tr('detail_no_overview'),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Quick Play and Download Buttons Row
                              if (!_isLoadingEpisodes &&
                                  !_isLoadingHistory &&
                                  activeCandidate != null &&
                                  activeCandidate.episodes.isNotEmpty)
                                Row(
                                  children: <Widget>[
                                    TvFocusWrapper(
                                      autofocus: true,
                                      onTap: () => _playEpisode(
                                        _resumeEpisode(activeCandidate),
                                        resume: true,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: colors.brandPrimary,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            const Icon(Icons.play_arrow,
                                                color: Colors.white),
                                            const SizedBox(width: 6),
                                            Text(
                                              _lastPlayback == null
                                                  ? context.tr('home_play_now')
                                                  : '继续播放 ${_resumeEpisode(activeCandidate).shortName}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    TvFocusWrapper(
                                      onTap: () =>
                                          _showDownloadModal(activeCandidate),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: colors.surfaceElevation,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: colors.brandAccent
                                                  .withAlpha(100)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            Icon(Icons.download_outlined,
                                                color: colors.brandAccent),
                                            const SizedBox(width: 6),
                                            Text(
                                              '缓存下载',
                                              style: TextStyle(
                                                color: colors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
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
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 28),
                ),

                // TVBox Source & Route Selector Tabs
                if (_effectiveCandidates.length > 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            context.tr('detail_source_lines'),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 44,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _effectiveCandidates.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final candidate = _effectiveCandidates[index];
                                final isSelected =
                                    _selectedCandidateIndex == index;

                                return TvFocusWrapper(
                                  onTap: () {
                                    setState(() {
                                      _selectedCandidateIndex = index;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? colors.brandPrimary
                                          : colors.surfaceElevation,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? colors.focusBorder
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          Icons.live_tv_outlined,
                                          size: 16,
                                          color: isSelected
                                              ? Colors.white
                                              : colors.textSecondary,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${candidate.sourceName} · ${candidate.lineName} · ${candidate.episodes.length}集',
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : colors.textPrimary,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            fontSize: 13,
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
                      ),
                    ),
                  ),

                if (_effectiveCandidates.length > 1)
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 24),
                  ),

                // Episode Grid Matrix
                if (_isLoadingEpisodes)
                  const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  )
                else if (_episodeLoadError != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _episodeLoadError!,
                        style: TextStyle(color: colors.statusError),
                      ),
                    ),
                  )
                else if (activeCandidate != null)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 240,
                        mainAxisExtent: 158,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final ep = activeCandidate.episodes[index];
                          final isLastPlayed = _matchesHistory(ep);
                          return TvFocusWrapper(
                            onTap: () => _playEpisode(ep),
                            child: _DetailEpisodeCard(
                              episode: ep,
                              isLastPlayed: isLastPlayed,
                              colors: colors,
                            ),
                          );
                        },
                        childCount: activeCandidate.episodes.length,
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 48),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadEpisodeSelectionSheet extends StatefulWidget {
  const _DownloadEpisodeSelectionSheet({
    required this.mediaId,
    required this.episodes,
    required this.cachedIds,
  });

  final String mediaId;
  final List<PlaybackEpisode> episodes;
  final Set<String> cachedIds;

  @override
  State<_DownloadEpisodeSelectionSheet> createState() =>
      _DownloadEpisodeSelectionSheetState();
}

class _DownloadEpisodeSelectionSheetState
    extends State<_DownloadEpisodeSelectionSheet> {
  final Set<int> _selectedIndexes = <int>{};
  final OfflineDownloadManager _manager = OfflineDownloadManager.instance;

  String _taskId(PlaybackEpisode episode) =>
      '${widget.mediaId}_ep${episode.sortIndex}';

  DownloadTask? _taskFor(List<DownloadTask> tasks, PlaybackEpisode episode) {
    final taskId = _taskId(episode);
    for (final task in tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  String _statusLabel(DownloadTask task) {
    return switch (task.status) {
      DownloadTaskStatus.queued => '已排队',
      DownloadTaskStatus.downloading =>
        '缓存中 ${(task.progress * 100).toStringAsFixed(0)}%',
      DownloadTaskStatus.paused => '已暂停',
      DownloadTaskStatus.completed => '已缓存',
      DownloadTaskStatus.failed => '缓存失败',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: StreamBuilder<List<DownloadTask>>(
          stream: _manager.tasksStream,
          initialData: _manager.tasks,
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? <DownloadTask>[];
            final selectableIndexes = <int>[
              for (var index = 0; index < widget.episodes.length; index++)
                if (!widget.cachedIds
                        .contains(_taskId(widget.episodes[index])) &&
                    _taskFor(tasks, widget.episodes[index]) == null)
                  index,
            ];
            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '选择要缓存下载的分集',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: selectableIndexes.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  if (_selectedIndexes.length ==
                                      selectableIndexes.length) {
                                    _selectedIndexes.clear();
                                  } else {
                                    _selectedIndexes
                                      ..clear()
                                      ..addAll(selectableIndexes);
                                  }
                                });
                              },
                        child: Text(
                          _selectedIndexes.length == selectableIndexes.length &&
                                  selectableIndexes.isNotEmpty
                              ? '取消全选'
                              : '全选未缓存',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => const DownloadPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.download_done_rounded, size: 18),
                        label: const Text('下载列表'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: widget.episodes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final episode = widget.episodes[index];
                      final taskId = _taskId(episode);
                      final task = _taskFor(tasks, episode);
                      final cached = widget.cachedIds.contains(taskId) ||
                          task?.status == DownloadTaskStatus.completed;
                      final unavailable = cached || task != null;
                      final selected = _selectedIndexes.contains(index);
                      final status = cached
                          ? '已缓存'
                          : task == null
                              ? null
                              : _statusLabel(task);
                      return InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: unavailable
                            ? null
                            : () {
                                setState(() {
                                  if (selected) {
                                    _selectedIndexes.remove(index);
                                  } else {
                                    _selectedIndexes.add(index);
                                  }
                                });
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? colors.brandPrimary.withAlpha(35)
                                : colors.surfaceElevation,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: selected
                                  ? colors.brandPrimary
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              if (unavailable)
                                Icon(
                                  cached
                                      ? Icons.check_circle_rounded
                                      : Icons.downloading_rounded,
                                  color: cached
                                      ? colors.statusSuccess
                                      : colors.brandAccent,
                                )
                              else
                                Checkbox(
                                  value: selected,
                                  onChanged: (_) {
                                    setState(() {
                                      if (selected) {
                                        _selectedIndexes.remove(index);
                                      } else {
                                        _selectedIndexes.add(index);
                                      }
                                    });
                                  },
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  episode.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: unavailable
                                        ? colors.textTertiary
                                        : colors.textPrimary,
                                  ),
                                ),
                              ),
                              if (status != null)
                                Text(
                                  status,
                                  style: TextStyle(
                                    color: cached
                                        ? colors.statusSuccess
                                        : colors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              else
                                Text(
                                  episode.badge ?? '',
                                  style: TextStyle(
                                    color: colors.textTertiary,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  decoration: BoxDecoration(
                    color: colors.surfaceCard,
                    border: Border(
                      top: BorderSide(color: colors.surfaceElevation),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '已选择 ${_selectedIndexes.length} 集',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _selectedIndexes.isEmpty
                            ? null
                            : () {
                                final selected = _selectedIndexes
                                    .map((index) => widget.episodes[index])
                                    .toList(growable: false);
                                Navigator.of(context).pop(selected);
                              },
                        icon: const Icon(Icons.download_rounded),
                        label: Text('缓存 ${_selectedIndexes.length} 集'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailEpisodeCard extends StatelessWidget {
  const _DetailEpisodeCard({
    required this.episode,
    required this.isLastPlayed,
    required this.colors,
  });

  final PlaybackEpisode episode;
  final bool isLastPlayed;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = episode.thumbnailUrl;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isLastPlayed ? colors.brandPrimary : colors.surfaceElevation,
          width: isLastPlayed ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                  Image.network(
                    thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallback(),
                  )
                else
                  _fallback(),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Colors.transparent, Colors.black54],
                    ),
                  ),
                ),
                const Center(
                  child: Icon(
                    Icons.play_circle_outline_rounded,
                    color: Colors.white,
                    size: 32,
                    shadows: <Shadow>[
                      Shadow(color: Colors.black87, blurRadius: 8),
                    ],
                  ),
                ),
                if (isLastPlayed)
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.brandPrimary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '上次播放',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  episode.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (episode.subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    episode.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return ColoredBox(
      color: colors.surfaceElevation,
      child: Icon(
        Icons.movie_outlined,
        color: colors.textTertiary,
        size: 34,
      ),
    );
  }
}
