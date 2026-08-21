import 'package:flutter/foundation.dart';

import '../../domain/models/media_source.dart';
import '../../domain/ports/media_source_adapter.dart';
import 'managed_media_source_adapter.dart';
import 'validated_media_source_adapter.dart';

/// 来源注册表集中管理适配器，避免页面直接构造或识别某一来源仓储。
class MediaSourceRegistry extends ChangeNotifier {
  MediaSourceRegistry(Iterable<MediaSourceAdapter> adapters)
      : _adapters = <String, ManagedMediaSourceAdapter>{} {
    for (final adapter in adapters) {
      _register(adapter, notify: false);
    }
  }

  final Map<String, ManagedMediaSourceAdapter> _adapters;

  List<MediaSourceAdapter> get adapters => List.unmodifiable(
      _adapters.values.where((adapter) => adapter.source.isActive));

  /// 包含暂时不可用来源，供界面解释状态，但查询仍必须走 [adapters] 与策略筛选。
  List<MediaSourceAdapter> get allAdapters =>
      List.unmodifiable(_adapters.values);

  MediaSourceAdapter? operator [](String sourceId) => _adapters[sourceId];

  /// 注册运行时来源（例如用户确认权利后的自有清单）。仍经过统一契约验证与故障管理。
  bool register(MediaSourceAdapter adapter) => _register(adapter, notify: true);

  bool unregister(String sourceId) {
    if (_adapters.remove(sourceId) == null) return false;
    notifyListeners();
    return true;
  }

  bool _register(MediaSourceAdapter adapter, {required bool notify}) {
    final sourceId = adapter.source.id;
    if (sourceId.trim().isEmpty || _adapters.containsKey(sourceId)) {
      if (notify) return false;
      throw ArgumentError.value(sourceId, 'sourceId', '来源 ID 必须唯一且非空');
    }
    _adapters[sourceId] = ManagedMediaSourceAdapter(
      ValidatedMediaSourceAdapter(adapter),
      onStateChanged: notifyListeners,
    );
    if (notify) notifyListeners();
    return true;
  }

  /// 供健康探测、远程关闭开关或授权状态变更调用；业务页面只读取快照。
  bool updateState(
    String sourceId, {
    bool? enabled,
    SourceHealth? health,
    SourceLifecycle? lifecycle,
  }) {
    final adapter = _adapters[sourceId];
    if (adapter == null) return false;
    adapter.update(enabled: enabled, health: health, lifecycle: lifecycle);
    return true;
  }

  /// 用户开关仅变更 enabled；授权、健康、熔断等安全状态不被覆盖。
  bool setEnabled(String sourceId, bool enabled) =>
      updateState(sourceId, enabled: enabled);

  /// 用户手动重试会清除本地熔断，下一次实际调用仍由适配器重新校验。
  bool restoreSource(String sourceId) => updateState(
        sourceId,
        health: SourceHealth.healthy,
        lifecycle: SourceLifecycle.active,
      );
}
