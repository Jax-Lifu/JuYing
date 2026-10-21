import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/models/tvbox_subscription.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

/// 管理一级 TVBox 订阅；站点始终作为订阅的二级数据持久化。
class TvBoxSubscriptionsNotifier
    extends StateNotifier<List<TvBoxSubscription>> {
  TvBoxSubscriptionsNotifier() : super(<TvBoxSubscription>[builtIn]) {
    unawaited(_restore());
  }

  static const String _storageKey = 'tvbox_subscriptions_v2';
  static const String _legacySitesStorageKey = 'tvbox_imported_sites_v1';
  bool _restoring = true;
  final List<void Function()> _pendingChanges = <void Function()>[];
  Future<void> _pendingWrite = Future<void>.value();

  static TvBoxSubscription get builtIn => TvBoxSubscription(
        id: 'builtin',
        name: '内置片库',
        url: '',
        isBuiltIn: true,
        sites: TvBoxSpiderEngine.defaultPresetSites,
      );

  Future<void> _restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      final raw = preferences.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = json.decode(raw);
          if (decoded is List) {
            final imported = decoded
                .whereType<Map>()
                .map((item) => TvBoxSubscription.fromJson(
                      Map<String, dynamic>.from(item),
                    ))
                .where((item) => !item.isBuiltIn && item.sites.isNotEmpty)
                .toList(growable: false);
            state = <TvBoxSubscription>[builtIn, ...imported];
            return;
          }
        } catch (_) {
          // 损坏的新缓存继续尝试旧版本迁移，内置片库始终可用。
        }
      }
      await _migrateLegacySites(preferences);
    } finally {
      // 启动操作基于已恢复的完整订阅重放，避免把尚未读取的缓存覆盖掉。
      _restoring = false;
      for (final change in _pendingChanges) {
        if (!mounted) break;
        change();
      }
      _pendingChanges.clear();
    }
  }

  Future<void> _migrateLegacySites(SharedPreferences preferences) async {
    final raw = preferences.getString(_legacySitesStorageKey);
    if (raw == null || raw.isEmpty) {
      state = <TvBoxSubscription>[builtIn];
      return;
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return;
      final sites = decoded
          .whereType<Map>()
          .map((item) => TvBoxSite.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
      if (sites.isEmpty) return;
      const legacyId = 'legacy_import';
      final legacy = TvBoxSubscription(
        id: legacyId,
        name: '旧版已导入站点',
        url: '',
        sites: _namespaceSites(legacyId, sites),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      state = <TvBoxSubscription>[builtIn, legacy];
      await _persist();
    } catch (_) {
      if (mounted) state = <TvBoxSubscription>[builtIn];
    }
  }

  /// 新增或刷新一条订阅；同一 URL 永远只占一级列表的一行。
  /// 部分仓加载失败时仅替换已返回站点，避免把离线子仓误当作删除。
  TvBoxSubscription upsert({
    required String url,
    required List<TvBoxSite> sites,
    String? name,
    bool preserveMissing = false,
  }) {
    if (_restoring) {
      final pendingSites = List<TvBoxSite>.of(sites);
      _pendingChanges.add(() => upsert(
            url: url,
            sites: pendingSites,
            name: name,
            preserveMissing: preserveMissing,
          ));
    }
    final id = TvBoxSubscription.idForUrl(url);
    final previousSites = <String, TvBoxSite>{
      for (final subscription in state.where((item) => item.id == id))
        for (final site in subscription.sites) site.key: site,
    };
    final sitesByOrigin = <String, TvBoxSite>{
      for (final site in previousSites.values)
        if (site.originId != null) site.originId!: site,
    };
    final mergedSites = <String, TvBoxSite>{
      if (preserveMissing) ...previousSites,
    };
    for (final site in _namespaceSites(id, sites)) {
      // 完整刷新也保留已知来源的展示 key，防止子仓换序重置当前选择。
      final previous = sitesByOrigin[site.originId];
      var key = previous?.key ?? site.key;
      final owner = previousSites[key];
      if (previous == null &&
          site.originId != null &&
          owner != null &&
          (owner.originId != null && owner.originId != site.originId ||
              preserveMissing && owner.originId == null)) {
        key = '${site.key}_${site.originId}';
      }
      // 部分刷新不能证明无来源旧记录已删除；先保留，完整刷新再移除旧缓存。
      // 不用名称或摘要后缀推测迁移，避免把离线子仓覆盖成另一来源。
      final updated = site.copyWith(key: key);
      mergedSites[key] = updated;
      previousSites[key] = updated;
      if (site.originId != null) sitesByOrigin[site.originId!] = updated;
    }
    final subscription = TvBoxSubscription(
      id: id,
      name: name?.trim().isNotEmpty == true
          ? name!.trim()
          : TvBoxSubscription.displayNameForUrl(url),
      url: url.trim(),
      sites: mergedSites.values.toList(growable: false),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final updated = List<TvBoxSubscription>.from(state);
    // 旧版本没有保存订阅 URL；首次用新版重新导入时用真实订阅替换迁移组，
    // 避免同一批站点同时显示“旧版已导入站点”和新订阅两行。
    updated.removeWhere((item) => item.id == 'legacy_import');
    final index = updated.indexWhere((item) => item.id == id);
    if (index < 0) {
      updated.add(subscription);
    } else {
      updated[index] = subscription;
    }
    state = updated;
    if (!_restoring) unawaited(_persist());
    return subscription;
  }

  void remove(String id) {
    if (_restoring) _pendingChanges.add(() => remove(id));
    state = state.where((item) => item.isBuiltIn || item.id != id).toList();
    if (!_restoring) unawaited(_persist());
  }

  Future<void> _persist() {
    final imported = state
        .where((item) => !item.isBuiltIn)
        .map((item) => item.toJson())
        .toList(growable: false);
    // 先捕获快照再串行写入；销毁后不读 state，慢的旧写入也不能覆盖新操作。
    final write = _pendingWrite.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_storageKey, json.encode(imported));
    });
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  /// 站点 key 在第三方仓内而非全局唯一，加入订阅命名空间后才能安全持久化。
  static List<TvBoxSite> _namespaceSites(
    String subscriptionId,
    List<TvBoxSite> sites,
  ) {
    return sites.map((site) {
      final prefix = '$subscriptionId::';
      return site.key.startsWith(prefix)
          ? site
          : site.copyWith(key: '$prefix${site.key}');
    }).toList(growable: false);
  }
}

final StateNotifierProvider<TvBoxSubscriptionsNotifier, List<TvBoxSubscription>>
    tvBoxSubscriptionsProvider =
    StateNotifierProvider<TvBoxSubscriptionsNotifier, List<TvBoxSubscription>>(
        (ref) {
  return TvBoxSubscriptionsNotifier();
});

/// 执行层仍消费扁平站点视图，但 UI 与持久层不会丢失订阅层级。
final Provider<List<TvBoxSite>> tvBoxSitesProvider =
    Provider<List<TvBoxSite>>((ref) {
  return ref
      .watch(tvBoxSubscriptionsProvider)
      .expand((subscription) => subscription.sites)
      .toList(growable: false);
});

/// 管理当前执行站点，并在订阅刷新/删除时保持状态有效。
class ActiveTvBoxSiteNotifier extends StateNotifier<TvBoxSite> {
  ActiveTvBoxSiteNotifier(List<TvBoxSite> sites)
      : _sites = sites,
        super(sites.first) {
    unawaited(_restore());
  }

  static const String _storageKey = 'tvbox_active_site_key_v1';
  List<TvBoxSite> _sites;

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final key = preferences.getString(_storageKey);
    if (key == null) return;
    for (final site in _sites) {
      if ((site.key == key || site.key.endsWith('::$key')) &&
          site.isRuntimeSupported) {
        state = site;
        if (site.key != key) unawaited(_persist(site.key));
        return;
      }
    }
  }

  void updateSites(List<TvBoxSite> sites) {
    _sites = sites;
    final refreshed = sites.where((site) => site.key == state.key).firstOrNull;
    if (refreshed != null && refreshed.isRuntimeSupported) {
      state = refreshed;
      return;
    }
    state = sites.firstWhere(
      (site) => site.isRuntimeSupported,
      orElse: () => sites.first,
    );
    unawaited(_persist(state.key));
  }

  void selectSite(TvBoxSite site) {
    if (!site.isRuntimeSupported) return;
    state = site;
    unawaited(_persist(site.key));
  }

  Future<void> _persist(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, key);
  }
}

final StateNotifierProvider<ActiveTvBoxSiteNotifier, TvBoxSite>
    activeTvBoxSiteProvider =
    StateNotifierProvider<ActiveTvBoxSiteNotifier, TvBoxSite>((ref) {
  final notifier = ActiveTvBoxSiteNotifier(ref.read(tvBoxSitesProvider));
  ref.listen<List<TvBoxSite>>(tvBoxSitesProvider, (_, sites) {
    notifier.updateSites(sites);
  });
  return notifier;
});
