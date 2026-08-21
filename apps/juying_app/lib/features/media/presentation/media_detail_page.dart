import 'package:flutter/material.dart';

import '../../../application/favorites/favorite_store.dart';
import '../../../application/live/live_program_schedule.dart';
import '../../../application/playback/playback_launcher.dart';
import '../../../application/policy/media_access_policy.dart';
import '../../../application/policy/source_policy.dart';
import '../../../domain/models/live_program.dart';
import '../../../domain/models/unified_media.dart';
import '../../../domain/models/media_source.dart';
import '../../../domain/ports/live_program_guide.dart';
import '../../../domain/ports/media_source_adapter.dart';

class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({
    required this.item,
    required this.adapter,
    required this.profileId,
    required this.isChildProfile,
    required this.playbackLauncher,
    this.childDailyLimitMinutes,
    super.key,
  });

  final MediaItem item;
  final MediaSourceAdapter adapter;
  final String profileId;
  final bool isChildProfile;
  final PlaybackLauncher playbackLauncher;
  final int? childDailyLimitMinutes;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  final FavoriteStore _favoriteStore = FavoriteStore();
  late Future<List<MediaEpisode>> _episodes = _loadEpisodes();
  late final Future<List<LiveProgram>> _programGuide = _loadProgramGuide();
  var _isFavorite = false;
  int _selectedEpisodeTab = 0;

  @override
  void initState() {
    super.initState();
    _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    final favorites = await _favoriteStore.load(widget.profileId);
    if (!mounted) return;
    setState(() => _isFavorite = favorites.any(
          (favorite) =>
              favorite.sourceId == widget.item.sourceId &&
              favorite.sourceItemId == widget.item.sourceItemId,
        ));
  }

  Future<void> _toggleFavorite() async {
    final saved = await _favoriteStore.toggle(
      profileId: widget.profileId,
      item: widget.item,
    );
    if (!mounted) return;
    setState(() => _isFavorite = saved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? '已加入收藏' : '已取消收藏'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<List<MediaEpisode>> _loadEpisodes() {
    final decision = MediaAccessPolicy.evaluateItem(
      widget.adapter.source,
      widget.item,
      SourceAction.episodes,
      context: _policyContext,
      explicitSourceSelection: true,
    );
    if (!decision.allowed) {
      return Future.error(StateError(decision.reason ?? '此来源暂时不能加载选集'));
    }
    return widget.adapter.episodes(widget.item);
  }

  MediaAccessContext get _policyContext => MediaAccessContext(
        isChildProfile: widget.isChildProfile,
      );

  bool get _canShowProgramGuide =>
      widget.item.category == MediaCategory.live &&
      widget.adapter.source.capabilities
          .contains(SourceCapability.liveProgramGuide) &&
      widget.adapter is LiveProgramGuide;

  Future<List<LiveProgram>> _loadProgramGuide() {
    if (!_canShowProgramGuide) return Future.value(const []);
    return (widget.adapter as LiveProgramGuide).programGuide(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allowed = MediaAccessPolicy.evaluateItem(
      widget.adapter.source,
      widget.item,
      SourceAction.episodes,
      context: _policyContext,
      explicitSourceSelection: true,
    ).allowed;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _isFavorite ? '取消收藏' : '收藏',
            onPressed: _toggleFavorite,
            icon: Icon(
              _isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: _isFavorite ? Colors.redAccent : Colors.white,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !allowed
          ? const Center(child: Text('当前档案不可浏览该内容'))
          : FutureBuilder<List<MediaEpisode>>(
              future: _episodes,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 48, color: Colors.amber),
                        const SizedBox(height: 12),
                        Text('加载失败：${snapshot.error}'),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => setState(
                            () => _episodes = _loadEpisodes(),
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重新加载选集'),
                        ),
                      ],
                    ),
                  );
                }
                final episodes = snapshot.requireData;
                return Stack(
                  children: [
                    // Backdrop subtle glow
                    if (widget.item.posterUri != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 380,
                        child: Opacity(
                          opacity: 0.18,
                          child: Image.network(
                            widget.item.posterUri.toString(),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 380,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              theme.scaffoldBackgroundColor,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Main Content
                    ListView(
                      padding: const EdgeInsets.fromLTRB(28, 90, 28, 48),
                      children: [
                        _MediaHeader(
                          item: widget.item,
                          sourceName: widget.adapter.source.name,
                          onPlayFirst: episodes.isNotEmpty
                              ? () => _play(episodes.first, episodes)
                              : null,
                          isFavorite: _isFavorite,
                          onToggleFavorite: _toggleFavorite,
                        ),
                        if (_canShowProgramGuide) ...[
                          const SizedBox(height: 32),
                          _ProgramGuide(future: _programGuide),
                        ],
                        const SizedBox(height: 32),
                        _buildEpisodesSection(episodes),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildEpisodesSection(List<MediaEpisode> episodes) {
    final theme = Theme.of(context);
    if (episodes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: const Center(child: Text('暂无选集信息')),
      );
    }

    const pageSize = 30;
    final totalTabs = (episodes.length / pageSize).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.video_library_rounded,
                size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '选集播放',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '共 ${episodes.length} 集',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        if (totalTabs > 1) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(totalTabs, (index) {
                final start = index * pageSize + 1;
                final end = ((index + 1) * pageSize).clamp(0, episodes.length);
                final isSelected = index == _selectedEpisodeTab;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$start - $end'),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _selectedEpisodeTab = index);
                    },
                  ),
                );
              }),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Builder(builder: (context) {
          final start = _selectedEpisodeTab * pageSize;
          final end = (start + pageSize).clamp(0, episodes.length);
          final currentBatch = episodes.sublist(start, end);

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: currentBatch.map((episode) {
              final label = episode.episodeNumber?.toString() ?? episode.title;
              return SizedBox(
                width: 90,
                child: FilledButton.tonal(
                  onPressed: () => _play(episode, episodes),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Future<void> _play(MediaEpisode episode, List<MediaEpisode> episodes) async {
    Object? nativeError;
    final nativeDecision = MediaAccessPolicy.evaluateItem(
      widget.adapter.source,
      widget.item,
      SourceAction.nativePlayback,
      context: _policyContext,
      explicitSourceSelection: true,
    );
    if (nativeDecision.allowed) {
      try {
        final playback = await widget.adapter.resolvePlayback(episode);
        if (playback.nativeStreamUri == null) {
          throw StateError('来源未提供可用原生播放地址');
        }
        if (!mounted) return;
        await widget.playbackLauncher.launchNative(
          context,
          PlaybackLaunchRequest(
            playback: playback,
            episodes: episodes,
            resolveEpisode: widget.adapter.resolvePlayback,
            profileId: widget.profileId,
            sourceCapabilities: widget.adapter.source.capabilities,
            childDailyLimitMinutes: widget.childDailyLimitMinutes,
          ),
        );
        return;
      } catch (error) {
        nativeError = error;
      }
    }
    final fallbackDecision = MediaAccessPolicy.evaluateItem(
      widget.adapter.source,
      widget.item,
      SourceAction.officialFallback,
      context: _policyContext,
      explicitSourceSelection: true,
    );
    if (!fallbackDecision.allowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nativeError == null
                ? fallbackDecision.reason ?? '当前来源不可播放'
                : '无法准备播放：$nativeError',
          ),
        ),
      );
      return;
    }
    try {
      final playback = await widget.adapter.resolveOfficialFallback(episode);
      if (!mounted) return;
      await widget.playbackLauncher.launchOfficial(
        context,
        PlaybackLaunchRequest(
          playback: playback,
          episodes: episodes,
          resolveEpisode: widget.adapter.resolveOfficialFallback,
          profileId: widget.profileId,
          sourceCapabilities: widget.adapter.source.capabilities,
          childDailyLimitMinutes: widget.childDailyLimitMinutes,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法准备官方播放：$error')),
      );
    }
  }
}

class _MediaHeader extends StatelessWidget {
  const _MediaHeader({
    required this.item,
    required this.sourceName,
    this.onPlayFirst,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final MediaItem item;
  final String sourceName;
  final VoidCallback? onPlayFirst;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Poster with subtle elevation
        Container(
          width: 150,
          height: 215,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: item.posterUri == null
              ? Container(
                  color: theme.colorScheme.surfaceContainer,
                  child: Icon(
                    item.category == MediaCategory.live
                        ? Icons.live_tv_rounded
                        : Icons.movie_rounded,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                )
              : Image.network(item.posterUri.toString(), fit: BoxFit.cover),
        ),
        const SizedBox(width: 24),
        // Metadata & Actions
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Badge(label: item.category.label, isPrimary: true),
                  if (item.year != null) _Badge(label: item.year!),
                  if (item.area != null) _Badge(label: item.area!),
                  _Badge(label: sourceName),
                ],
              ),
              if (item.brief != null) ...[
                const SizedBox(height: 14),
                Text(
                  item.brief!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  if (onPlayFirst != null)
                    FilledButton.icon(
                      onPressed: onPlayFirst,
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: const Text('立即起播'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 20,
                      color: isFavorite ? Colors.redAccent : null,
                    ),
                    label: Text(isFavorite ? '已收藏' : '收藏'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.isPrimary = false});
  final String label;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPrimary
            ? theme.colorScheme.primary.withValues(alpha: 0.18)
            : theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPrimary
              ? theme.colorScheme.primary.withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isPrimary
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.8),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProgramGuide extends StatelessWidget {
  const _ProgramGuide({required this.future});
  final Future<List<LiveProgram>> future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<LiveProgram>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator();
        }
        final programs = snapshot.data ?? const [];
        if (programs.isEmpty) return const SizedBox.shrink();
        final now = DateTime.now();
        final current = LiveProgramSchedule.current(programs, now: now);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '节目单 (EPG)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (current != null) ...[
                _NowPlayingProgram(program: current, now: now),
                const SizedBox(height: 12),
              ],
              ...programs.take(6).map((program) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          _time(program.startsAt),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            program.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _NowPlayingProgram extends StatelessWidget {
  const _NowPlayingProgram({required this.program, required this.now});
  final LiveProgram program;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = LiveProgramSchedule.progress(program, now: now);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fiber_manual_record,
                  color: Colors.redAccent, size: 10),
              const SizedBox(width: 6),
              Text(
                '正在播出：${program.title}',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}
