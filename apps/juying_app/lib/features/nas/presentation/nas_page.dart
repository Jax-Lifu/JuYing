import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/nas/models/nas_remote_share.dart';
import 'package:juying/features/nas/models/nas_server_config.dart';
import 'package:juying/features/nas/models/nas_share_item.dart';
import 'package:juying/features/nas/providers/nas_provider.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// Comprehensive NAS Media Explorer with Grid/List/Details View Modes,
/// Interactive Click-to-Jump Breadcrumbs, Real LAN Hostname Scanning,
/// and Clean Storage Unmounting / Session Release.
class NasPage extends ConsumerStatefulWidget {
  const NasPage({super.key});

  @override
  ConsumerState<NasPage> createState() => _NasPageState();
}

class _NasPageState extends ConsumerState<NasPage> {
  // TvFocusWrapper permanently reserves a 2px focus ring on every side. The
  // pinned extent must include that vertical space even before a control gains
  // focus, otherwise the empty-server header overflows by exactly four pixels.
  static const double _emptyHeaderHeight = 81;
  static const double _mountedHeaderHeight = 212;

  final ScrollController _serverStripController = ScrollController();

  @override
  void dispose() {
    _serverStripController.dispose();
    super.dispose();
  }

  /// Scrolls the mounted-server strip by one viewport page so large NAS sets
  /// remain reachable with mouse, touch, keyboard, and TV remote input.
  void _scrollServerStrip(int direction) {
    if (!_serverStripController.hasClients) return;

    final position = _serverStripController.position;
    final target = (_serverStripController.offset +
            position.viewportDimension * 0.72 * direction)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _serverStripController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _navigateFolder(String newPath) {
    ref.read(currentNasPathProvider.notifier).state = newPath;
  }

  void _navigateUp() {
    final current = ref.read(currentNasPathProvider);
    if (current == '/' || current.isEmpty) return;

    final parts = current.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) {
      ref.read(currentNasPathProvider.notifier).state = '/';
    } else {
      parts.removeLast();
      ref.read(currentNasPathProvider.notifier).state = '/${parts.join('/')}';
    }
  }

  void _playNasMedia(NasServerConfig server, NasShareItem file) {
    final service = ref.read(lanNasServiceProvider);
    final proxyUrl = service.bridgeNasFileToProxy(server: server, file: file);

    final candidate = PlaybackCandidate(
      sourceKey: 'nas_${server.id}',
      sourceName: server.name,
      lineName: '${server.protocol.label} · 本地回环直连',
      resolution: file.resolutionTag,
      episodes: <PlaybackEpisode>[
        PlaybackEpisode(
          name: file.name,
          url: proxyUrl,
          sortIndex: 1,
          badge: file.formattedSize,
        ),
      ],
    );

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => VideoPlayerPage(
          title: file.name,
          currentEpisode: candidate.episodes.first,
          candidate: candidate,
          allCandidates: <PlaybackCandidate>[candidate],
        ),
      ),
    );
  }

  void _confirmUnmountServer(BuildContext context, NasServerConfig server) {
    final colors = context.colors;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceCard,
        title: Row(
          children: <Widget>[
            Icon(Icons.eject_rounded, color: colors.statusError, size: 22),
            const SizedBox(width: 8),
            Text('卸载 / 断开 NAS 存储', style: TextStyle(color: colors.textPrimary)),
          ],
        ),
        content: Text(
          '确定要卸载并断开 "${server.name}" (${server.summaryUri}) 吗？\n\n卸载后将安全释放网络会话并从本地存储中移除。',
          style: TextStyle(color: colors.textSecondary, height: 1.4),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('取消', style: TextStyle(color: colors.textTertiary)),
          ),
          ElevatedButton.icon(
            style:
                ElevatedButton.styleFrom(backgroundColor: colors.statusError),
            onPressed: () async {
              final service = ref.read(lanNasServiceProvider);
              Navigator.of(ctx).pop();
              await ref
                  .read(nasServersProvider.notifier)
                  .unmountAndRemoveServer(server, service);
            },
            icon: const Icon(Icons.link_off_rounded,
                color: Colors.white, size: 16),
            label: const Text('确认卸载', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final servers = ref.watch(nasServersProvider);
    final activeServer = ref.watch(activeNasServerProvider);
    final currentPath = ref.watch(currentNasPathProvider);
    final viewMode = ref.watch(nasViewModeProvider);
    final contentsAsync = ref.watch(nasDirectoryContentsProvider);

    return Scaffold(
      backgroundColor: colors.backgroundDeep,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverPersistentHeader(
            pinned: true,
            delegate: _NasHeaderDelegate(
              height:
                  servers.isEmpty ? _emptyHeaderHeight : _mountedHeaderHeight,
              child: _buildPersistentHeader(
                colors,
                servers,
                activeServer,
                currentPath,
                viewMode,
              ),
            ),
          ),

          // 2. Empty State when NO NAS servers are added
          if (servers.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(36),
                    constraints: const BoxConstraints(maxWidth: 540),
                    decoration: BoxDecoration(
                      color: colors.surfaceCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.surfaceElevation),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: colors.brandPrimary.withAlpha(25),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.storage_rounded,
                            size: 48,
                            color: colors.brandPrimary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '尚未挂载任何 NAS 存储',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '支持挂载您的局域网 Samba (SMBv2/v3)、NFS 以及 WebDAV / Alist 影音库，支持 4K 原盘直连与拖拽寻道播放。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.brandPrimary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () => _showAddServerModal(context),
                              icon: const Icon(Icons.add_rounded,
                                  color: Colors.white, size: 18),
                              label: const Text('添加 NAS 连接',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 14),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: colors.brandPrimary.withAlpha(120)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () => _showScanModal(context),
                              icon: Icon(Icons.radar_rounded,
                                  color: colors.brandAccent, size: 18),
                              label: Text('扫描局域网',
                                  style: TextStyle(color: colors.textPrimary)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else ...<Widget>[
            // 4. Directory Contents Explorer (Grid / List / Details)
            contentsAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(60),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
              error: (err, _) => SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text('读取 NAS 目录失败: $err',
                        style: TextStyle(color: colors.statusError)),
                  ),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(60),
                        child: Text('当前目录为空或无法连接到存储设备',
                            style: TextStyle(color: colors.textTertiary)),
                      ),
                    ),
                  );
                }

                switch (viewMode) {
                  case NasViewMode.grid:
                    return _buildGridView(colors, activeServer, items);
                  case NasViewMode.list:
                    return _buildListView(colors, activeServer, items);
                  case NasViewMode.details:
                    return _buildDetailsView(colors, activeServer, items);
                }
              },
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 40),
            ),
          ],
        ],
      ),
    );
  }

  /// Keeps navigation and storage controls outside the directory scroll flow.
  /// A single fixed-height header avoids nested pinned slivers overlapping when
  /// the mounted-server strip grows beyond one viewport.
  Widget _buildPersistentHeader(
    AppThemeColors colors,
    List<NasServerConfig> servers,
    NasServerConfig? activeServer,
    String currentPath,
    NasViewMode viewMode,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.backgroundDeep,
        border: Border(
          bottom: BorderSide(color: colors.surfaceElevation),
        ),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
            child: Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.brandPrimary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'LAN NAS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '局域网影音库 · Samba / NFS / WebDAV',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TvFocusWrapper(
                  onTap: () => _showAddServerModal(context),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.brandPrimary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: <Widget>[
                        Icon(Icons.add, size: 16, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          '添加 NAS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TvFocusWrapper(
                  onTap: () => _showScanModal(context),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.surfaceElevation,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colors.brandPrimary.withAlpha(80),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.radar,
                          size: 16,
                          color: colors.brandAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '自动扫描',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (servers.isNotEmpty) ...<Widget>[
            SizedBox(
              height: 48,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 24),
                  if (servers.length > 1) ...<Widget>[
                    _buildServerStripScrollButton(
                      colors,
                      Icons.chevron_left_rounded,
                      () => _scrollServerStrip(-1),
                      '向前浏览 NAS',
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ListView.separated(
                      controller: _serverStripController,
                      scrollDirection: Axis.horizontal,
                      itemCount: servers.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final server = servers[index];
                        final isSelected = server.id == activeServer?.id;

                        return TvFocusWrapper(
                          onTap: () {
                            ref.read(activeNasServerProvider.notifier).state =
                                server;
                            ref.read(currentNasPathProvider.notifier).state =
                                '/';
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.brandPrimary.withAlpha(50)
                                  : colors.surfaceElevation,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isSelected
                                    ? colors.brandPrimary
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  server.protocol == NasProtocol.smb
                                      ? Icons.folder_shared_rounded
                                      : server.protocol == NasProtocol.nfs
                                          ? Icons.storage_rounded
                                          : Icons.cloud_queue_rounded,
                                  size: 16,
                                  color: isSelected
                                      ? colors.focusBorder
                                      : colors.brandAccent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  server.name,
                                  style: TextStyle(
                                    color: isSelected
                                        ? colors.textPrimary
                                        : colors.textSecondary,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.backgroundDeep,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    server.protocol.name.toUpperCase(),
                                    style: TextStyle(
                                      color: colors.textTertiary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: '卸载 ${server.name}',
                                  child: GestureDetector(
                                    onTap: () =>
                                        _confirmUnmountServer(context, server),
                                    child: Icon(
                                      Icons.eject_rounded,
                                      size: 15,
                                      color: colors.textSecondary,
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
                  if (servers.length > 1) ...<Widget>[
                    const SizedBox(width: 8),
                    _buildServerStripScrollButton(
                      colors,
                      Icons.chevron_right_rounded,
                      () => _scrollServerStrip(1),
                      '向后浏览 NAS',
                    ),
                  ],
                  const SizedBox(width: 24),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.surfaceElevation),
                ),
                child: Row(
                  children: <Widget>[
                    if (currentPath != '/' &&
                        currentPath.isNotEmpty) ...<Widget>[
                      TvFocusWrapper(
                        onTap: _navigateUp,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceElevation,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.arrow_upward_rounded,
                                size: 14,
                                color: colors.brandPrimary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '上级',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        height: 18,
                        width: 1,
                        color: colors.surfaceElevation,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _buildBreadcrumbSegments(
                            colors,
                            currentPath,
                            activeServer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (activeServer != null) ...<Widget>[
                      TvFocusWrapper(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () =>
                            _confirmUnmountServer(context, activeServer),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.statusError.withAlpha(18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colors.statusError.withAlpha(130),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.link_off_rounded,
                                size: 14,
                                color: colors.statusError,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '卸载',
                                style: TextStyle(
                                  color: colors.statusError,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    _buildViewModeSwitcher(colors, viewMode),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServerStripScrollButton(
    AppThemeColors colors,
    IconData icon,
    VoidCallback onTap,
    String tooltip,
  ) {
    return Tooltip(
      message: tooltip,
      child: TvFocusWrapper(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.surfaceElevation),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: colors.textSecondary),
        ),
      ),
    );
  }

  /// Builds interactive click-to-jump breadcrumb segments.
  List<Widget> _buildBreadcrumbSegments(
    AppThemeColors colors,
    String currentPath,
    NasServerConfig? server,
  ) {
    final widgets = <Widget>[];

    // Root Segment
    final isRootActive = currentPath == '/' || currentPath.isEmpty;
    widgets.add(
      TvFocusWrapper(
        onTap: () => _navigateFolder('/'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isRootActive
                ? colors.brandPrimary.withAlpha(40)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.home_rounded,
                  size: 15,
                  color:
                      isRootActive ? colors.brandPrimary : colors.brandAccent),
              const SizedBox(width: 4),
              Text(
                '根目录',
                style: TextStyle(
                  color:
                      isRootActive ? colors.textPrimary : colors.textSecondary,
                  fontSize: 12,
                  fontWeight:
                      isRootActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (currentPath == '/' || currentPath.isEmpty) {
      return widgets;
    }

    final rawSegments =
        currentPath.split('/').where((s) => s.isNotEmpty).toList();
    var accumulatedPath = '';

    for (var i = 0; i < rawSegments.length; i++) {
      final seg = rawSegments[i];
      accumulatedPath += '/$seg';
      final isLast = i == rawSegments.length - 1;
      final targetPath = accumulatedPath;

      // Divider Chevron
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right_rounded,
              size: 16, color: colors.textTertiary),
        ),
      );

      // Segment Chip
      widgets.add(
        TvFocusWrapper(
          onTap: () => _navigateFolder(targetPath),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isLast
                  ? colors.brandPrimary.withAlpha(40)
                  : colors.surfaceElevation,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isLast ? colors.brandPrimary : Colors.transparent,
                width: 1,
              ),
            ),
            child: Text(
              seg,
              style: TextStyle(
                color: isLast ? colors.textPrimary : colors.textSecondary,
                fontSize: 12,
                fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  /// Segmented view mode switcher (Icons / List / Details).
  Widget _buildViewModeSwitcher(
      AppThemeColors colors, NasViewMode currentMode) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevation,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceElevation),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: NasViewMode.values.map((mode) {
          final isSelected = mode == currentMode;

          return TvFocusWrapper(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              ref.read(nasViewModeProvider.notifier).state = mode;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? colors.brandPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: isSelected
                    ? <BoxShadow>[
                        BoxShadow(
                          color: colors.focusGlow,
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    mode.icon,
                    size: 14,
                    color: isSelected ? Colors.white : colors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    mode.label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : colors.textSecondary,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // -------------------------------------------------------------
  // View 1: Icons / Grid View Mode (图标模式)
  // -------------------------------------------------------------
  Widget _buildGridView(
    AppThemeColors colors,
    NasServerConfig? server,
    List<NasShareItem> items,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.1,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            final isDir = item.isDirectory;
            final isMedia = item.isMediaFile;

            return TvFocusWrapper(
              onTap: () {
                if (isDir) {
                  _navigateFolder(item.path);
                } else if (isMedia && server != null) {
                  _playNasMedia(server, item);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.surfaceElevation),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDir
                                ? Colors.amber.withAlpha(40)
                                : isMedia
                                    ? colors.brandPrimary.withAlpha(40)
                                    : colors.surfaceElevation,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isDir
                                ? Icons.folder_rounded
                                : isMedia
                                    ? Icons.play_circle_fill_rounded
                                    : item.isSubtitles
                                        ? Icons.subtitles_rounded
                                        : Icons.insert_drive_file_rounded,
                            color: isDir
                                ? Colors.amber
                                : isMedia
                                    ? colors.focusBorder
                                    : colors.textSecondary,
                            size: 24,
                          ),
                        ),
                        const Spacer(),
                        if (isMedia && item.resolutionTag != '-')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.brandPrimary.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.resolutionTag,
                              style: TextStyle(
                                color: colors.brandAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13,
                            fontWeight:
                                isDir ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              item.fileTypeName,
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 10,
                              ),
                            ),
                            if (!isDir)
                              Text(
                                item.formattedSize,
                                style: TextStyle(
                                  color: colors.textTertiary,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // View 2: List View Mode (列表模式)
  // -------------------------------------------------------------
  Widget _buildListView(
    AppThemeColors colors,
    NasServerConfig? server,
    List<NasShareItem> items,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            final isDir = item.isDirectory;
            final isMedia = item.isMediaFile;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TvFocusWrapper(
                onTap: () {
                  if (isDir) {
                    _navigateFolder(item.path);
                  } else if (isMedia && server != null) {
                    _playNasMedia(server, item);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.surfaceElevation),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDir
                              ? Colors.amber.withAlpha(30)
                              : isMedia
                                  ? colors.brandPrimary.withAlpha(30)
                                  : colors.surfaceElevation,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          isDir
                              ? Icons.folder_rounded
                              : isMedia
                                  ? Icons.play_arrow_rounded
                                  : item.isSubtitles
                                      ? Icons.subtitles_rounded
                                      : Icons.insert_drive_file_rounded,
                          color: isDir
                              ? Colors.amber
                              : isMedia
                                  ? colors.brandPrimary
                                  : colors.textSecondary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.name,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 13,
                                fontWeight:
                                    isDir ? FontWeight.bold : FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.fileTypeName,
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isMedia && item.resolutionTag != '-') ...<Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.brandPrimary.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.resolutionTag,
                            style: TextStyle(
                              color: colors.brandAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      if (!isDir) ...<Widget>[
                        Text(
                          item.formattedSize,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Icon(
                        isDir
                            ? Icons.chevron_right_rounded
                            : isMedia
                                ? Icons.play_circle_outline_rounded
                                : Icons.arrow_forward_ios_rounded,
                        size: 18,
                        color:
                            isMedia ? colors.brandPrimary : colors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // View 3: Details Table View Mode (详情表格模式)
  // -------------------------------------------------------------
  Widget _buildDetailsView(
    AppThemeColors colors,
    NasServerConfig? server,
    List<NasShareItem> items,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverToBoxAdapter(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.surfaceElevation),
          ),
          child: Column(
            children: <Widget>[
              // Table Header Row
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.surfaceElevation,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(9)),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: Text('名称',
                          style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('类型',
                          style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('大小',
                          style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('画质',
                          style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('修改时间',
                          style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('操作',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

              // Table Body Rows
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: colors.surfaceElevation),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isDir = item.isDirectory;
                  final isMedia = item.isMediaFile;

                  return TvFocusWrapper(
                    onTap: () {
                      if (isDir) {
                        _navigateFolder(item.path);
                      } else if (isMedia && server != null) {
                        _playNasMedia(server, item);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      color: index % 2 == 1
                          ? colors.surfaceElevation.withAlpha(40)
                          : Colors.transparent,
                      child: Row(
                        children: <Widget>[
                          // 1. Name & Icon
                          Expanded(
                            flex: 5,
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  isDir
                                      ? Icons.folder_rounded
                                      : isMedia
                                          ? Icons.video_file_rounded
                                          : item.isSubtitles
                                              ? Icons.subtitles_rounded
                                              : Icons.insert_drive_file_rounded,
                                  size: 18,
                                  color: isDir
                                      ? Colors.amber
                                      : isMedia
                                          ? colors.brandPrimary
                                          : colors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: isDir
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 2. File Type
                          Expanded(
                            flex: 2,
                            child: Text(
                              item.fileTypeName,
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 12),
                            ),
                          ),

                          // 3. File Size
                          Expanded(
                            flex: 2,
                            child: Text(
                              item.formattedSize,
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),

                          // 4. Resolution
                          Expanded(
                            flex: 2,
                            child: isMedia && item.resolutionTag != '-'
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colors.brandPrimary.withAlpha(30),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.resolutionTag,
                                      style: TextStyle(
                                        color: colors.brandAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : Text('-',
                                    style: TextStyle(
                                        color: colors.textTertiary,
                                        fontSize: 12)),
                          ),

                          // 5. Modified Time
                          Expanded(
                            flex: 3,
                            child: Text(
                              item.formattedModifiedTime,
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),

                          // 6. Action Button
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: isMedia
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colors.brandPrimary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(Icons.play_arrow_rounded,
                                              size: 14, color: Colors.white),
                                          SizedBox(width: 2),
                                          Text('播放',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    )
                                  : isDir
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: colors.surfaceElevation,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text('打开',
                                              style: TextStyle(
                                                  color: colors.textPrimary,
                                                  fontSize: 11)),
                                        )
                                      : const SizedBox.shrink(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Modals: Add NAS Server & Auto Scan
  // -------------------------------------------------------------
  void _showAddServerModal(BuildContext context) {
    final colors = context.colors;
    final nameCtrl = TextEditingController();
    final hostCtrl = TextEditingController();
    final shareCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    NasProtocol selectedProtocol = NasProtocol.smb;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surfaceCard,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              height: MediaQuery.of(context).size.height * 0.85,
              child: ListView(
                children: <Widget>[
                  Text(
                    '添加局域网 NAS 连接 (Samba / NFS / WebDAV)',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Protocol Selector
                  Text('存储协议类型', style: TextStyle(color: colors.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: NasProtocol.values.map((p) {
                      final isSel = p == selectedProtocol;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedProtocol = p),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? colors.brandPrimary
                                  : colors.surfaceElevation,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                p.name.toUpperCase(),
                                style: TextStyle(
                                  color:
                                      isSel ? Colors.white : colors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: '连接名称 (如: 我的群晖 / Alist)',
                      labelStyle: TextStyle(color: colors.textSecondary),
                      filled: true,
                      fillColor: colors.surfaceElevation,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: hostCtrl,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'NAS 主机 IP / 域名 (如: 192.168.1.100)',
                      labelStyle: TextStyle(color: colors.textSecondary),
                      filled: true,
                      fillColor: colors.surfaceElevation,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: shareCtrl,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: selectedProtocol == NasProtocol.nfs
                          ? 'NFS 挂载路径 (如: /mnt/storage/movies)'
                          : '共享文件夹或路径 (如: video 或 dav)',
                      labelStyle: TextStyle(color: colors.textSecondary),
                      filled: true,
                      fillColor: colors.surfaceElevation,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: userCtrl,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: '账号 / 用户名 (匿名可留空)',
                      labelStyle: TextStyle(color: colors.textSecondary),
                      filled: true,
                      fillColor: colors.surfaceElevation,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: '密码 (匿名可留空)',
                      labelStyle: TextStyle(color: colors.textSecondary),
                      filled: true,
                      fillColor: colors.surfaceElevation,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.brandPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      final host = hostCtrl.text.trim();
                      if (host.isEmpty) return;

                      final newServer = NasServerConfig(
                        id: 'nas_${DateTime.now().millisecondsSinceEpoch}',
                        name: nameCtrl.text.trim().isNotEmpty
                            ? nameCtrl.text.trim()
                            : '${selectedProtocol.name.toUpperCase()} ($host)',
                        protocol: selectedProtocol,
                        host: host,
                        shareName: shareCtrl.text.trim(),
                        username: userCtrl.text.trim().isNotEmpty
                            ? userCtrl.text.trim()
                            : null,
                        password: passCtrl.text.trim().isNotEmpty
                            ? passCtrl.text.trim()
                            : null,
                      );
                      ref
                          .read(nasServersProvider.notifier)
                          .addServer(newServer);
                      ref.read(activeNasServerProvider.notifier).state =
                          newServer;
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      '保存并连接 NAS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget _buildDiscoveredGroups(
    BuildContext context,
    WidgetRef ref,
    List<NasServerConfig> discovered,
    AppThemeColors colors,
  ) {
    final groups = <NasProtocol, List<NasServerConfig>>{
      for (final protocol in NasProtocol.values)
        protocol:
            discovered.where((item) => item.protocol == protocol).toList(),
    };
    final children = <Widget>[];
    for (final entry in groups.entries) {
      if (entry.value.isEmpty) continue;
      final title = switch (entry.key) {
        NasProtocol.smb => 'Samba 共享',
        NasProtocol.nfs => 'NFS 导出',
        NasProtocol.webdav => 'WebDAV / Alist',
      };
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
          child: Row(
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entry.value.length} 台',
                style: TextStyle(color: colors.textTertiary, fontSize: 11),
              ),
              const SizedBox(width: 10),
              Expanded(child: Divider(color: colors.surfaceElevation)),
            ],
          ),
        ),
      );
      for (final server in entry.value) {
        children
          ..add(_buildDiscoveredServerTile(context, ref, server, colors))
          ..add(const SizedBox(height: 10));
      }
    }
    return ListView(children: children);
  }

  Widget _buildDiscoveredServerTile(
    BuildContext context,
    WidgetRef ref,
    NasServerConfig server,
    AppThemeColors colors,
  ) {
    final hasHostname = server.hostname != null && server.hostname!.isNotEmpty;
    return TvFocusWrapper(
      onTap: () => _mountDiscoveredServer(context, ref, server),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceElevation,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              server.protocol == NasProtocol.smb
                  ? Icons.folder_shared_rounded
                  : server.protocol == NasProtocol.nfs
                      ? Icons.storage_rounded
                      : Icons.cloud_queue_rounded,
              color: colors.focusBorder,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          server.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (hasHostname) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colors.brandPrimary.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '主机名: ${server.hostname!}',
                            style: TextStyle(
                              color: colors.brandAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    server.summaryUri,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.brandPrimary,
              ),
              onPressed: () => _mountDiscoveredServer(context, ref, server),
              child: Text(
                server.protocol == NasProtocol.smb ? '选择共享' : '挂载连接',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mountDiscoveredServer(
    BuildContext context,
    WidgetRef ref,
    NasServerConfig discovered,
  ) async {
    try {
      NasServerConfig? mounted;
      if (discovered.protocol == NasProtocol.smb) {
        mounted = await _showSmbShareDialog(context, ref, discovered);
      } else if (discovered.protocol == NasProtocol.nfs) {
        mounted = await _showNfsExportDialog(context, ref, discovered);
      } else {
        mounted = discovered;
      }
      if (mounted == null || !context.mounted) return;
      await ref.read(nasServersProvider.notifier).addServer(mounted);
      ref.read(activeNasServerProvider.notifier).state = mounted;
      ref.read(currentNasPathProvider.notifier).state = '/';
      if (context.mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<NasServerConfig?> _showSmbShareDialog(
    BuildContext context,
    WidgetRef ref,
    NasServerConfig server,
  ) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    var shares = const <NasRemoteShare>[];
    var loading = false;
    String? error;

    return showDialog<NasServerConfig>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> loadShares() async {
            setDialogState(() {
              loading = true;
              error = null;
            });
            try {
              final result =
                  await ref.read(lanNasServiceProvider).listSmbShares(
                        server,
                        username: usernameController.text.trim(),
                        password: passwordController.text,
                      );
              if (!dialogContext.mounted) return;
              setDialogState(() => shares = result);
            } catch (exception) {
              if (!dialogContext.mounted) return;
              setDialogState(() => error = exception.toString());
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => loading = false);
              }
            }
          }

          return AlertDialog(
            backgroundColor: context.colors.surfaceCard,
            title: Text('Samba 身份与共享 · ${server.hostname ?? server.host}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: '用户名（匿名访问可留空）',
                        helperText: r'域账号可直接填写 DOMAIN\用户名',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '密码'),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: loading ? null : loadShares,
                        icon: loading
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.folder_open_rounded),
                        label: const Text('验证并读取共享目录'),
                      ),
                    ),
                    if (error != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: TextStyle(color: context.colors.statusError),
                      ),
                    ],
                    for (final share in shares)
                      ListTile(
                        leading: const Icon(Icons.folder_shared_rounded),
                        title: Text(share.name),
                        subtitle: share.description == null
                            ? null
                            : Text(share.description!),
                        onTap: () {
                          Navigator.of(dialogContext).pop(
                            server.copyWith(
                              id: '${server.id}_${share.path.hashCode.abs()}',
                              name:
                                  '${server.hostname ?? server.host} · ${share.name}',
                              shareName: share.path,
                              username: usernameController.text.trim().isEmpty
                                  ? null
                                  : usernameController.text.trim(),
                              password: passwordController.text.isEmpty
                                  ? null
                                  : passwordController.text,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      usernameController.dispose();
      passwordController.dispose();
    });
  }

  Future<NasServerConfig?> _showNfsExportDialog(
    BuildContext context,
    WidgetRef ref,
    NasServerConfig server,
  ) {
    final exports = ref.read(lanNasServiceProvider).listNfsExports(server);
    return showDialog<NasServerConfig>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceCard,
        title: Text('NFS 导出目录 · ${server.hostname ?? server.host}'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: FutureBuilder<List<NasRemoteShare>>(
            future: exports,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text(snapshot.error.toString()));
              }
              final items = snapshot.data ?? const <NasRemoteShare>[];
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final export = items[index];
                  return ListTile(
                    leading: const Icon(Icons.storage_rounded),
                    title: Text(export.path),
                    subtitle: Text('允许访问: ${export.description ?? '*'}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      try {
                        final mounted = await ref
                            .read(lanNasServiceProvider)
                            .mountNfsExport(server, export);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(mounted);
                        }
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showScanModal(BuildContext context) {
    final colors = context.colors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surfaceCard,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final scanAsync = ref.watch(discoveredLanServersProvider);

            return Container(
              padding: const EdgeInsets.all(24),
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.radar_rounded, color: colors.brandAccent),
                      const SizedBox(width: 10),
                      Text(
                        '局域网已发现的 NAS 设备 (Samba/NFS/WebDAV)',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: scanAsync.when(
                      loading: () => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              '正在广播发现设备并校验真实 SMB/NFS/WebDAV 协议...',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      error: (e, _) => Center(
                        child: Text('扫描失败: $e',
                            style: TextStyle(color: colors.statusError)),
                      ),
                      data: (discovered) {
                        if (discovered.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(Icons.search_off_rounded,
                                    size: 40, color: colors.textTertiary),
                                const SizedBox(height: 12),
                                Text(
                                  '局域网内未发现通过协议验证的可连接 NAS 服务',
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '您可以点击下方按钮手动输入 IP 挂载',
                                  style: TextStyle(
                                      color: colors.textTertiary, fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        }

                        return _buildDiscoveredGroups(
                          context,
                          ref,
                          discovered,
                          colors,
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
}

/// Pins the complete NAS navigation surface while directory contents scroll.
/// Keeping min/max extents equal prevents layout jumps when the body switches
/// between loading, empty, and populated states.
class _NasHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _NasHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _NasHeaderDelegate oldDelegate) {
    return height != oldDelegate.height || child != oldDelegate.child;
  }
}
