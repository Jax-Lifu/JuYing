import 'dart:convert';

import 'cctv_models.dart';
import '../../domain/models/playable_media.dart';
import 'cctv_exception.dart';

abstract final class CctvParsers {
  static final _guidPattern = RegExp(
    r'''var\s+guid\s*=\s*["']([a-fA-F0-9]{32})["']''',
    caseSensitive: false,
  );

  static final _episodeArrayPattern = RegExp(
    r'var\s+jsonData\d*\s*=\s*\[(.*?)\]\s*;',
    dotAll: true,
  );
  static final _episodePattern = RegExp(
    r'''['"]title['"]\s*:\s*['"]((?:\\.|[^'"])*)['"][\s\S]*?['"]url['"]\s*:\s*['"](https://tv\.cctv\.com/[^'"]+?\.shtml)['"]''',
  );
  static final _episodeImagePattern = RegExp(
    r'''['"]img['"]\s*:\s*['"]([^'"]+)['"]''',
  );

  static CctvCatalogResult catalog(
    String body, {
    required int page,
    required CctvCatalogCategory category,
  }) {
    final root = _map(jsonDecode(body), '片库响应');
    final data = _map(root['data'], '片库 data');
    final rawItems = data['list'];
    if (rawItems is! List) {
      throw const CctvException('CCTV 片库返回格式已变化');
    }

    final items = <CctvProgram>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final episode = item['video'] is Map
          ? Map<String, dynamic>.from(item['video'] as Map)
          : const <String, dynamic>{};
      final id = _string(item['id']);
      final title = _string(item['title']);
      final officialPage = _cctvPage(_string(item['url']));
      final episodePage = _cctvPage(_string(episode['url'])) ?? officialPage;
      if (id == null ||
          title == null ||
          officialPage == null ||
          episodePage == null) {
        continue;
      }

      items.add(CctvProgram(
        id: id,
        title: title,
        officialPageUrl: officialPage,
        episodePageUrl: episodePage,
        category: category,
        episodeTitle: _string(episode['title']),
        imageUrl: _httpsUri(_string(item['image2']) ?? _string(item['image'])),
        brief: _string(item['brief']),
        year: _string(item['year']),
        area: _string(item['area']),
        channel: _string(item['channel']),
        subcategory: _string(item['sc']),
        episodeCount: int.tryParse(_string(item['count']) ?? ''),
      ));
    }

    return CctvCatalogResult(
      items: List.unmodifiable(items),
      page: page,
      total: int.tryParse('${data['total'] ?? items.length}') ?? items.length,
    );
  }

  static List<CctvProgram> search(String body) {
    final root = _map(jsonDecode(body), '搜索响应');
    final rawItems = root['list'];
    if (rawItems is! List) {
      throw const CctvException('CCTV 搜索返回格式已变化');
    }
    final items = <CctvProgram>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final id = _string(item['id']);
      final page = _cctvPage(_string(item['urllink']));
      final title = _stripSearchMarkup(
          _string(item['all_title']) ?? _string(item['title']));
      if (id == null || page == null || title == null) continue;
      items.add(CctvProgram(
        id: id,
        title: title,
        officialPageUrl: page,
        episodePageUrl: page,
        category: CctvCatalogCategory.animation,
        imageUrl: _httpsUri(_string(item['imglink'])),
        channel: _string(item['channel']),
      ));
    }
    return List.unmodifiable(items);
  }

  static List<CctvEpisode> episodes(String html, {required String programId}) {
    final episodes = <CctvEpisode>[];
    final seenUrls = <String>{};
    for (final array in _episodeArrayPattern.allMatches(html)) {
      final source = array.group(1)!;
      for (final match in _episodePattern.allMatches(source)) {
        final url = _cctvPage(match.group(2));
        if (url == null || !seenUrls.add(url.toString())) continue;
        final title = _unescapeJs(match.group(1)!);
        final beforeUrl = source.substring(0, match.start);
        final imageMatches = _episodeImagePattern.allMatches(beforeUrl);
        final image =
            imageMatches.isEmpty ? null : _httpsUri(imageMatches.last.group(1));
        episodes.add(CctvEpisode(
          id: '$programId-${episodes.length + 1}',
          title: title,
          officialPageUrl: url,
          imageUrl: image,
          number: _episodeNumber(title),
        ));
      }
    }
    return List.unmodifiable(episodes);
  }

  static String pageGuid(String html) {
    final match = _guidPattern.firstMatch(html);
    if (match == null) {
      throw const CctvException('节目页没有公开可用的播放标识');
    }
    return match.group(1)!.toLowerCase();
  }

  static PlayableMedia playback(
    String body, {
    required String guid,
    required Uri officialPageUri,
  }) {
    final root = _map(jsonDecode(body), '播放元数据');
    if (_string(root['ack']) != 'yes' || _string(root['play']) != '1') {
      throw CctvException(_string(root['tip_msg']) ?? '该节目当前不可播放');
    }
    if (_enabled(root['is_protected']) ||
        _enabled(root['is_invalid_copyright'])) {
      throw const CctvException('该节目存在版权或保护限制，请前往官网观看');
    }

    // 原生播放器只使用 CCTV 声明的兼容 HLS 地址。官网 HTML5 的高码率
    // h5e 流需要官网自己的播放链路，在部分 Windows 原生解码器中会花屏，
    // 因而由播放器页面显式回退到官网 WebView2，而不是直接交给本地解码器。
    final rawStreamUrl = _string(root['hls_url']);
    final streamUri = _trustedStream(rawStreamUrl);
    if (streamUri == null) {
      final receivedUri = Uri.tryParse(rawStreamUrl ?? '');
      final origin = receivedUri == null
          ? '空地址'
          : '${receivedUri.scheme}://${receivedUri.host}';
      throw CctvException('CCTV 返回的 HLS 地址不可用于原生播放（$origin）');
    }

    final seconds = double.tryParse(_string(
          root['video'] is Map ? (root['video'] as Map)['totalLength'] : null,
        ) ??
        '');
    return PlayableMedia(
      id: guid,
      title: _string(root['title']) ?? 'CCTV 节目',
      streamUri: streamUri,
      officialPageUri: officialPageUri,
      posterUri: _httpsUri(_string(root['image'])),
      duration: seconds == null
          ? null
          : Duration(milliseconds: (seconds * 1000).round()),
      httpHeaders: {
        'Referer': officialPageUri.toString(),
        'User-Agent': 'JuYing/0.1',
      },
    );
  }

  /// 只解析公开 HLS 主播放列表中声明的变体，不推测或生成清晰度地址。
  static List<PlaybackQuality> hlsQualities(String body,
      {required Uri baseUri}) {
    final lines = const LineSplitter().convert(body);
    final qualities = <PlaybackQuality>[];
    final seenUris = <String>{};
    final isCctvHtml5Playlist = baseUri.path.contains('/asp/h5e/hls/');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final attributes = line.substring('#EXT-X-STREAM-INF:'.length);
      final resolution =
          RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(attributes);
      final bandwidth =
          RegExp(r'(?:AVERAGE-)?BANDWIDTH=(\d+)').firstMatch(attributes);
      final uriLine =
          lines.skip(index + 1).map((item) => item.trim()).firstWhere(
                (item) => item.isNotEmpty,
                orElse: () => '',
              );
      if (uriLine.isEmpty || uriLine.startsWith('#')) continue;
      final streamUri = _trustedStream(baseUri.resolve(uriLine).toString());
      if (streamUri == null || !seenUris.add(streamUri.toString())) continue;
      final width = int.tryParse(resolution?.group(1) ?? '');
      final height = int.tryParse(resolution?.group(2) ?? '');
      final bits = int.tryParse(bandwidth?.group(1) ?? '');
      final label = _qualityLabel(
        height: height,
        bandwidth: bits,
        useCctvLabels: isCctvHtml5Playlist,
      );
      qualities.add(PlaybackQuality(
        id: streamUri.toString(),
        label: label,
        streamUri: streamUri,
        width: width,
        height: height,
        bandwidth: bits,
      ));
    }
    qualities.sort((left, right) {
      final heightComparison = (right.height ?? 0).compareTo(left.height ?? 0);
      if (heightComparison != 0) return heightComparison;
      return (right.bandwidth ?? 0).compareTo(left.bandwidth ?? 0);
    });
    return List.unmodifiable(qualities);
  }

  static Map<String, dynamic> _map(Object? value, String label) {
    if (value is! Map) throw CctvException('$label不是有效对象');
    return Map<String, dynamic>.from(value);
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _stripSearchMarkup(String? value) => value
      ?.replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .trim();

  static String _unescapeJs(String value) => value
      .replaceAll(r"\\'", "'")
      .replaceAll(r'\\"', '"')
      .replaceAll(r'\\/', '/')
      .replaceAll(r'\\n', ' ')
      .trim();

  static int? _episodeNumber(String title) =>
      int.tryParse(RegExp(r'第\s*(\d+)\s*集').firstMatch(title)?.group(1) ?? '');

  static String _qualityLabel({
    required int? height,
    required int? bandwidth,
    required bool useCctvLabels,
  }) {
    // CCTV 客户端公开的 vod_bitrate_mapping.json 按 kbps 声明档位。
    // 保持官网语义，同时以分辨率作为其他来源/非标准清单的安全回退显示。
    if (useCctvLabels && bandwidth != null) {
      final kilobits = bandwidth / 1000;
      if (kilobits >= 16000) return '4K';
      if (kilobits >= 12000) return '2K';
      if (kilobits >= 3999) return '蓝光';
      if (kilobits >= 1600) return '超清';
      if (kilobits >= 900) return '高清';
      if (kilobits >= 600) return '标清';
      return '流畅';
    }
    return height == null ? '自适应分档' : '${height}P';
  }

  static bool _enabled(Object? value) {
    final text = _string(value)?.toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  static Uri? _httpsUri(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' ? uri : null;
  }

  static Uri? _cctvPage(String? value) {
    final uri = _httpsUri(value);
    if (uri == null) return null;
    return uri.host == 'tv.cctv.com' ? uri : null;
  }

  static Uri? _trustedStream(String? value) {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        !uri.path.toLowerCase().contains('.m3u8')) {
      return null;
    }
    const allowedSuffixes = [
      '.cntv.cn',
      '.cctv.com',
      '.cntv.com.cn',
      '.cntv.cdn20.com',
      '.cntv.lxdns.com',
    ];
    // CCTV 当前公开 HLS 接口会返回该官方 CDN，例如
    // newcntv.qcloudcdn.com/asp/hls/.../main.m3u8。使用精确主机，避免
    // 将整个 qcloud CDN 域都纳入信任范围。
    const allowedHosts = {'newcntv.qcloudcdn.com'};
    const officialH5Hosts = {'dh5wx.cntv.kfcbest.com'};
    return allowedHosts.contains(uri.host) ||
            officialH5Hosts.contains(uri.host) ||
            allowedSuffixes.any(uri.host.endsWith)
        ? uri
        : null;
  }
}
