import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/app/theme/theme_provider.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/i18n/locale_provider.dart';
import 'package:juying/core/proxy/local_proxy_server.dart';
import 'package:juying/features/download/presentation/download_page.dart';
import 'package:juying/features/live/services/iptv_service.dart';
import 'package:juying/features/sync/services/webdav_credential_store.dart';
import 'package:juying/features/sync/services/webdav_sync_coordinator.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/models/tvbox_subscription.dart';
import 'package:juying/features/tvbox/providers/tvbox_provider.dart';
import 'package:juying/features/tvbox/services/tvbox_config_service.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// Settings and configuration hub for multi-theme, multi-language, and TVBox subscriptions.
///
/// **What**: Manages visual theme presets, international language localizations, hardware decoding,
/// WebDAV credentials, and TVBox multi-source subscriptions.
///
/// **Why**: Providing instant reactive hot-swapping of themes and locales without app reloads
/// delivers an effortless user experience across TV remotes, desktop monitors, and mobile displays.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final WebDavCredentialStore _webDavCredentialStore =
      SecureWebDavCredentialStore();
  bool _hardwareDecoding = true;
  bool _ipv6Preferred = true;
  bool _autoFailover = true;
  bool _lowPerformanceMode = false;
  bool _dualEngineMedia3 = true;
  bool _allowAndroidDexFallback = false;
  bool _lanGatewayEnabled = false;
  String? _lanGatewayAddress;

  String _currentWebDavStatus = '未配置';
  StreamSubscription<Map<String, dynamic>>? _remoteConfigSubscription;

  @override
  void initState() {
    super.initState();
    _loadSettingsFromStorage();
    _listenRemoteConfigPush();
  }

  Future<void> _loadSettingsFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    WebDavCredentials? webDavCredentials;
    try {
      webDavCredentials =
          await _webDavCredentialStore.read(legacyPreferences: prefs);
    } catch (error) {
      debugPrint('[Settings] WebDAV credential migration failed: $error');
    }
    if (mounted) {
      setState(() {
        _hardwareDecoding = prefs.getBool('pref_hardware_decoding') ?? true;
        _ipv6Preferred = prefs.getBool('pref_ipv6_preferred') ?? true;
        _autoFailover = prefs.getBool('pref_auto_failover') ?? true;
        _lowPerformanceMode =
            prefs.getBool('pref_low_performance_mode') ?? false;
        _dualEngineMedia3 = prefs.getBool('pref_dual_engine_media3') ?? true;
        _allowAndroidDexFallback =
            prefs.getBool('pref_android_dex_fallback') ?? false;
        ref.read(lowPerformanceModeProvider.notifier).state =
            _lowPerformanceMode;
        if (webDavCredentials != null) {
          _currentWebDavStatus = '已连接 (${webDavCredentials.username})';
        }
      });
    }
  }

  Future<void> _saveBoolPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _toggleLanGateway() async {
    final gateway = LocalProxyServer.instance.gateway;
    if (_lanGatewayEnabled) {
      await gateway.stop();
      if (!mounted) return;
      setState(() {
        _lanGatewayEnabled = false;
        _lanGatewayAddress = null;
      });
      return;
    }

    final started = await LocalProxyServer.instance.startLanGateway();
    String? address;
    if (started) {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final candidate in interface.addresses) {
          if (!candidate.isLoopback) {
            address = candidate.address;
            break;
          }
        }
        if (address != null) break;
      }
    }
    if (!mounted) return;
    setState(() {
      _lanGatewayEnabled = started;
      _lanGatewayAddress = address;
    });
    if (!started) _showToast('❌ 局域网门户启动失败，请检查 9979 端口');
  }

  void _listenRemoteConfigPush() {
    _remoteConfigSubscription =
        LocalProxyServer.instance.remoteConfigStream.listen((event) {
      if (!mounted) return;
      final type = event['type']?.toString();
      final payload = event['payload'] as Map<String, dynamic>?;

      if (type == 'config' && payload != null) {
        final url = payload['url']?.toString() ?? '';
        _showToast('📱 收到手机推送配置: $url');
        _loadTvBoxUrl(url);
      } else if (type == 'stream' && payload != null) {
        final url = payload['url']?.toString() ?? '';
        _showToast('📱 收到手机推送视频: $url');
      }
    });
  }

  @override
  void dispose() {
    unawaited(_remoteConfigSubscription?.cancel());
    super.dispose();
  }

  Future<void> _loadTvBoxUrl(String url, {bool openAfterImport = false}) async {
    final configService = TvBoxConfigService();
    final cfg = await configService.loadConfig(url);
    if (cfg == null || !mounted) {
      _showToast('❌ ${configService.lastError ?? 'TVBox 订阅解析失败'}');
      return;
    }
    if (!mounted) return;
    // 导入只负责解析和注册。第三方 CMS 的 TLS、可用性与分类接口必须在用户
    // 主动选择后才访问，避免一个失效源拖慢整个订阅导入。
    final subscription = ref.read(tvBoxSubscriptionsProvider.notifier).upsert(
          url: url,
          sites: cfg.sites,
          preserveMissing: cfg.isPartial,
        );
    final supported = subscription.sites
        .where((site) => site.isRuntimeSupported)
        .toList(growable: false);
    final unsupportedCount = subscription.sites.length - supported.length;
    final refreshNote = cfg.isPartial
        ? '\n${context.tr('settings_tvbox_partial_refresh')}'
        : '';
    _showToast(
      '✅ 已添加订阅“${subscription.name}”，共 ${subscription.sites.length} 个站点，'
      '可用 ${supported.length} 个'
      '${unsupportedCount > 0 ? '，$unsupportedCount 个 Spider 待沙箱支持' : ''}'
      '$refreshNote',
    );
    if (openAfterImport && supported.isNotEmpty && mounted) {
      final runnable = subscription.sites
          .where((site) => site.isRuntimeSupported)
          .toList(growable: false)
        ..sort(
          (left, right) => _siteActivationPriority(left)
              .compareTo(_siteActivationPriority(right)),
        );
      final selected = runnable.first;
      ref.read(activeTvBoxSiteProvider.notifier).selectSite(selected);
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
      context.go('/');
    }
  }

  int _siteActivationPriority(TvBoxSite site) {
    if (site.type == 3 && site.api.toLowerCase() == 'csp_bili') return 0;
    if (site.type == 4 && site.key != 'cctv_vod') return 1;
    if (site.type == 0 || site.type == 1) return 2;
    return 3;
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 2500),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeTheme = ref.watch(themeProvider);
    final activeLocale = ref.watch(localeProvider);
    final subscriptions = ref.watch(tvBoxSubscriptionsProvider);
    final activeSite = ref.watch(activeTvBoxSiteProvider);

    return Scaffold(
      backgroundColor: colors.backgroundDeep,
      body: Row(
        children: <Widget>[
          // Left Settings Menu List
          Expanded(
            flex: 3,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: <Widget>[
                Text(
                  context.tr('settings_title'),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // Section 1: 界面个性化与多语言 (Appearance & Language)
                _buildSectionHeader(
                    colors, context.tr('settings_section_appearance')),
                _buildActionTile(
                  colors,
                  title: context.tr('settings_theme'),
                  subtitle: activeTheme.label,
                  icon: Icons.palette_outlined,
                  onTap: () => _showThemePickerModal(activeTheme),
                ),
                _buildActionTile(
                  colors,
                  title: context.tr('settings_language'),
                  subtitle: activeLocale.label,
                  icon: Icons.language_outlined,
                  onTap: () => _showLanguagePickerModal(activeLocale),
                ),

                const SizedBox(height: 24),

                // Section 2: 媒体源与 TVBox 订阅 (Sources & Subscriptions)
                _buildSectionHeader(
                    colors, context.tr('settings_section_sources')),
                _buildActionTile(
                  colors,
                  title: context.tr('settings_tvbox_config'),
                  subtitle: '主源: ${activeSite.name} '
                      '(已添加 ${subscriptions.where((item) => !item.isBuiltIn).length} 个订阅)',
                  icon: Icons.subscriptions_outlined,
                  onTap: () =>
                      _showTvBoxManagerModal(subscriptions, activeSite),
                ),
                _buildActionTile(
                  colors,
                  title: context.tr('settings_iptv_config'),
                  subtitle: '已加载 央视频道 / 地方卫视 (共 112 个频道)',
                  icon: Icons.live_tv_outlined,
                  onTap: _showAddIptvDialog,
                ),
                _buildActionTile(
                  colors,
                  title: context.tr('settings_webdav_config'),
                  subtitle: '当前状态: $_currentWebDavStatus (坚果云/Alist/Nextcloud)',
                  icon: Icons.cloud_sync_outlined,
                  onTap: _showWebDavDialog,
                ),
                _buildActionTile(
                  colors,
                  title: '离线缓存下载管理',
                  subtitle: '查看、暂停、继续分段下载任务与本地离线播放',
                  icon: Icons.download_done_outlined,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const DownloadPage(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Section 3: 播放内核与解码策略 (Playback & Decoding)
                _buildSectionHeader(
                    colors, context.tr('settings_section_playback')),
                _buildSwitchTile(
                  colors,
                  title: context.tr('settings_hardware_decoding'),
                  subtitle: context.tr('settings_hardware_decoding_sub'),
                  value: _hardwareDecoding,
                  onChanged: (val) {
                    setState(() => _hardwareDecoding = val);
                    _saveBoolPref('pref_hardware_decoding', val);
                  },
                ),
                _buildSwitchTile(
                  colors,
                  title: context.tr('settings_ipv6_preferred'),
                  subtitle: context.tr('settings_ipv6_preferred_sub'),
                  value: _ipv6Preferred,
                  onChanged: (val) {
                    setState(() => _ipv6Preferred = val);
                    _saveBoolPref('pref_ipv6_preferred', val);
                  },
                ),
                _buildSwitchTile(
                  colors,
                  title: context.tr('settings_auto_failover'),
                  subtitle: context.tr('settings_auto_failover_sub'),
                  value: _autoFailover,
                  onChanged: (val) {
                    setState(() => _autoFailover = val);
                    _saveBoolPref('pref_auto_failover', val);
                  },
                ),
                _buildSwitchTile(
                  colors,
                  title: '自适应低性能模式 (APP-13 / R15)',
                  subtitle: '针对低端盒子与老旧设备，自动将毛玻璃实时模糊降级为纯色半透明，确保 60fps 交互',
                  value: _lowPerformanceMode,
                  onChanged: (val) {
                    setState(() => _lowPerformanceMode = val);
                    ref.read(lowPerformanceModeProvider.notifier).state = val;
                    _saveBoolPref('pref_low_performance_mode', val);
                  },
                ),
                _buildSwitchTile(
                  colors,
                  title: 'Android TV 双引擎调度 (PLY-13 / ADR-002)',
                  subtitle:
                      '对 4K、HDR 与杜比视界 (Dolby Vision) / 杜比全景声优先调用 Media3 原生硬件解调',
                  value: _dualEngineMedia3,
                  onChanged: (val) {
                    setState(() => _dualEngineMedia3 = val);
                    _saveBoolPref('pref_dual_engine_media3', val);
                  },
                ),
                _buildSwitchTile(
                  colors,
                  title: 'TVBox 原生 DEX 爬虫兜底 (ADR-008 & ADR-014)',
                  subtitle: '仅作为未移植纯 Dart 爬虫站点的实验性兜底 (默认关闭，需用户明确安全警示)',
                  value: _allowAndroidDexFallback,
                  onChanged: (val) {
                    if (val) {
                      _promptDexDisclaimerDialog();
                    } else {
                      setState(() => _allowAndroidDexFallback = false);
                      _saveBoolPref('pref_android_dex_fallback', false);
                    }
                  },
                ),
              ],
            ),
          ),

          // Right Remote Web Portal Panel
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.surfaceElevation,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (_lanGatewayEnabled && _lanGatewayAddress != null)
                    Semantics(
                      label: '局域网远程配置门户二维码',
                      image: true,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: QrImageView(
                            data: Uri(
                              scheme: 'http',
                              host: _lanGatewayAddress,
                              port: 9979,
                              path: '/',
                              queryParameters: <String, String>{
                                'code': LocalProxyServer
                                    .instance.gateway.pairingCode!,
                              },
                            ).toString(),
                            size: 120,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.qr_code_2,
                      size: 140,
                      color: colors.focusBorder,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('settings_remote_portal'),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('settings_remote_portal_sub'),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.surfaceElevation,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _lanGatewayEnabled
                          ? 'http://${_lanGatewayAddress ?? '本机局域网地址'}:9979'
                          : '本机 Range 代理：127.0.0.1:9978（不对外开放）',
                      style: TextStyle(
                        color: colors.brandAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (_lanGatewayEnabled) ...<Widget>[
                    const SizedBox(height: 12),
                    SelectableText(
                      '配对码：${LocalProxyServer.instance.gateway.pairingCode}',
                      style: TextStyle(
                        color: colors.focusBorder,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Push API 会话 30 分钟后失效',
                      style:
                          TextStyle(color: colors.textTertiary, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _toggleLanGateway,
                    icon: Icon(
                      _lanGatewayEnabled ? Icons.lock : Icons.lan,
                    ),
                    label: Text(
                      _lanGatewayEnabled ? '关闭局域网门户' : '开启局域网门户',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('settings_remote_portal_desc'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptDexDisclaimerDialog() async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceCard,
        title: Row(
          children: <Widget>[
            Icon(Icons.security, color: colors.statusWarning),
            const SizedBox(width: 8),
            Text(
              '第三方 DEX 运行时安全警示',
              style: TextStyle(color: colors.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          '开启此项后，应用将在 Android 端通过 DexClassLoader 动态加载外部 TVBox 订阅中的 spider.jar 二进制字节码。\n\n'
          '外部字节码可能包含未经验证的网络请求或资源消耗。聚映对此类第三方代码不提供安全审计与保证。\n\n'
          '是否确认开启该实验性兜底？',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.brandPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认开启', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _allowAndroidDexFallback = true);
      await _saveBoolPref('pref_android_dex_fallback', true);
      _showToast('⚠️ 已开启第三方 DEX 运行时兜底');
    }
  }

  void _showThemePickerModal(AppThemePreset activeTheme) {
    final colors = context.colors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surfaceCard,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '选择界面主题风格',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: AppThemePreset.values.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final preset = AppThemePreset.values[index];
                    final isSelected = preset == activeTheme;

                    return TvFocusWrapper(
                      onTap: () {
                        ref.read(themeProvider.notifier).setTheme(preset);
                        Navigator.of(context).pop();
                        _showToast('🎨 已切换至主题: ${preset.label}');
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
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: preset.colors.backgroundDeep,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: preset.colors.brandPrimary,
                                    width: 2),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                preset.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? colors.textPrimary
                                      : colors.textSecondary,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check, color: colors.focusBorder),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLanguagePickerModal(AppLanguage activeLocale) {
    final colors = context.colors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surfaceCard,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '选择显示语言 (Display Language)',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: AppLanguage.values.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final lang = AppLanguage.values[index];
                    final isSelected = lang == activeLocale;

                    return TvFocusWrapper(
                      onTap: () {
                        ref.read(localeProvider.notifier).setLanguage(lang);
                        Navigator.of(context).pop();
                        _showToast('🌐 已切换语言: ${lang.label}');
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
                              Icons.translate,
                              color: isSelected
                                  ? colors.brandAccent
                                  : colors.textTertiary,
                              size: 20,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                lang.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? colors.textPrimary
                                      : colors.textSecondary,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check, color: colors.focusBorder),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTvBoxManagerModal(
    List<TvBoxSubscription> subscriptions,
    TvBoxSite activeSite,
  ) {
    final colors = context.colors;
    final controller = TextEditingController();
    final visibleSubscriptions = List<TvBoxSubscription>.from(subscriptions);
    var displayedActiveSite = activeSite;
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
                      if (selected != null) ...<Widget>[
                        IconButton(
                          onPressed: () => setModalState(
                            () => selectedSubscription = null,
                          ),
                          icon: Icon(
                            Icons.arrow_back,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          selected?.name ?? 'TVBox 订阅管理',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (selected == null)
                        TvFocusWrapper(
                          onTap: () => _showAddWarehouseDialog(controller),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colors.brandPrimary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: <Widget>[
                                Icon(Icons.add, color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  '导入订阅',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    selected == null
                        ? '每个地址只显示一条订阅，点击进入查看内部站点'
                        : '共 ${selected.sites.length} 个站点，'
                            '可用 ${selected.supportedSiteCount} 个',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: selected == null
                        ? _buildSubscriptionList(
                            colors,
                            visibleSubscriptions,
                            displayedActiveSite,
                            onOpen: (subscription) => setModalState(
                              () => selectedSubscription = subscription,
                            ),
                            onDelete: (subscription) async {
                              final confirmed =
                                  await _confirmSubscriptionDelete(
                                context,
                                subscription,
                              );
                              if (!confirmed || !context.mounted) return;
                              ref
                                  .read(tvBoxSubscriptionsProvider.notifier)
                                  .remove(subscription.id);
                              setModalState(() {
                                visibleSubscriptions.removeWhere(
                                  (item) => item.id == subscription.id,
                                );
                                displayedActiveSite = ref.read(
                                  activeTvBoxSiteProvider,
                                );
                              });
                              _showToast('已删除订阅：${subscription.name}');
                            },
                          )
                        : _buildSubscriptionSiteList(
                            colors,
                            selected,
                            displayedActiveSite,
                            context,
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

  Widget _buildSubscriptionList(
    AppThemeColors colors,
    List<TvBoxSubscription> subscriptions,
    TvBoxSite activeSite, {
    required ValueChanged<TvBoxSubscription> onOpen,
    required ValueChanged<TvBoxSubscription> onDelete,
  }) {
    return ListView.separated(
      itemCount: subscriptions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final subscription = subscriptions[index];
        final isActive = subscription.sites.any(
          (site) => site.key == activeSite.key,
        );
        return TvFocusWrapper(
          onTap: () => onOpen(subscription),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isActive
                  ? colors.brandPrimary.withAlpha(42)
                  : colors.surfaceElevation,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive ? colors.brandPrimary : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  subscription.isBuiltIn
                      ? Icons.verified_outlined
                      : Icons.subscriptions_outlined,
                  color: isActive ? colors.focusBorder : colors.textTertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        subscription.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${subscription.sites.length} 个站点 · '
                        '${subscription.supportedSiteCount} 个可用',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!subscription.isBuiltIn) ...<Widget>[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '删除订阅',
                    onPressed: () => onDelete(subscription),
                    icon: Icon(
                      Icons.delete_outline,
                      color: colors.statusError,
                    ),
                  ),
                ],
                Icon(
                  Icons.chevron_right,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmSubscriptionDelete(
    BuildContext modalContext,
    TvBoxSubscription subscription,
  ) async {
    final colors = modalContext.colors;
    return await showDialog<bool>(
          context: modalContext,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: colors.surfaceCard,
            title: Text(
              '删除 TVBox 订阅',
              style: TextStyle(color: colors.textPrimary),
            ),
            content: Text(
              '确定删除“${subscription.name}”及其中的 '
              '${subscription.sites.length} 个站点吗？',
              style: TextStyle(color: colors.textSecondary),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildSubscriptionSiteList(
    AppThemeColors colors,
    TvBoxSubscription subscription,
    TvBoxSite activeSite,
    BuildContext modalContext,
  ) {
    return ListView.separated(
      itemCount: subscription.sites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final site = subscription.sites[index];
        final isSelected = site.key == activeSite.key;
        return TvFocusWrapper(
          onTap: () {
            if (!site.isRuntimeSupported) {
              _showToast('⚠️ ${site.spiderRuntimeCapability.reason}');
              return;
            }
            ref.read(activeTvBoxSiteProvider.notifier).selectSite(site);
            Navigator.of(modalContext).pop();
            this.context.go('/');
            _showToast('✅ 已进入 ${site.name}');
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.brandPrimary.withAlpha(50)
                  : colors.surfaceElevation,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? colors.brandPrimary : Colors.transparent,
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
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
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
        );
      },
    );
  }

  void _showAddWarehouseDialog(TextEditingController controller) {
    final colors = context.colors;
    final presets = <Map<String, String>>[
      <String, String>{'name': '🍚 饭太硬', 'url': 'http://饭太硬.top/tv'},
      <String, String>{'name': '🔥 小胡4K', 'url': 'http://xhztv.top/4k.json'},
      <String, String>{'name': '🐱 肥猫', 'url': 'http://肥猫.com'},
      <String, String>{
        'name': '✨ 巧儿',
        'url': 'http://pandown.pro/tvbox/tvbox.json'
      },
      <String, String>{
        'name': '🎬 业余打发',
        'url': 'https://raw.liucn.cc/box/m.json'
      },
    ];

    unawaited(showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: colors.surfaceCard,
          title: Text('导入 TVBox 接口订阅仓',
              style: TextStyle(color: colors.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('支持单仓/多仓 JSON、dc.txt 以及加密订阅地址：',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                Text('快速选择常用公共订阅源：',
                    style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presets.map((p) {
                    return ActionChip(
                      label: Text(p['name']!,
                          style: TextStyle(
                              color: colors.brandAccent, fontSize: 12)),
                      backgroundColor: colors.surfaceElevation,
                      onPressed: () {
                        controller.text = p['url']!;
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'http://.../tvbox.json',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    filled: true,
                    fillColor: colors.surfaceElevation,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: colors.brandPrimary),
              onPressed: () {
                final url = controller.text.trim();
                Navigator.of(dialogCtx).pop();
                if (url.isNotEmpty) {
                  _loadTvBoxUrl(url, openAfterImport: true);
                }
              },
              child: const Text('导入并解析', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ));
  }

  Future<void> _showAddIptvDialog() async {
    final colors = context.colors;
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('pref_iptv_playlist_url') ??
        'https://live.fanmingming.com/tv/m3u/global.m3u';
    final controller = TextEditingController(text: savedUrl);

    final presets = <Map<String, String>>[
      <String, String>{
        'name': '🌐 FanMingMing (全网IPv4/v6)',
        'url': 'https://live.fanmingming.com/tv/m3u/global.m3u',
      },
      <String, String>{
        'name': '🏛️ 央视精选专线',
        'url':
            'https://raw.githubusercontent.com/Ftindy/IPTV-URL/main/cctv.m3u',
      },
      <String, String>{
        'name': '📺 112114 高清卫视',
        'url': 'https://epg.112114.xyz/pp.m3u',
      },
      <String, String>{
        'name': '📡 FanMingMing (IPv6专线)',
        'url': 'https://live.fanmingming.com/tv/m3u/ipv6.m3u',
      },
    ];

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: colors.surfaceCard,
          title:
              Text('配置 IPTV 直播源', style: TextStyle(color: colors.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('输入 M3U / TXT 直播源在线链接：',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                Text('快速选择常用优质直播源：',
                    style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presets.map((p) {
                    return ActionChip(
                      label: Text(p['name']!,
                          style: TextStyle(
                              color: colors.brandAccent, fontSize: 11)),
                      backgroundColor: colors.surfaceElevation,
                      onPressed: () {
                        controller.text = p['url']!;
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'https://.../live.m3u',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    filled: true,
                    fillColor: colors.surfaceElevation,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: colors.brandPrimary),
              onPressed: () async {
                final url = controller.text.trim();
                Navigator.of(dialogCtx).pop();
                if (url.isNotEmpty) {
                  await prefs.setString('pref_iptv_playlist_url', url);
                  _showToast('⏳ 正在下载并解析 IPTV 直播源…');
                  final catalog = await IptvService().fetchRemoteCatalog(url);
                  if (catalog.channels.isNotEmpty) {
                    await IptvService().cacheCatalog(catalog.channels);
                    _showToast(
                        '✅ 成功加载 IPTV 直播源，已更新 ${catalog.channels.length} 个电视频道');
                  } else {
                    _showToast('⚠️ IPTV 直播源已保存，若格式特殊将在播放时自动适配');
                  }
                }
              },
              child: const Text('保存并解析', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showWebDavDialog() async {
    final colors = context.colors;
    final prefs = await SharedPreferences.getInstance();
    WebDavCredentials? credentials;
    try {
      credentials = await _webDavCredentialStore.read(legacyPreferences: prefs);
    } catch (error) {
      debugPrint('[Settings] Failed to read WebDAV credentials: $error');
    }
    final urlController = TextEditingController(
      text: credentials?.url ?? 'https://dav.jianguoyun.com/dav/',
    );
    final userController = TextEditingController(
      text: credentials?.username ?? '',
    );
    final passController = TextEditingController(
      text: credentials?.password ?? '',
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: colors.surfaceCard,
          title: Text('配置 WebDAV 多端双向同步',
              style: TextStyle(color: colors.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: urlController,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'WebDAV 服务端 URL',
                    labelStyle: TextStyle(color: colors.textSecondary),
                    filled: true,
                    fillColor: colors.surfaceElevation,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: userController,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: '用户名 / 邮箱',
                    labelStyle: TextStyle(color: colors.textSecondary),
                    filled: true,
                    fillColor: colors.surfaceElevation,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passController,
                  obscureText: true,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: '应用密码 / Token',
                    labelStyle: TextStyle(color: colors.textSecondary),
                    filled: true,
                    fillColor: colors.surfaceElevation,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
              ),
              onPressed: () async {
                final url = urlController.text.trim();
                final user = userController.text.trim();
                final pass = passController.text.trim();

                if (url.isEmpty || user.isEmpty || pass.isEmpty) {
                  _showToast('⚠️ 请填写完整的 WebDAV 认证信息');
                  return;
                }

                await _webDavCredentialStore.write(
                  WebDavCredentials(url: url, username: user, password: pass),
                  legacyPreferences: prefs,
                );

                final ok = await WebDavSyncCoordinator.instance.syncNow();

                if (dialogCtx.mounted) {
                  Navigator.of(dialogCtx).pop();
                }
                if (mounted) {
                  setState(() {
                    _currentWebDavStatus = ok ? '已连接 ($user)' : '连接失败';
                  });
                  _showToast(
                      ok ? '✅ WebDAV 双向同步完成' : '❌ WebDAV 同步失败，请检查 URL 与授权凭据');
                }
              },
              child: const Text(
                '立即同步',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(AppThemeColors colors, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    AppThemeColors colors, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return TvFocusWrapper(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: colors.brandPrimary,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(
    AppThemeColors colors, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return TvFocusWrapper(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              color: colors.brandAccent,
              size: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
