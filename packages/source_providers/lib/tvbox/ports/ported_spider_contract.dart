/// TVBox Jar-to-Dart Ported Spider Contract (Section 5.9, 6.1 & ADR-008).
///
/// **What**: Defines the abstract contract for TVBox Jar sites ported to pure Dart.
///
/// **Why**: Implements ADR-008. Replaces execution of Android DEX/JAR bytecode with
/// pure Dart spiders and reusable parsing rule engines, ensuring cross-platform
/// reliability across Windows, Android TV, and mobile.
library;

export 'rule_based_ported_spider.dart';

/// Contract for a TVBox Spider ported from Java/DEX to pure Dart.
abstract class PortedSpiderProvider {
  /// Unique identifier of the ported site/spider (e.g., 'csp_AppYsV2', 'csp_Bili').
  String get siteKey;

  /// Human-readable name for logging and UI capabilities display.
  String get displayName;

  /// Fetches home catalog categories and featured video recommendation rows.
  Future<Map<String, dynamic>> homeContent();

  /// Fetches paginated category items, supporting optional multi-dimensional filters.
  Future<Map<String, dynamic>> categoryContent(
    String tid,
    String pg, {
    Map<String, dynamic>? filter,
  });

  /// Fetches comprehensive media details, episode playlists, and video sources.
  Future<Map<String, dynamic>> detailContent(List<String> ids);

  /// Performs keyword search against the ported target site.
  Future<Map<String, dynamic>> searchContent(
    String key, {
    bool quick = false,
  });

  /// Resolves raw media URL, headers, and parsing flags for playback.
  Future<Map<String, dynamic>> playerContent(
    String flag,
    String id, {
    List<String>? vipFlags,
  });
}
