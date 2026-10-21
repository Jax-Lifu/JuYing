// TVBox parsing factories stay beside their wire-format serializers for auditability.
// ignore_for_file: sort_constructors_first

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';

/// 用户导入的一条 TVBox 订阅及其二级站点集合。
///
/// 订阅 URL 是一级身份，站点只在所属订阅内展示。这样多仓展开出的数百个站点
/// 不会污染设置首页，同时仍可在播放和搜索层按需展开。
class TvBoxSubscription {
  const TvBoxSubscription({
    required this.id,
    required this.name,
    required this.url,
    required this.sites,
    this.isBuiltIn = false,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String url;
  final List<TvBoxSite> sites;
  final bool isBuiltIn;
  final int? updatedAt;

  int get supportedSiteCount =>
      sites.where((site) => site.isRuntimeSupported).length;

  TvBoxSubscription copyWith({
    String? name,
    String? url,
    List<TvBoxSite>? sites,
    int? updatedAt,
  }) {
    return TvBoxSubscription(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      sites: sites ?? this.sites,
      isBuiltIn: isBuiltIn,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
        'sites': sites.map((site) => site.toJson()).toList(growable: false),
        'isBuiltIn': isBuiltIn,
        'updatedAt': updatedAt,
      };

  factory TvBoxSubscription.fromJson(Map<String, dynamic> json) {
    final rawSites = json['sites'];
    return TvBoxSubscription(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'TVBox 订阅',
      url: json['url']?.toString() ?? '',
      sites: rawSites is List
          ? rawSites
              .whereType<Map>()
              .map(
                  (site) => TvBoxSite.fromJson(Map<String, dynamic>.from(site)))
              .toList(growable: false)
          : const <TvBoxSite>[],
      isBuiltIn: json['isBuiltIn'] == true,
      updatedAt: int.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  /// URL 哈希提供跨重启稳定身份；重新导入同一地址会刷新而非新增重复行。
  static String idForUrl(String url) {
    return sha1.convert(utf8.encode(url.trim())).toString().substring(0, 16);
  }

  static String displayNameForUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return 'TVBox 订阅';
    final segment = uri.pathSegments
        .where((value) => value.trim().isNotEmpty)
        .lastOrNull
        ?.replaceAll(RegExp(r'\.(json|txt)$', caseSensitive: false), '');
    return segment == null || segment.isEmpty
        ? uri.host
        : '${uri.host} · $segment';
  }
}
