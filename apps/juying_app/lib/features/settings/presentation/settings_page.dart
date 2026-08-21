import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/app_strings.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../../application/playback/playback_telemetry.dart';
import '../../../domain/models/media_source.dart';
import '../../../domain/models/playlist_source.dart';
import '../../../domain/models/tvbox_source.dart';
import 'external_source_diagnostics_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.config,
    required this.settings,
    required this.sources,
    required this.onSourceEnabledChanged,
    required this.profileId,
    required this.onClearProfileData,
    required this.telemetry,
    this.onAddPlaylistSource,
    this.onAddTvboxSource,
    this.onRemovePlaylistSource,
    super.key,
  });
  final AppConfig config;
  final AppSettingsController settings;
  final List<MediaSource> sources;
  final Future<void> Function(String sourceId, bool enabled)
      onSourceEnabledChanged;
  final String profileId;
  final Future<void> Function(String profileId) onClearProfileData;
  final PlaybackTelemetry telemetry;
  final Future<void> Function(PlaylistSourceDefinition source)?
      onAddPlaylistSource;
  final Future<void> Function(TvboxSourceDefinition source)? onAddTvboxSource;
  final Future<void> Function(String sourceId)? onRemovePlaylistSource;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
      children: [
        Text(
          strings.settings,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 24),
        _GroupLabel(strings.appearanceAndLanguage),
        _SettingsCard(children: [
          _Setting(
            Icons.palette_rounded,
            strings.theme,
            _themeLabel(strings, settings.theme),
            onTap: () => _chooseTheme(context),
          ),
          const Divider(height: 1),
          _Setting(
            Icons.translate_rounded,
            strings.language,
            settings.locale.languageCode == 'en' ? 'English' : '简体中文',
            onTap: () => _chooseLocale(context),
          ),
        ]),
        const SizedBox(height: 24),
        _GroupLabel(strings.contentAndPlayback),
        _SettingsCard(children: [
          _Setting(
            Icons.public_rounded,
            strings.contentSources,
            strings.configuredSources(sources.length),
            onTap: () => _manageSources(context),
          ),
          const Divider(height: 1),
          _Setting(
            Icons.health_and_safety_outlined,
            strings.externalConfigDiagnostics,
            strings.externalConfigDiagnosticsHint,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const ExternalSourceDiagnosticsPage(),
            )),
          ),
          const Divider(height: 1),
          _Setting(Icons.high_quality_rounded, strings.playbackPreferences,
              strings.playbackPreferencesHint),
          const Divider(height: 1),
          _Setting(Icons.subtitles_rounded, strings.accessibility,
              strings.accessibilityHint),
          const Divider(height: 1),
          _Setting(
            Icons.monitor_heart_outlined,
            strings.playbackDiagnostics,
            strings.playbackDiagnosticsHint,
            onTap: () => _showDiagnostics(context),
          ),
        ]),
        const SizedBox(height: 24),
        _GroupLabel(strings.familyAndDevice),
        _SettingsCard(children: [
          _Setting(Icons.group_rounded, strings.familyMembers,
              strings.familyMembersHint),
          const Divider(height: 1),
          _Setting(Icons.devices_rounded, strings.devicesAndSync,
              strings.devicesAndSyncHint),
          const Divider(height: 1),
          _Setting(
            Icons.privacy_tip_rounded,
            strings.clearLocalProfileData,
            strings.clearLocalProfileDataHint,
            onTap: () => _confirmClearProfileData(context),
          ),
        ]),
      ],
    );
  }

  String _themeLabel(AppStrings strings, AppThemePreference preference) =>
      switch (preference) {
        AppThemePreference.system => strings.systemTheme,
        AppThemePreference.light => strings.lightTheme,
        AppThemePreference.dark => strings.darkTheme,
        AppThemePreference.highContrast => strings.highContrastTheme,
      };

  Future<void> _chooseTheme(BuildContext context) async {
    final strings = AppStrings.of(context);
    final selected = await showModalBottomSheet<AppThemePreference>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppThemePreference.values
              .map((preference) => ListTile(
                    title: Text(_themeLabel(strings, preference)),
                    trailing: settings.theme == preference
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.pop(context, preference),
                  ))
              .toList(),
        ),
      ),
    );
    if (selected != null) await settings.setTheme(selected);
  }

  Future<void> _chooseLocale(BuildContext context) async {
    final selected = await showModalBottomSheet<Locale>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: const Text('简体中文'),
            trailing: settings.locale.languageCode == 'zh'
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.pop(context, const Locale('zh', 'CN')),
          ),
          ListTile(
            title: const Text('English'),
            trailing: settings.locale.languageCode == 'en'
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.pop(context, const Locale('en')),
          ),
        ]),
      ),
    );
    if (selected != null) await settings.setLocale(selected);
  }

  Future<void> _manageSources(BuildContext context) async {
    final states = {for (final source in sources) source.id: source.enabled};
    final strings = AppStrings.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(strings.sourceManagement,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              if (onAddPlaylistSource != null)
                ListTile(
                  leading: const Icon(Icons.add_link_rounded),
                  title: const Text('添加 IPTV 直播来源'),
                  subtitle: const Text('支持 HTTP(S) 的 M3U、TXT 与分组 JSON 清单'),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () => _addPlaylistSource(context),
                ),
              if (onAddPlaylistSource != null)
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: const Text('添加 IPTV-ORG 直播来源'),
                  subtitle: const Text('使用公开的 HTTPS M3U 清单；导入前仍需确认内容权利'),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () => _addPlaylistSource(
                    context,
                    initialName: 'IPTV-ORG',
                    initialUrl: 'https://iptv-org.github.io/iptv/index.m3u',
                  ),
                ),
              if (onAddTvboxSource != null)
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('导入 TVBox 配置'),
                  subtitle: const Text('支持电影、剧集、综艺、动画及直连直播'),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () => _addTvboxSource(context),
                ),
              ...sources.map(
                (source) => SwitchListTile(
                    title: Text(source.name),
                    subtitle: Text(
                      (states[source.id] ?? source.enabled)
                          ? strings.sourceEnabled
                          : strings.sourceDisabled,
                    ),
                    value: states[source.id] ?? source.enabled,
                    onChanged: (enabled) async {
                      setModalState(() => states[source.id] = enabled);
                      await onSourceEnabledChanged(source.id, enabled);
                    },
                    secondary: source.kind == MediaSourceKind.custom &&
                            onRemovePlaylistSource != null
                        ? IconButton(
                            tooltip: '移除来源',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => _removePlaylistSource(
                              context,
                              source.id,
                            ),
                          )
                        : null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addPlaylistSource(
    BuildContext context, {
    String initialName = '',
    String initialUrl = 'https://',
  }) async {
    final draft = await showDialog<_PlaylistSourceDraft>(
      context: context,
      builder: (_) => _PlaylistSourceDialog(
        initialName: initialName,
        initialUrl: initialUrl,
      ),
    );
    if (draft == null || !context.mounted || onAddPlaylistSource == null) {
      return;
    }
    final uri = Uri.tryParse(draft.url.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !draft.rightsConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请使用不含账号的 HTTP(S) 清单地址，并确认内容权利')),
      );
      return;
    }
    try {
      await onAddPlaylistSource!(PlaylistSourceDefinition(
        id: 'playlist-${DateTime.now().microsecondsSinceEpoch}',
        name: draft.name.trim().isEmpty ? '我的直播清单' : draft.name.trim(),
        playlistUri: uri,
        rightsConfirmedAt: DateTime.now(),
      ));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('直播清单检测通过，已自动加入统一来源列表')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法添加 IPTV 清单：$error')),
      );
    }
  }

  Future<void> _removePlaylistSource(
    BuildContext context,
    String sourceId,
  ) async {
    final remove = onRemovePlaylistSource;
    if (remove == null) return;
    await remove(sourceId);
  }

  Future<void> _addTvboxSource(BuildContext context) async {
    final draft = await showDialog<_TvboxSourceDraft>(
      context: context,
      builder: (_) => const _TvboxSourceDialog(),
    );
    if (draft == null || !context.mounted || onAddTvboxSource == null) return;
    final uri = Uri.tryParse(draft.url.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !draft.rightsConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入不含账号的 HTTP(S) 配置地址，并确认内容权利')),
      );
      return;
    }
    try {
      await onAddTvboxSource!(TvboxSourceDefinition(
        id: 'tvbox-${DateTime.now().microsecondsSinceEpoch}',
        name: draft.name.trim().isEmpty ? 'TVBox 来源' : draft.name.trim(),
        configUri: uri,
        rightsConfirmedAt: DateTime.now(),
      ));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TVBox 来源已加入统一来源列表')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法导入 TVBox 配置：$error')),
      );
    }
  }

  Future<void> _confirmClearProfileData(BuildContext context) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.clearProfileDataTitle),
        content: Text(strings.clearProfileDataBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await onClearProfileData(profileId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.profileDataCleared)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.clearProfileDataFailed)),
      );
    }
  }

  Future<void> _showDiagnostics(BuildContext context) async {
    final strings = AppStrings.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: telemetry,
        builder: (context, _) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
                child: Row(children: [
                  Expanded(
                    child: Text(strings.playbackDiagnostics,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  TextButton(
                    onPressed:
                        telemetry.records.isEmpty ? null : telemetry.clear,
                    child: Text(strings.clearDiagnostics),
                  ),
                ]),
              ),
              if (telemetry.records.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(strings.noPlaybackDiagnostics),
                )
              else
                SizedBox(
                  height: 360,
                  child: ListView.builder(
                    itemCount: telemetry.records.length,
                    itemBuilder: (context, index) {
                      final entry = telemetry.records.reversed.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${_eventLabel(strings, entry.event)} · '
                          '${entry.mode == PlaybackTelemetryMode.native ? strings.nativePlayback : strings.officialPlayback}',
                        ),
                        subtitle: Text(
                          '${entry.sourceId} / ${entry.sourceEpisodeId}'
                          '${entry.errorCode == null ? '' : ' · ${entry.errorCode}'}',
                        ),
                        trailing: Text(
                          '${entry.recordedAt.hour.toString().padLeft(2, '0')}:${entry.recordedAt.minute.toString().padLeft(2, '0')}',
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _eventLabel(AppStrings strings, PlaybackTelemetryEvent event) =>
      switch (event) {
        PlaybackTelemetryEvent.opening =>
          strings.locale.languageCode == 'en' ? 'Opening' : '正在打开',
        PlaybackTelemetryEvent.ready =>
          strings.locale.languageCode == 'en' ? 'Ready' : '已就绪',
        PlaybackTelemetryEvent.failed =>
          strings.locale.languageCode == 'en' ? 'Failed' : '失败',
        PlaybackTelemetryEvent.qualityChanged =>
          strings.locale.languageCode == 'en' ? 'Quality changed' : '清晰度已切换',
        PlaybackTelemetryEvent.ended =>
          strings.locale.languageCode == 'en' ? 'Ended' : '播放结束',
      };
}

class _PlaylistSourceDraft {
  const _PlaylistSourceDraft({
    required this.name,
    required this.url,
    required this.rightsConfirmed,
  });

  final String name;
  final String url;
  final bool rightsConfirmed;
}

class _PlaylistSourceDialog extends StatefulWidget {
  const _PlaylistSourceDialog({
    this.initialName = '',
    this.initialUrl = '',
  });
  final String initialName;
  final String initialUrl;

  @override
  State<_PlaylistSourceDialog> createState() => _PlaylistSourceDialogState();
}

class _TvboxSourceDraft {
  const _TvboxSourceDraft(
      {required this.name, required this.url, required this.rightsConfirmed});
  final String name;
  final String url;
  final bool rightsConfirmed;
}

class _TvboxSourceDialog extends StatefulWidget {
  const _TvboxSourceDialog();
  @override
  State<_TvboxSourceDialog> createState() => _TvboxSourceDialogState();
}

class _TvboxSourceDialogState extends State<_TvboxSourceDialog> {
  final _name = TextEditingController(text: 'TVBox 来源');
  final _url = TextEditingController();
  var _rightsConfirmed = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('导入 TVBox 配置'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '来源名称')),
            TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'TVBox 配置地址',
                  hintText: 'https://example.com/config.json',
                )),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _rightsConfirmed,
              onChanged: (value) =>
                  setState(() => _rightsConfirmed = value ?? false),
              title: const Text('我确认有权访问和播放其中的直播及点播内容'),
              subtitle: const Text(
                  '支持 lives 直连直播和标准 XML/JSON sites；动态脚本、解析器和代理规则不会导入。'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: _rightsConfirmed
                ? () => Navigator.pop(
                    context,
                    _TvboxSourceDraft(
                        name: _name.text,
                        url: _url.text,
                        rightsConfirmed: true))
                : null,
            child: const Text('检测并导入'),
          ),
        ],
      );
}

class _PlaylistSourceDialogState extends State<_PlaylistSourceDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _url = TextEditingController(text: widget.initialUrl);
  var _rightsConfirmed = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('添加 IPTV 直播来源'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '来源名称'),
            ),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'HTTP(S) 清单地址',
                hintText: 'https://example.com/playlist.m3u',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _rightsConfirmed,
              onChanged: (value) =>
                  setState(() => _rightsConfirmed = value ?? false),
              title: const Text('我确认有权访问和播放此清单中的内容'),
              subtitle: const Text('支持 M3U、TXT 和分组 JSON；不导入脚本、解析器或 Cookie。'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _rightsConfirmed
                ? () => Navigator.pop(
                      context,
                      _PlaylistSourceDraft(
                        name: _name.text,
                        url: _url.text,
                        rightsConfirmed: _rightsConfirmed,
                      ),
                    )
                : null,
            child: const Text('检测并自动添加'),
          ),
        ],
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      );
}

class _Setting extends StatelessWidget {
  const _Setting(this.icon, this.title, this.subtitle, {this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          fontSize: 12,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
      ),
      onTap: onTap,
    );
  }
}
