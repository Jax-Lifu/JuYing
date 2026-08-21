import 'package:flutter/material.dart';

import '../../../application/nas/nas_connection_store.dart';
import '../../../application/nas/nas_credential_store.dart';
import '../../../application/playback/playback_launcher.dart';
import '../../../application/playback/playback_preference_store.dart';
import '../../../application/policy/media_access_policy.dart';
import '../../../application/policy/source_policy.dart';
import '../../../domain/models/nas_connection.dart';
import '../../../domain/models/media_source.dart';
import '../../../domain/models/playlist_source.dart';
import '../../../domain/models/unified_media.dart' hide MediaCatalogPage;
import '../../../domain/ports/media_source_adapter.dart';
import '../../../domain/ports/catalog_initial_category.dart';
import '../../../domain/ports/source_catalog_tabs.dart';
import '../../../infrastructure/nas/nas_media_adapter.dart';
import '../../../infrastructure/nas/webdav_connection_service.dart';
import '../../media/presentation/media_catalog_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    required this.connectionStore,
    required this.credentialStore,
    required this.webDavService,
    required this.profileId,
    required this.isChildProfile,
    required this.playbackLauncher,
    required this.playlistSources,
    required this.onAddPlaylistSource,
    required this.onRemovePlaylistSource,
    super.key,
  });

  final NasConnectionStore connectionStore;
  final NasCredentialStore credentialStore;
  final WebDavConnectionService webDavService;
  final String profileId;
  final bool isChildProfile;
  final PlaybackLauncher playbackLauncher;
  final List<MediaSourceAdapter> playlistSources;
  final Future<void> Function(PlaylistSourceDefinition source)
      onAddPlaylistSource;
  final Future<void> Function(String sourceId) onRemovePlaylistSource;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final PlaybackPreferenceStore _preferenceStore = PlaybackPreferenceStore();
  late Future<List<NasConnection>> _connections = widget.connectionStore.load();

  void _reload() =>
      setState(() => _connections = widget.connectionStore.load());

  Future<void> _configureWebDav() async {
    final draft = await showDialog<_WebDavDraft>(
      context: context,
      builder: (_) => const _WebDavDialog(),
    );
    if (draft == null || !mounted) return;
    final endpoint = Uri.tryParse(draft.endpoint.trim());
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入不含账号信息的 HTTPS WebDAV 地址')),
      );
      return;
    }
    final id = 'webdav-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final credentials = NasCredentials(
        username: draft.username.trim(),
        password: draft.password,
      );
      final ref = await widget.credentialStore.save(
        connectionId: id,
        credentials: credentials,
      );
      final connection = NasConnection(
        id: id,
        name: draft.name.trim().isEmpty ? '家庭 WebDAV' : draft.name.trim(),
        protocol: NasProtocol.webDav,
        endpoint: endpoint,
        credentialsRef: ref,
      );
      final check = await widget.webDavService.verify(
        connection: connection,
        credentials: credentials,
      );
      if (!mounted) return;
      if (check != NasConnectionCheck.available) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_checkMessage(check))),
        );
        return;
      }
      await widget.connectionStore.upsert(NasConnection(
        id: connection.id,
        name: connection.name,
        protocol: connection.protocol,
        endpoint: connection.endpoint,
        credentialsRef: connection.credentialsRef,
        lastVerifiedAt: DateTime.now(),
      ));
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV 已连接。当前仅保存连接，不会扫描私有目录。')),
      );
    } on ArgumentError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写 NAS 用户名和密码')),
        );
      }
    }
  }

  Future<void> _configureSmbNfs() async {
    final draft = await showDialog<_SmbNfsDraft>(
      context: context,
      builder: (_) => const _SmbNfsDialog(),
    );
    if (draft == null || !mounted) return;
    final uri = Uri.tryParse(draft.endpoint.trim());
    if (uri == null ||
        (uri.scheme != 'smb' && uri.scheme != 'nfs') ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入合法的 smb:// 或 nfs:// 共享地址')),
      );
      return;
    }
    final protocol = uri.scheme == 'smb' ? NasProtocol.smb : NasProtocol.nfs;
    final id = '${protocol.name}-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final credentials = NasCredentials(
        username: draft.username.trim(),
        password: draft.password,
      );
      final ref = await widget.credentialStore.save(
        connectionId: id,
        credentials: credentials,
      );
      final connection = NasConnection(
        id: id,
        name: draft.name.trim().isEmpty
            ? (protocol == NasProtocol.smb ? 'Samba 共享' : 'NFS 共享')
            : draft.name.trim(),
        protocol: protocol,
        endpoint: uri,
        credentialsRef: ref,
        lastVerifiedAt: DateTime.now(),
      );
      await widget.connectionStore.upsert(connection);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${connection.name} 已添加')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存网络共享失败：$e')),
        );
      }
    }
  }

  Future<void> _configurePlaylist() async {
    final draft = await showDialog<_PlaylistDraft>(
      context: context,
      builder: (_) => const _PlaylistDialog(),
    );
    if (draft == null || !mounted) return;
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
    final id = 'playlist-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await widget.onAddPlaylistSource(PlaylistSourceDefinition(
        id: id,
        name: draft.name.trim().isEmpty ? '我的直播清单' : draft.name.trim(),
        playlistUri: uri,
        rightsConfirmedAt: DateTime.now(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IPTV 来源已验证并加入统一来源列表')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法添加 IPTV 清单：$error')),
      );
    }
  }

  String _checkMessage(NasConnectionCheck check) => switch (check) {
        NasConnectionCheck.unauthorized => 'WebDAV 认证失败，请检查账号和密码',
        NasConnectionCheck.unreachable => '无法连接 WebDAV，请检查地址和网络',
        NasConnectionCheck.unsupported => '该地址未返回可用的 WebDAV 响应',
        NasConnectionCheck.available => '连接成功',
      };

  Future<void> _openConnection(NasConnection connection) async {
    if (widget.isChildProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('儿童档案暂不能浏览未分级的 NAS 私有媒体')),
      );
      return;
    }
    final credentials = await widget.credentialStore.read(
      connection.credentialsRef,
    );
    if (!mounted) return;
    if (credentials == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到 NAS 凭据，请重新配置该连接')),
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MediaCatalogPage(
        adapter: NasMediaAdapter(
          connection: connection,
          credentials: credentials,
          webDavService: widget.webDavService,
        ),
        profileId: widget.profileId,
        isChildProfile: widget.isChildProfile,
        playbackLauncher: widget.playbackLauncher,
        initialCategory: MediaCategory.other,
      ),
    ));
  }

  static const _programCategories = {
    MediaCategory.movie,
    MediaCategory.drama,
    MediaCategory.animation,
    MediaCategory.documentary,
    MediaCategory.variety,
    MediaCategory.kids,
    MediaCategory.other,
  };

  bool _supportsCategory(
    MediaSourceAdapter adapter,
    bool Function(MediaCategory category) predicate,
  ) {
    if (adapter is SourceCatalogTabs) {
      return (adapter as SourceCatalogTabs)
          .primaryTabs
          .any((tab) => predicate(tab.category));
    }
    return predicate(adapter is CatalogInitialCategory
        ? (adapter as CatalogInitialCategory).initialCatalogCategory
        : MediaCategory.other);
  }

  List<MediaSourceAdapter> get _programSources => widget.playlistSources
      .where((adapter) => _supportsCategory(
            adapter,
            (category) => _programCategories.contains(category),
          ))
      .toList(growable: false);

  List<MediaSourceAdapter> get _liveSources => widget.playlistSources
      .where((adapter) =>
          adapter.source.capabilities.contains(SourceCapability.liveCatalog) ||
          _supportsCategory(
              adapter, (category) => category == MediaCategory.live))
      .toList(growable: false);

  Future<void> _openLiveDirectly(MediaSourceAdapter adapter) async {
    final decision = MediaAccessPolicy.evaluateSource(
      adapter.source,
      SourceAction.browse,
      context: MediaAccessContext(isChildProfile: widget.isChildProfile),
      explicitSourceSelection: true,
    );
    if (!decision.allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(decision.reason ?? '当前档案不可浏览该直播来源')),
      );
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

      // Check last watched live channel
      final lastChannelId = await _preferenceStore.getLastLiveChannel(
        profileId: widget.profileId,
        sourceId: adapter.source.id,
      );

      // Find target channel: 1) last saved channel, 2) CCTV-1, 3) first channel
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
                childDailyLimitMinutes: null,
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
                childDailyLimitMinutes: null,
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

  Future<void> _openSource(
    MediaSourceAdapter adapter, {
    required bool live,
  }) async {
    if (widget.isChildProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('儿童档案不能浏览未分级的自定义直播清单')),
      );
      return;
    }
    if (live) {
      await _openLiveDirectly(adapter);
      return;
    }
    final CatalogInitialCategory? catalogAdapter =
        adapter is CatalogInitialCategory
            ? adapter as CatalogInitialCategory
            : null;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MediaCatalogPage(
        adapter: adapter,
        profileId: widget.profileId,
        isChildProfile: widget.isChildProfile,
        playbackLauncher: widget.playbackLauncher,
        initialCategory: catalogAdapter != null &&
                _programCategories
                    .contains(catalogAdapter.initialCatalogCategory)
            ? catalogAdapter.initialCatalogCategory
            : MediaCategory.movie,
        allowedCategories: _programCategories,
      ),
    ));
  }

  Future<void> _removePlaylist(MediaSourceAdapter adapter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除自定义来源？'),
        content: Text('将移除“${adapter.source.name}”的来源配置，不会删除任何媒体内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onRemovePlaylistSource(adapter.source.id);
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('家庭媒体库',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('管理自有文件、NAS、Samba、NFS 与家庭媒体服务器。'),
          const SizedBox(height: 28),
          _Connector(
            'WebDAV',
            '先连接并验证 HTTPS WebDAV；凭据仅保存在系统安全存储。',
            Icons.cloud_rounded,
            onPressed: _configureWebDav,
          ),
          _Connector(
            'Samba (SMB) / NFS',
            '支持局域网 Samba 共享与 NFS 媒体流，直连原生高速播放。',
            Icons.folder_shared_rounded,
            onPressed: _configureSmbNfs,
          ),
          _Connector(
            'IPTV 直播清单',
            '支持用户自有或已获得授权的 HTTP(S) M3U、TXT 与分组 JSON 清单；TVBox 配置可在“设置 → 内容来源”中导入。',
            Icons.live_tv_rounded,
            onPressed: _configurePlaylist,
          ),
          const _Connector(
            'Jellyfin / Plex / Emby',
            '媒体服务器适配器，待来源契约扩展后开放。',
            Icons.dns_rounded,
          ),
          const SizedBox(height: 26),
          Text('已验证连接', style: Theme.of(context).textTheme.titleLarge),
          FutureBuilder<List<NasConnection>>(
            future: _connections,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final connections = snapshot.data ?? const [];
              if (connections.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('尚未添加 NAS / 网络共享连接。'),
                );
              }
              return Column(
                children: connections
                    .map((connection) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            connection.protocol == NasProtocol.webDav
                                ? Icons.cloud_done_rounded
                                : Icons.folder_copy_rounded,
                          ),
                          title: Text(connection.name),
                          subtitle: Text(
                            '${connection.protocol.name.toUpperCase()} · ${connection.endpoint.host} · 已安全保存凭据',
                          ),
                          trailing: const Icon(Icons.verified_rounded),
                          onTap: () => _openConnection(connection),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          Text('节目来源', style: Theme.of(context).textTheme.titleLarge),
          if (_programSources.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('尚未添加可用节目来源。'),
            )
          else
            ..._programSources.map(
              (adapter) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.movie_filter_rounded),
                title: Text(adapter.source.name),
                subtitle: Text(
                  '${adapter.source.capabilities.contains(SourceCapability.search) ? '可搜索' : '不可搜索'} · ${adapter.source.health.name}',
                ),
                trailing: adapter.source.id.startsWith('playlist-') ||
                        adapter.source.id.startsWith('tvbox-')
                    ? IconButton(
                        tooltip: '移除来源',
                        onPressed: () => _removePlaylist(adapter),
                        icon: const Icon(Icons.delete_outline_rounded),
                      )
                    : null,
                onTap: adapter.source.isActive
                    ? () => _openSource(adapter, live: false)
                    : null,
              ),
            ),
          const SizedBox(height: 20),
          Text('直播来源', style: Theme.of(context).textTheme.titleLarge),
          if (_liveSources.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('尚未添加可用直播来源。'),
            )
          else
            ..._liveSources.map(
              (adapter) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.live_tv_rounded),
                title: Text(adapter.source.name),
                subtitle: Text(
                  '${adapter.source.capabilities.contains(SourceCapability.search) ? '可搜索' : '不可搜索'} · 点击直接进入直播',
                ),
                trailing: adapter.source.id.startsWith('playlist-') ||
                        adapter.source.id.startsWith('tvbox-')
                    ? IconButton(
                        tooltip: '移除来源',
                        onPressed: () => _removePlaylist(adapter),
                        icon: const Icon(Icons.delete_outline_rounded),
                      )
                    : null,
                onTap: adapter.source.isActive
                    ? () => _openSource(adapter, live: true)
                    : null,
              ),
            ),
        ],
      );
}

class _Connector extends StatelessWidget {
  const _Connector(this.title, this.subtitle, this.icon, {this.onPressed});
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: onPressed == null
            ? const Text('规划中')
            : FilledButton.tonal(
                onPressed: onPressed,
                child: const Text('配置'),
              ),
      );
}

class _WebDavDraft {
  const _WebDavDraft({
    required this.name,
    required this.endpoint,
    required this.username,
    required this.password,
  });
  final String name;
  final String endpoint;
  final String username;
  final String password;
}

class _SmbNfsDraft {
  const _SmbNfsDraft({
    required this.name,
    required this.endpoint,
    required this.username,
    required this.password,
  });
  final String name;
  final String endpoint;
  final String username;
  final String password;
}

class _SmbNfsDialog extends StatefulWidget {
  const _SmbNfsDialog();

  @override
  State<_SmbNfsDialog> createState() => _SmbNfsDialogState();
}

class _SmbNfsDialogState extends State<_SmbNfsDialog> {
  final _name = TextEditingController();
  final _endpoint = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('添加 Samba (SMB) / NFS 共享'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '连接名称',
                hintText: '家庭局域网 NAS',
              ),
            ),
            TextField(
              controller: _endpoint,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '共享地址 (smb:// 或 nfs://)',
                hintText: 'smb://192.168.1.100/share 或 nfs://192.168.1.100/media',
              ),
            ),
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: '用户名（可选，匿名共享留空）',
              ),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码（可选）',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _SmbNfsDraft(
                name: _name.text,
                endpoint: _endpoint.text,
                username: _username.text,
                password: _password.text,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      );
}

class _PlaylistDraft {
  const _PlaylistDraft({
    required this.name,
    required this.url,
    required this.rightsConfirmed,
  });
  final String name;
  final String url;
  final bool rightsConfirmed;
}

class _PlaylistDialog extends StatefulWidget {
  const _PlaylistDialog();

  @override
  State<_PlaylistDialog> createState() => _PlaylistDialogState();
}

class _PlaylistDialogState extends State<_PlaylistDialog> {
  final _name = TextEditingController();
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
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('我确认拥有该清单内媒体的访问与收视权利'),
              value: _rightsConfirmed,
              onChanged: (value) =>
                  setState(() => _rightsConfirmed = value ?? false),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _PlaylistDraft(
                name: _name.text,
                url: _url.text,
                rightsConfirmed: _rightsConfirmed,
              ),
            ),
            child: const Text('验证并添加'),
          ),
        ],
      );
}

class _WebDavDialog extends StatefulWidget {
  const _WebDavDialog();

  @override
  State<_WebDavDialog> createState() => _WebDavDialogState();
}

class _WebDavDialogState extends State<_WebDavDialog> {
  final _name = TextEditingController();
  final _endpoint = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('连接 WebDAV'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '连接名称'),
            ),
            TextField(
              controller: _endpoint,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'HTTPS WebDAV 根目录地址',
                hintText: 'https://nas.example.com/dav',
              ),
            ),
            TextField(
              controller: _username,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _WebDavDraft(
                name: _name.text,
                endpoint: _endpoint.text,
                username: _username.text,
                password: _password.text,
              ),
            ),
            child: const Text('验证并连接'),
          ),
        ],
      );
}
