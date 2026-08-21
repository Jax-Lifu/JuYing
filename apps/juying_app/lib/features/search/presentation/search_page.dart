import 'package:flutter/material.dart';

import '../../../application/policy/media_access_policy.dart';
import '../../../application/playback/playback_launcher.dart';
import '../../../application/search/federated_search_service.dart';
import '../../../application/search/media_search_clusterer.dart';
import '../../../domain/models/unified_media.dart';
import '../../../domain/models/media_source.dart';
import '../../../domain/ports/media_source_adapter.dart';
import '../../media/presentation/media_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    required this.adapters,
    required this.profileId,
    required this.isChildProfile,
    required this.playbackLauncher,
    this.childDailyLimitMinutes,
    super.key,
  });

  final List<MediaSourceAdapter> adapters;
  final String profileId;
  final bool isChildProfile;
  final PlaybackLauncher playbackLauncher;
  final int? childDailyLimitMinutes;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _searchService = const FederatedSearchService();
  Future<FederatedSearchResult>? _results;
  String? _selectedSourceId;

  static const _hotQueries = [
    'CCTV-1',
    '新闻联播',
    'CCTV-5',
    '少儿',
    '焦点访谈',
    'CCTV 4K',
    '纪录片',
    '卫视',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
      children: [
        Text(
          '聚合搜索',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '跨来源多路检索影片、电视频道与家庭媒体。',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 20),

        // Source filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('全域来源'),
                selected: _selectedSourceId == null,
                onSelected: (_) => setState(() => _selectedSourceId = null),
              ),
              const SizedBox(width: 8),
              ...widget.adapters.map((adapter) {
                final isUnavailable =
                    adapter.source.health == SourceHealth.unavailable ||
                        !adapter.source.isActive;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(isUnavailable
                        ? '${adapter.source.name}（暂不可用）'
                        : adapter.source.name),
                    selected: _selectedSourceId == adapter.source.id,
                    onSelected: isUnavailable
                        ? null
                        : (_) => setState(
                              () => _selectedSourceId = adapter.source.id,
                            ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Search Input Bar
        TextField(
          controller: _controller,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            prefixIcon:
                Icon(Icons.search_rounded, color: theme.colorScheme.primary),
            hintText: '输入节目名称、频道（如 CCTV-1）或关键词',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 20),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _results = null);
                    },
                  ),
                IconButton.filled(
                  onPressed: _search,
                  tooltip: '开始搜索',
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Hot keywords
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '热门探索：',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            ..._hotQueries.map((query) => ActionChip(
                  label: Text(query),
                  onPressed: () {
                    _controller.text = query;
                    _search();
                  },
                )),
          ],
        ),
        const SizedBox(height: 28),

        // Search Results
        if (_results == null)
          const _EmptyState(
            icon: Icons.travel_explore_rounded,
            title: '探索精彩视界',
            subtitle: '输入关键词搜索 CCTV 直播频道、点播节目与全网片库。',
          )
        else
          FutureBuilder<FederatedSearchResult>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) return _SearchError(onRetry: _search);
              final result = snapshot.requireData;
              final hits = result.hits;
              final clusters = result.clusters;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '已检索 ${result.succeededSourceCount} 个来源 · 共找到 ${clusters.length} 个作品 (${hits.length} 个版本)',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (hits.isEmpty)
                    const _EmptyState(
                      icon: Icons.search_off_rounded,
                      title: '未找到匹配结果',
                      subtitle: '请尝试更换关键词，或切换其他来源分类重试。',
                    )
                  else
                    ...clusters.map(
                      (cluster) => _SearchClusterCard(
                        cluster: cluster,
                        onOpen: _openHit,
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  void _search() {
    if (_controller.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _results = _searchAll(_controller.text));
  }

  Future<FederatedSearchResult> _searchAll(String query) async {
    final result = await _searchService.search(
      query: query,
      adapters: widget.adapters,
      sourceId: _selectedSourceId,
      policyContext: MediaAccessContext(
        isChildProfile: widget.isChildProfile,
      ),
    );
    return result;
  }

  void _openHit(MediaSearchHit hit) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MediaDetailPage(
        item: hit.item,
        adapter: widget.adapters.firstWhere(
          (adapter) => adapter.source.id == hit.item.sourceId,
        ),
        profileId: widget.profileId,
        isChildProfile: widget.isChildProfile,
        playbackLauncher: widget.playbackLauncher,
        childDailyLimitMinutes: widget.childDailyLimitMinutes,
      ),
    ));
  }
}

class _SearchClusterCard extends StatelessWidget {
  const _SearchClusterCard({required this.cluster, required this.onOpen});

  final MediaSearchCluster cluster;
  final ValueChanged<MediaSearchHit> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstHit = cluster.versions.first;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onOpen(firstHit),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: theme.colorScheme.surfaceContainer,
                ),
                clipBehavior: Clip.antiAlias,
                child: firstHit.item.posterUri == null
                    ? Icon(
                        firstHit.item.category == MediaCategory.live
                            ? Icons.live_tv_rounded
                            : Icons.movie_rounded,
                        color: theme.colorScheme.primary,
                      )
                    : Image.network(
                        firstHit.item.posterUri.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.movie_rounded, size: 24)),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cluster.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        _SmallBadge(label: firstHit.item.category.label),
                        _SmallBadge(label: firstHit.item.sourceId),
                        if (cluster.versions.length > 1)
                          _SmallBadge(
                            label: '${cluster.versions.length} 个版本',
                            isAccent: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label, this.isAccent = false});
  final String label;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isAccent
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isAccent
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: Colors.amber),
              const SizedBox(height: 12),
              const Text('搜索服务暂时不可用'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainer,
            ),
            child: Icon(icon,
                size: 48,
                color: theme.colorScheme.primary.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
