import '../../domain/models/media_source.dart';
import '../../domain/models/live_program.dart';
import '../../domain/models/unified_media.dart';
import '../../domain/ports/live_program_guide.dart';
import '../../domain/ports/catalog_initial_category.dart';
import '../../domain/ports/media_source_adapter.dart';
import '../../domain/ports/source_catalog_tabs.dart';
import '../../domain/ports/source_catalog_scopes.dart';
import '../policy/source_policy.dart';

/// 为来源适配器提供可在不重建 UI 的情况下更新的生命周期与健康快照。
class ManagedMediaSourceAdapter
    implements
        MediaSourceAdapter,
        LiveProgramGuide,
        SourceCatalogTabs,
        SourceCatalogScopes,
        CatalogInitialCategory {
  ManagedMediaSourceAdapter(
    this._delegate, {
    this.failureThreshold = 3,
    this.onStateChanged,
  }) : _source = _delegate.source;

  final MediaSourceAdapter _delegate;
  final int failureThreshold;
  final void Function()? onStateChanged;
  MediaSource _source;
  var _consecutiveFailures = 0;

  @override
  MediaSource get source => _source;

  void update({
    bool? enabled,
    SourceHealth? health,
    SourceLifecycle? lifecycle,
  }) {
    _source = _source.copyWith(
      enabled: enabled,
      health: health,
      lifecycle: lifecycle,
    );
    if (health == SourceHealth.healthy || lifecycle == SourceLifecycle.active) {
      _consecutiveFailures = 0;
    }
    onStateChanged?.call();
  }

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) async {
    _require(SourceAction.browse);
    return _run(() => _delegate.browse(query));
  }

  @override
  Future<List<MediaSearchHit>> search(String query) async {
    _require(SourceAction.search);
    return _run(() => _delegate.search(query));
  }

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) async {
    _require(SourceAction.episodes);
    return _run(() => _delegate.episodes(item));
  }

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) async {
    _require(SourceAction.nativePlayback);
    return _run(() => _delegate.resolvePlayback(episode));
  }

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(
    MediaEpisode episode,
  ) async {
    _require(SourceAction.officialFallback);
    return _run(() => _delegate.resolveOfficialFallback(episode));
  }

  @override
  Future<List<LiveProgram>> programGuide(
    MediaItem item, {
    DateTime? now,
  }) {
    _require(SourceAction.browse);
    final delegate = _delegate;
    if (delegate is! LiveProgramGuide) return Future.value(const []);
    return _run(
        () => (delegate as LiveProgramGuide).programGuide(item, now: now));
  }

  @override
  MediaCategory get initialCatalogCategory =>
      _delegate is CatalogInitialCategory
          ? (_delegate as CatalogInitialCategory).initialCatalogCategory
          : MediaCategory.live;

  @override
  bool get supportsSubtabs =>
      _delegate is SourceCatalogTabs &&
      (_delegate as SourceCatalogTabs).supportsSubtabs;

  @override
  List<SourceCatalogTab> get primaryTabs => _delegate is SourceCatalogTabs
      ? (_delegate as SourceCatalogTabs).primaryTabs
      : const [];

  @override
  List<SourceCatalogTab> subTabsFor(
    MediaCategory category,
    Iterable<MediaItem> items,
  ) =>
      _delegate is SourceCatalogTabs
          ? (_delegate as SourceCatalogTabs).subTabsFor(category, items)
          : const [];

  @override
  Future<List<SourceCatalogScope>> catalogScopes() =>
      _delegate is SourceCatalogScopes
          ? (_delegate as SourceCatalogScopes).catalogScopes()
          : Future.value(const []);

  @override
  Future<Set<String>> availableCatalogScopeIds({
    required MediaCategory category,
    bool refresh = false,
  }) =>
      _delegate is SourceCatalogScopes
          ? _run(
              () => (_delegate as SourceCatalogScopes).availableCatalogScopeIds(
                category: category,
                refresh: refresh,
              ),
            )
          : Future.value(const {});

  @override
  String? get selectedCatalogScopeId => _delegate is SourceCatalogScopes
      ? (_delegate as SourceCatalogScopes).selectedCatalogScopeId
      : null;

  @override
  Future<void> selectCatalogScope(String? id) => _delegate
          is SourceCatalogScopes
      ? _run(() => (_delegate as SourceCatalogScopes).selectCatalogScope(id))
      : Future.value();

  void _require(SourceAction action) {
    final decision = SourcePolicy.evaluate(
      source,
      action,
      // 直接调用已明确携带 sourceId，按用户选中此来源处理；联邦流程会先自行筛选。
      explicitSourceSelection: true,
    );
    if (!decision.allowed) {
      throw StateError(decision.reason ?? '来源当前不可用');
    }
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      final value = await operation();
      _recordSuccess();
      return value;
    } catch (_) {
      _recordFailure();
      rethrow;
    }
  }

  void _recordSuccess() {
    _consecutiveFailures = 0;
    if (_source.health != SourceHealth.healthy) {
      _source = _source.copyWith(health: SourceHealth.healthy);
      onStateChanged?.call();
    }
  }

  void _recordFailure() {
    _consecutiveFailures += 1;
    if (_consecutiveFailures >= failureThreshold) {
      _source = _source.copyWith(
        health: SourceHealth.unavailable,
        lifecycle: SourceLifecycle.circuitOpen,
      );
      onStateChanged?.call();
      return;
    }
    if (_source.health != SourceHealth.degraded) {
      _source = _source.copyWith(health: SourceHealth.degraded);
      onStateChanged?.call();
    }
  }
}
