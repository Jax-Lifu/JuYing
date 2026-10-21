import 'package:flutter/foundation.dart';

import 'package:juying/core/models/media_item.dart';

/// Metadata scraper and dirty title sanitizer engine (TMDB / Douban / Bangumi).
///
/// **What**: Normalizes messy crawler/torrent filenames into canonical titles,
/// and fetches poster backdrops with parallel prefetch and generation token protection.
///
/// **Why**: Spider crawlers return dirty titles packed with tags (`[4K.60FPS.杜比视界.国粤双语]`).
/// Regex cleaning converts them into clean search queries for TMDB/Douban scraping.
class MediaMetadataService {
  MediaMetadataService({MetadataProvider? provider}) : _provider = provider;

  final MetadataProvider? _provider;
  int _currentLoadGeneration = 0;

  int get currentGeneration => _currentLoadGeneration;

  /// Advances generation token to discard previous asynchronous detail prefetch tasks.
  int nextGeneration() => ++_currentLoadGeneration;

  /// Strips resolution badges, release groups, and episode tags from dirty media titles.
  static String cleanMediaTitle(String rawTitle) {
    var cleaned = rawTitle;

    // 1. Remove bracketed release info: 【...】, [...], (...), <...>
    cleaned = cleaned.replaceAll(
      RegExp(r'(\[.*?\]|【.*?】|\(.*?\)|<.*?>)', caseSensitive: false),
      ' ',
    );

    // 2. Replace dots, underscores, hyphens with spaces when surrounded by alphanumeric words
    cleaned = cleaned.replaceAll(
      RegExp(
        r'[\._\-](4k|2160p|1080p|720p|hdr|dolby|atmos|hevc|x264|x265|h264|h265|aac|dts|web-dl|webdl|bdrip|remux|hd).*',
        caseSensitive: false,
      ),
      ' ',
    );

    // 3. Remove standalone video quality & audio codec noise
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\b(4k|2160p|1080p|720p|hdr|dolby|atmos|hevc|x264|x265|aac|dts|web-dl|bdrip|remux|h\.264|h\.265)\b',
        caseSensitive: false,
      ),
      ' ',
    );

    // 4. Remove episode / season tags
    cleaned = cleaned.replaceAll(
      RegExp(r'(第\s*\d+\s*[集话期]|全\s*\d+\s*[集话期]|s\d{1,2}e\d{1,2}|ep?\d{1,3})',
          caseSensitive: false),
      ' ',
    );

    // 5. Remove common watermarks & subtitles tags
    cleaned = cleaned.replaceAll(
      RegExp(
        r'(国语|粤语|中字|双语|官方|未删减|加长版|无修|生肉|招募|压制)',
        caseSensitive: false,
      ),
      ' ',
    );

    // 6. Clean extra spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? rawTitle.trim() : cleaned;
  }

  /// Concurrently prefetches TMDB/Douban metadata alongside spider detail content.
  Future<MetadataResult> prefetchMetadata({
    required String rawTitle,
    required int generation,
  }) async {
    final cleanTitle = cleanMediaTitle(rawTitle);
    final provider = _provider;
    if (provider == null) {
      return MetadataUnavailableResult(
        fallbackTitle: cleanTitle,
        reason: '未配置元数据供应商',
      );
    }

    final item = await provider.searchByTitle(cleanTitle);

    // Generation token check: if user navigated away, discard result
    if (generation != _currentLoadGeneration) {
      debugPrint(
          '[MetadataService] Prefetch aborted: generation mismatch ($generation vs $_currentLoadGeneration)');
      return MetadataStaleResult(fallbackTitle: cleanTitle);
    }

    if (item == null) {
      return MetadataUnavailableResult(
        fallbackTitle: cleanTitle,
        reason: '未找到匹配的元数据',
      );
    }
    return MetadataAvailableResult(item);
  }
}

/// 元数据供应商只负责描述性信息，不得返回播放线路或站源私有字段。
abstract interface class MetadataProvider {
  Future<MediaItem?> searchByTitle(String title);
}

sealed class MetadataResult {
  const MetadataResult({required this.fallbackTitle});

  final String fallbackTitle;
}

class MetadataAvailableResult extends MetadataResult {
  MetadataAvailableResult(this.item) : super(fallbackTitle: item.title);

  final MediaItem item;
}

class MetadataUnavailableResult extends MetadataResult {
  const MetadataUnavailableResult({
    required super.fallbackTitle,
    required this.reason,
  });

  final String reason;
}

class MetadataStaleResult extends MetadataResult {
  const MetadataStaleResult({required super.fallbackTitle});
}
