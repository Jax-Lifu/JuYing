// TVBox parsing factories stay beside their wire-format serializers for auditability.
// ignore_for_file: sort_constructors_first

import 'package:juying_source_providers/juying_source_providers.dart';

import 'package:juying/features/tvbox/services/tvbox_spider_runtime_capability.dart';

/// Domain model representing a TVBox Site Source adapter.
///
/// **What**: Defines metadata, API type (Spider, CMS, CCTV VOD), search capabilities,
/// and category hierarchies for TVBox aggregation sites.
///
/// **Why**: TVBox architectures aggregate dozens of disparate crawler endpoints.
/// A unified model allows the UI and federated search engine to treat CCTV official片库,
/// CatVod JS spiders, and MacCMS JSON APIs identically.
class TvBoxCategory {
  const TvBoxCategory({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  factory TvBoxCategory.fromJson(Map<String, dynamic> json) {
    return TvBoxCategory(
      id: json['type_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['type_name']?.toString() ?? json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
      };
}

class TvBoxSite {
  const TvBoxSite({
    required this.key,
    required this.name,
    this.originId,
    this.type = 3, // 4: CCTV, 3: Spider/JS, 1: CMS JSON, 0: XML
    this.api = '',
    this.searchable = true,
    this.quickSearch = true,
    this.filterable = true,
    this.ext,
    this.jar = '',
    this.categories = const <TvBoxCategory>[],
    this.parses = const <Map<String, dynamic>>[],
    this.flags = const <String>[],
  });

  final String key;
  final String name;

  /// 配置请求 URL 与原始 key 的摘要；旧缓存没有来源证据时保持为空。
  /// 来源不随展示 key、JAR 或解析器配置变化，供刷新时稳定匹配。
  final String? originId;
  final int type;
  final String api;
  final bool searchable;
  final bool quickSearch;
  final bool filterable;
  final dynamic ext;
  final String jar;
  final List<TvBoxCategory> categories;

  /// 解析器和 VIP 线路标识属于原仓上下文，随站点保存以免多仓串用。
  final List<Map<String, dynamic>> parses;
  final List<String> flags;

  /// UI、搜索和执行入口共用同一能力判断，避免显示可用却落入错误协议。
  TvBoxSpiderRuntimeCapability get spiderRuntimeCapability =>
      TvBoxSpiderRuntimeCapability.inspect(
        api: api,
        type: type,
        key: key,
        jar: jar,
        ext: ext,
      );

  bool get isRuntimeSupported => spiderRuntimeCapability.runtimeAvailable;

  String get adapterLabel {
    final capability = spiderRuntimeCapability;
    if (!capability.runtimeAvailable) return capability.label;
    if (type == 0) return 'CMS XML';
    if (type == 1) return 'CMS JSON';
    if (type == 4) return key == 'cctv_vod' ? '官方片库' : 'T4 HTTP';
    final lowerApi = api.trim().toLowerCase();
    if (lowerApi == 'csp_bili') return 'Dart Spider';
    if (lowerApi.startsWith('py_cctv')) return 'Dart 兼容';
    if (TvBoxSpiderRuntimeCapability.supportsXbpq(api: api, ext: ext)) {
      return 'Dart XBPQ';
    }
    if (PortedSpiderRegistry.instance.has(api)) {
      return 'Dart 移植';
    }
    if (capability.kind == TvBoxSpiderRuntimeKind.catVodJar) {
      return capability.label;
    }
    return lowerApi.startsWith('http') ? 'HTTP VOD' : 'Dart App API';
  }

  TvBoxSite copyWith({
    String? key,
    String? name,
    String? originId,
    int? type,
    String? api,
    bool? searchable,
    bool? quickSearch,
    bool? filterable,
    dynamic ext,
    String? jar,
    List<TvBoxCategory>? categories,
    List<Map<String, dynamic>>? parses,
    List<String>? flags,
  }) {
    return TvBoxSite(
      key: key ?? this.key,
      name: name ?? this.name,
      originId: originId ?? this.originId,
      type: type ?? this.type,
      api: api ?? this.api,
      searchable: searchable ?? this.searchable,
      quickSearch: quickSearch ?? this.quickSearch,
      filterable: filterable ?? this.filterable,
      ext: ext ?? this.ext,
      jar: jar ?? this.jar,
      categories: categories ?? this.categories,
      parses: parses ?? this.parses,
      flags: flags ?? this.flags,
    );
  }

  factory TvBoxSite.fromJson(Map<String, dynamic> json) {
    final categories = <TvBoxCategory>[];
    final rawCategories = json['categories'];
    if (rawCategories is List) {
      for (final rawCategory in rawCategories) {
        if (rawCategory is String) {
          final name = rawCategory.trim();
          if (name.isNotEmpty) {
            // 部分 TVBox 仓仅提供分类名称，CMS 通常也接受名称作为筛选值。
            categories.add(TvBoxCategory(id: name, name: name));
          }
          continue;
        }
        if (rawCategory is Map) {
          final category = TvBoxCategory.fromJson(
            Map<String, dynamic>.from(rawCategory),
          );
          if (category.id.isNotEmpty && category.name.isNotEmpty) {
            categories.add(category);
          }
        }
      }
    }
    return TvBoxSite(
      key: json['key']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '未知站点',
      originId: switch (json['originId']) {
        final String value when value.trim().isNotEmpty => value.trim(),
        _ => null,
      },
      type: json['type'] is int
          ? json['type'] as int
          : int.tryParse(json['type']?.toString() ?? '3') ?? 3,
      api: json['api']?.toString().trim() ?? '',
      searchable: !json.containsKey('searchable') ||
          json['searchable'] == 1 ||
          json['searchable'] == true,
      quickSearch: !json.containsKey('quickSearch') ||
          json['quickSearch'] == 1 ||
          json['quickSearch'] == true,
      filterable: !json.containsKey('filterable') ||
          json['filterable'] == 1 ||
          json['filterable'] == true,
      ext: json['ext'],
      jar: json['jar']?.toString().trim() ?? '',
      categories: categories,
      parses: (json['parses'] as List?)
              ?.whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .toList(growable: false) ??
          const <Map<String, dynamic>>[],
      flags: (json['flags'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const <String>[],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'name': name,
        if (originId != null) 'originId': originId,
        'type': type,
        'api': api,
        'searchable': searchable,
        'quickSearch': quickSearch,
        'filterable': filterable,
        'ext': ext,
        'jar': jar,
        'categories': categories.map((c) => c.toJson()).toList(),
        'parses': parses,
        'flags': flags,
      };
}
