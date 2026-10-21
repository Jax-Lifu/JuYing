import 'dart:convert';
import 'ported_spider_contract.dart';

/// HTTP request delegator for ported spiders in pure Dart test/CLI environments.
typedef SpiderHttpClient = Future<String> Function(
  String url, {
  Map<String, String>? headers,
});

/// Declarative Rule Specification for Ported TVBox Spiders (Section 5.9 & ADR-008).
///
/// **What**: Encapsulates URL patterns, query keys, and extraction mappings for a
/// specific video site, allowing pure Dart execution without DEX bytecode.
///
/// **Why**: Implements ADR-008. Over 80% of TVBox Jar spiders follow either CMS REST
/// APIs, AppYsV2 conventions, or XPath/Regex field extractors. Reusable rule specs
/// minimize boilerplate when porting community jar crawlers.
class SpiderRuleConfig {
  const SpiderRuleConfig({
    required this.siteKey,
    required this.displayName,
    required this.host,
    this.homePath = '',
    this.categoryPathTemplate =
        '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
    this.detailPathTemplate = '/api.php/provide/vod/?ac=detail&ids={ids}',
    this.searchPathTemplate = '/api.php/provide/vod/?ac=detail&wd={key}',
    this.defaultHeaders = const <String, String>{},
    this.categories = const <Map<String, String>>[],
  });

  final String siteKey;
  final String displayName;
  final String host;
  final String homePath;
  final String categoryPathTemplate;
  final String detailPathTemplate;
  final String searchPathTemplate;
  final Map<String, String> defaultHeaders;
  final List<Map<String, String>> categories;
}

/// Generic Pure Dart Rule-Driven TVBox Spider (ADR-008 & PoC-9).
class RuleBasedPortedSpider implements PortedSpiderProvider {
  RuleBasedPortedSpider({
    required this.rule,
    required SpiderHttpClient httpClient,
  }) : _httpClient = httpClient;

  final SpiderRuleConfig rule;
  final SpiderHttpClient _httpClient;

  @override
  String get siteKey => rule.siteKey;

  @override
  String get displayName => rule.displayName;

  @override
  Future<Map<String, dynamic>> homeContent() async {
    final classes = rule.categories.isNotEmpty
        ? rule.categories
            .map((c) => <String, dynamic>{
                  'type_id': c['id'] ?? '',
                  'type_name': c['name'] ?? '',
                })
            .toList(growable: false)
        : <Map<String, dynamic>>[];

    // If a dedicated home path exists, query featured items
    var list = <Map<String, dynamic>>[];
    if (rule.homePath.isNotEmpty) {
      final url = '${rule.host}${rule.homePath}';
      try {
        final raw = await _httpClient(url, headers: rule.defaultHeaders);
        list = _extractVodList(raw);
      } catch (_) {
        list = <Map<String, dynamic>>[];
      }
    }

    return <String, dynamic>{
      'class': classes,
      'list': list,
    };
  }

  @override
  Future<Map<String, dynamic>> categoryContent(
    String tid,
    String pg, {
    Map<String, dynamic>? filter,
  }) async {
    final path = rule.categoryPathTemplate
        .replaceAll('{tid}', Uri.encodeComponent(tid))
        .replaceAll('{pg}', Uri.encodeComponent(pg));
    final url = '${rule.host}$path';
    final raw = await _httpClient(url, headers: rule.defaultHeaders);
    final items = _extractVodList(raw);

    return <String, dynamic>{
      'page': int.tryParse(pg) ?? 1,
      'pagecount': 999,
      'limit': items.length,
      'total': 9999,
      'list': items,
    };
  }

  @override
  Future<Map<String, dynamic>> detailContent(List<String> ids) async {
    final path = rule.detailPathTemplate.replaceAll(
      '{ids}',
      Uri.encodeComponent(ids.join(',')),
    );
    final url = '${rule.host}$path';
    final raw = await _httpClient(url, headers: rule.defaultHeaders);
    final items = _extractVodList(raw);

    return <String, dynamic>{
      'list': items,
    };
  }

  @override
  Future<Map<String, dynamic>> searchContent(
    String key, {
    bool quick = false,
  }) async {
    final path = rule.searchPathTemplate.replaceAll(
      '{key}',
      Uri.encodeComponent(key),
    );
    final url = '${rule.host}$path';
    final raw = await _httpClient(url, headers: rule.defaultHeaders);
    final items = _extractVodList(raw);

    return <String, dynamic>{
      'list': items,
    };
  }

  @override
  Future<Map<String, dynamic>> playerContent(
    String flag,
    String id, {
    List<String>? vipFlags,
  }) async {
    // Direct link or header-wrapped playback payload
    return <String, dynamic>{
      'parse': 0,
      'playUrl': '',
      'url': id,
      'header': rule.defaultHeaders,
    };
  }

  List<Map<String, dynamic>> _extractVodList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final list = decoded['list'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false);
        }
        final data = decoded['data'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false);
        }
      }
    } catch (_) {
      // Fallback: non-JSON or regex parsing could be appended here
    }
    return <Map<String, dynamic>>[];
  }
}
