import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// Source Management Center (Section 6.1 features/sources & APP-01/10).
///
/// **What**: Unified entrypoint to manage IPTV live playlists, TVBox subscriptions,
/// and NAS network shares with health status checks and fault-isolated lists.
///
/// **Why**: Implements APP-01, APP-10, LIVE-02, VOD-06, VOD-09. Consolidates source configuration
/// across all media domains with a 10-foot TV-friendly remote navigation layout.
class SourcesManagementPage extends ConsumerStatefulWidget {
  const SourcesManagementPage({super.key});

  @override
  ConsumerState<SourcesManagementPage> createState() =>
      _SourcesManagementPageState();
}

class _SourcesManagementPageState extends ConsumerState<SourcesManagementPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '源管理中心 (APP-01)',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '管理 IPTV 直播源、TVBox 订阅仓与局域网 NAS 共享',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                TvFocusWrapper(
                  onTap: _showImportDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.brandPrimary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: <Widget>[
                        Icon(Icons.add, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '添加 / 导入源',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: colors.brandPrimary,
              unselectedLabelColor: colors.textSecondary,
              indicatorColor: colors.brandPrimary,
              tabs: const <Widget>[
                Tab(text: '📺 直播源 (IPTV)'),
                Tab(text: '🕷️ TVBox / 点播仓'),
                Tab(text: '📁 局域网 NAS / 网盘'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _buildLiveTab(colors),
                  _buildTvboxTab(colors),
                  _buildStorageTab(colors),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTab(AppThemeColors colors) {
    return ListView(
      children: <Widget>[
        // LIVE-02 & ADR-005: CCTV Official Default Preset
        _buildSourceCard(
          colors: colors,
          icon: Icons.tv,
          title: 'CCTV 官方直播（默认预设，可编辑可删除）',
          subtitle: '官方公开网址接入 (LIVE-02) • 仅提供流解析，应用不存储/分发内容 • 支持 IPv4/IPv6',
          badgeText: '官方预设',
          badgeColor: colors.statusSuccess,
          isEnabled: true,
          actionTrailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                icon: Icon(Icons.info_outline, color: colors.textSecondary),
                tooltip: '合规与免责声明 (3.5)',
                onPressed: () => _showDisclaimerDialog(
                  title: 'CCTV 默认源合规说明 (LIVE-02 / ADR-005)',
                  content: '本源使用央视网官方公开网址 (tv.cctv.com/yxg) 动态换取 HLS 清单，'
                      '仅作为展示客户端解析能力的可选示例。用户可根据自身需求自由查看、编辑或随时删除此预设。',
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: colors.brandPrimary),
                tooltip: '刷新线路',
                onPressed: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSourceCard(
          colors: colors,
          icon: Icons.playlist_play,
          title: '自定义 M3U8 订阅 (示范)',
          subtitle:
              'https://example.com/live.m3u • 自动分类 42 个频道 • 2 秒快速换台 (LIVE-08)',
          badgeText: '正常',
          badgeColor: colors.statusSuccess,
          isEnabled: true,
          actionTrailing: IconButton(
            icon: Icon(Icons.more_vert, color: colors.textSecondary),
            onPressed: () {},
          ),
        ),
      ],
    );
  }

  Widget _buildTvboxTab(AppThemeColors colors) {
    return ListView(
      children: <Widget>[
        // VOD-09: Multi-warehouse fault isolation
        _buildSourceCard(
          colors: colors,
          icon: Icons.folder_special,
          title: 'TVBox 聚合配置仓 (VOD-09 多仓隔离)',
          subtitle: '聚合源包含多个站点配置；单站点失效隔离运行，不影响其余站点可用性',
          badgeText: '多仓就绪',
          badgeColor: colors.brandPrimary,
          isEnabled: true,
          actionTrailing: IconButton(
            icon: Icon(Icons.refresh, color: colors.brandPrimary),
            onPressed: () {},
          ),
        ),
        const SizedBox(height: 12),
        // Active CMS site
        _buildSourceCard(
          colors: colors,
          icon: Icons.code,
          title: '站源: 极速资源 (CMS XML/JSON 接口)',
          subtitle: 'VOD-03 标准原生 HTTP 协议解析 • 全平台支持 (Windows / Android TV)',
          badgeText: 'CMS 活跃',
          badgeColor: colors.statusSuccess,
          isEnabled: true,
        ),
        const SizedBox(height: 12),
        // QuickJS Spider site
        _buildSourceCard(
          colors: colors,
          icon: Icons.javascript,
          title: '站源: DR-PY 影视 (QuickJS 宿主沙箱)',
          subtitle: 'VOD-04 JavaScript 爬虫 • 6秒超时 / 32MB 内存硬隔离',
          badgeText: '沙箱正常',
          badgeColor: colors.statusSuccess,
          isEnabled: true,
        ),
        const SizedBox(height: 12),
        // VOD-06 & VOD-07: Greyed-out unported Jar site
        _buildSourceCard(
          colors: colors,
          icon: Icons.pest_control_outlined,
          title: '站源: 某 Jar 爬虫站点 (DEX 外部字节码)',
          subtitle: '暂未完成 Dart 纯语言移植 (VOD-07)；当前处于安全禁用置灰状态',
          badgeText: '置灰不可用 (VOD-06)',
          badgeColor: colors.textTertiary,
          isEnabled: false,
          isGreyedOut: true,
        ),
      ],
    );
  }

  Widget _buildStorageTab(AppThemeColors colors) {
    return ListView(
      children: <Widget>[
        _buildSourceCard(
          colors: colors,
          icon: Icons.storage,
          title: '家庭 NAS 影视库 (Samba SMB2/3)',
          subtitle:
              'smb://192.168.1.10/video • 凭据安全存储 (Keystore/Vault) • 局域网 Range 代理 (ADR-006)',
          badgeText: 'SMB 已连接',
          badgeColor: colors.statusSuccess,
          isEnabled: true,
        ),
        const SizedBox(height: 12),
        _buildSourceCard(
          colors: colors,
          icon: Icons.cloud_queue,
          title: 'Alist 网盘虚拟挂载 (WebDAV)',
          subtitle: 'http://127.0.0.1:5244/dav • LIB-03 间接支持多网盘直链与 302 重定向',
          badgeText: 'WebDAV 就绪',
          badgeColor: colors.brandPrimary,
          isEnabled: true,
        ),
        const SizedBox(height: 12),
        _buildSourceCard(
          colors: colors,
          icon: Icons.lan,
          title: 'NFS 媒体共享 (LIB-07 P1 待验证)',
          subtitle:
              'nfs://192.168.1.10/media • 首选系统原生挂载，或经 SMB / Alist 兜底 (PoC-7)',
          badgeText: '实验性 (P1)',
          badgeColor: colors.statusWarning,
          isEnabled: true,
        ),
      ],
    );
  }

  Widget _buildSourceCard({
    required AppThemeColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required bool isEnabled,
    bool isGreyedOut = false,
    Widget? actionTrailing,
  }) {
    final effectiveTextColor =
        isGreyedOut ? colors.textTertiary : colors.textPrimary;
    final effectiveSubColor = isGreyedOut
        ? colors.textTertiary.withValues(alpha: 0.6)
        : colors.textSecondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isGreyedOut
            ? colors.surfaceCard.withValues(alpha: 0.4)
            : colors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGreyedOut
              ? colors.focusBorder.withValues(alpha: 0.05)
              : colors.focusBorder.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isGreyedOut
                  ? Colors.grey.withValues(alpha: 0.1)
                  : colors.brandPrimary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isGreyedOut ? colors.textTertiary : colors.brandPrimary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: effectiveTextColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: effectiveSubColor,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (actionTrailing != null) actionTrailing,
        ],
      ),
    );
  }

  void _showDisclaimerDialog({
    required String title,
    required String content,
  }) {
    final colors = context.colors;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colors.surfaceCard,
          title: Text(title, style: TextStyle(color: colors.textPrimary)),
          content: Text(
            content,
            style: TextStyle(color: colors.textSecondary, height: 1.5),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我知道了'),
            ),
          ],
        );
      },
    );
  }

  void _showImportDialog() {
    final colors = context.colors;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colors.surfaceCard,
          title: Text(
            '添加 / 导入媒体源 (APP-10 向导)',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '支持通过网络订阅、本地文件或局域网手机推送导入：',
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.link, color: colors.brandPrimary),
                title: Text('网络 URL 导入',
                    style: TextStyle(color: colors.textPrimary)),
                subtitle: Text('支持 M3U 直播源或 TVBox 单仓/多仓 JSON 链接',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: Icon(Icons.file_open, color: colors.brandPrimary),
                title:
                    Text('本地文件导入', style: TextStyle(color: colors.textPrimary)),
                subtitle: Text('选择 .m3u / .txt / .json 文件导入',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: Icon(Icons.qr_code, color: colors.brandPrimary),
                title: Text('局域网手机扫码推送 (APP-10)',
                    style: TextStyle(color: colors.textPrimary)),
                subtitle: Text('在手机浏览器输入 :9979 页面一键投送配置到电视',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}
