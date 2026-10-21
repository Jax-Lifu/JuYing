import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'package:juying/core/models/live_channel.dart';

/// Service engine for IPTV playlist parsing, stream probing, CCTV official resolution, and EPG mapping.
///
/// **What**: Parses M3U/TXT live sources, measures stream latency/bandwidth, resolves dynamic CCTV HLS streams,
/// and detects IPv4/IPv6 dual-stack connectivity.
///
/// **Why**: Live channels suffer from dead links and CDN rotation. Probing latency and resolving
/// official CNTV tokens dynamically ensures sub-second tuning and resilient 3-second auto-failover.
class IptvService {
  IptvService({
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
              ),
            );

  final Dio _dio;
  static const String _catalogCacheKey = 'iptv_channel_catalog_v1';
  static List<LiveChannel>? _memoryCatalog;
  final Map<String, _RouteProbeCacheEntry> _healthyRouteCache =
      <String, _RouteProbeCacheEntry>{};
  bool _isIpv6Supported = false;

  bool get isIpv6Supported => _isIpv6Supported;

  /// 读取上一次成功目录，让直播页遵循 stale-while-revalidate 而非空屏等待网络。
  Future<List<LiveChannel>> readCachedCatalog() async {
    final memoryCatalog = _memoryCatalog;
    if (memoryCatalog != null && memoryCatalog.isNotEmpty) {
      return List<LiveChannel>.of(memoryCatalog);
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_catalogCacheKey);
      if (raw == null || raw.isEmpty) return <LiveChannel>[];
      final payload = json.decode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        (payload['savedAt'] as num?)?.toInt() ?? 0,
      );
      if (DateTime.now().difference(savedAt) > const Duration(days: 7)) {
        return <LiveChannel>[];
      }
      final channels = (payload['channels'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(_channelFromJson)
          .whereType<LiveChannel>()
          .toList(growable: false);
      _memoryCatalog = channels;
      return List<LiveChannel>.of(channels);
    } catch (error) {
      debugPrint('Error reading IPTV catalog cache: $error');
      return <LiveChannel>[];
    }
  }

  /// 仅在远端目录成功解析后原子替换缓存，网络故障不能覆盖最后可用目录。
  Future<void> cacheCatalog(List<LiveChannel> channels) async {
    if (channels.isEmpty) return;
    _memoryCatalog = List<LiveChannel>.of(channels);
    final payload = <String, dynamic>{
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'channels': channels.map(_channelToJson).toList(growable: false),
    };
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_catalogCacheKey, json.encode(payload));
  }

  Map<String, dynamic> _channelToJson(LiveChannel channel) {
    return <String, dynamic>{
      'id': channel.id,
      'name': channel.name,
      'category': channel.category,
      'channelNumber': channel.channelNumber,
      'logoUrl': channel.logoUrl,
      'catchupTemplate': channel.catchupTemplate,
      'routes': channel.routes
          .map(
            (route) => <String, dynamic>{
              'name': route.name,
              'url': route.url,
              'isIpv6': route.isIpv6,
              'resolution': route.resolution,
              'headers': route.headers,
            },
          )
          .toList(growable: false),
    };
  }

  LiveChannel? _channelFromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final name = json['name']?.toString();
    final category = json['category']?.toString();
    if (id == null || name == null || category == null) return null;
    final routes = (json['routes'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((route) {
          final url = route['url']?.toString();
          if (url == null || url.isEmpty) return null;
          final rawHeaders = route['headers'];
          final headers = rawHeaders is Map
              ? rawHeaders.map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                )
              : null;
          return LiveStreamRoute(
            name: route['name']?.toString() ?? '默认线路',
            url: url,
            isIpv6: route['isIpv6'] == true,
            resolution: route['resolution']?.toString() ?? '1080P',
            headers: headers,
          );
        })
        .whereType<LiveStreamRoute>()
        .toList(growable: false);
    return LiveChannel(
      id: id,
      name: name,
      category: category,
      channelNumber: (json['channelNumber'] as num?)?.toInt(),
      logoUrl: json['logoUrl']?.toString(),
      routes: routes,
      catchupTemplate: json['catchupTemplate']?.toString(),
    );
  }

  /// Probes network stack to detect if native IPv6 routing is available.
  Future<bool> probeNetworkStack() async {
    try {
      final addresses = await InternetAddress.lookup('ipv6.google.com')
          .timeout(const Duration(seconds: 2));
      _isIpv6Supported =
          addresses.any((a) => a.type == InternetAddressType.IPv6);
    } catch (_) {
      try {
        final socket = await Socket.connect(
          '2400:3200::1',
          53,
          timeout: const Duration(milliseconds: 1500),
        );
        socket.destroy();
        _isIpv6Supported = true;
      } catch (_) {
        _isIpv6Supported = false;
      }
    }
    debugPrint('IPTV Network Stack Probe: IPv6 Available = $_isIpv6Supported');
    return _isIpv6Supported;
  }

  /// Fetches and parses a remote M3U / TXT playlist from URL.
  Future<List<LiveChannel>> fetchRemotePlaylist(String url) async {
    return (await fetchRemoteCatalog(url)).channels;
  }

  /// 下载直播订阅，同时保留 M3U 首行声明的 XMLTV 地址。
  Future<IptvPlaylistCatalog> fetchRemoteCatalog(String url) async {
    try {
      final response = await _dio.get<String>(url);
      final content = response.data ?? '';
      if (content.contains('#EXTINF')) {
        return IptvPlaylistCatalog(
          channels: parseM3u(content),
          epgUrls: extractXmlTvUrls(content),
        );
      } else {
        return IptvPlaylistCatalog(channels: parseTxt(content));
      }
    } catch (e) {
      debugPrint('Error fetching remote playlist $url: $e');
      return const IptvPlaylistCatalog(channels: <LiveChannel>[]);
    }
  }

  /// 提取 M3U 的 `x-tvg-url`/`url-tvg` 声明，支持引号及逗号分隔的多源。
  List<String> extractXmlTvUrls(String m3uContent) {
    final header = m3uContent
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere(
          (line) => line.toUpperCase().startsWith('#EXTM3U'),
          orElse: () => '',
        );
    if (header.isEmpty) return <String>[];
    final match = RegExp(
      r'''(?:x-tvg-url|url-tvg)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s]+))''',
      caseSensitive: false,
    ).firstMatch(header);
    final value = match?.group(1) ?? match?.group(2) ?? match?.group(3);
    if (value == null || value.trim().isEmpty) return <String>[];
    return value
        .split(',')
        .map((url) => url.trim())
        .where((url) => Uri.tryParse(url)?.hasScheme ?? false)
        .toSet()
        .toList(growable: false);
  }

  /// 下载普通或 gzip/zlib 压缩的 XMLTV，并返回可用于频道合并的时间线。
  ///
  /// EPG 聚合站常以 `.xml.gz` 或启用 GZIP 传输以节省带宽。
  /// Dart HttpClient 在收到 Content-Encoding: gzip 时会自动解压，导致 response.data
  /// 已经是解压后的明文 XML 字节；直接检查二进制魔数（0x1f 0x8b）可精准判定是否真正需要 GZIP 解压，
  /// 彻底避免对已解压文本调用 gzip.decode 抛出 FormatException: Filter error, bad data。
  Future<List<EpgChannelSchedule>> fetchXmlTv(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        sendTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 6),
      ),
    );
    final bytes = response.data ?? <int>[];
    if (bytes.isEmpty) return <EpgChannelSchedule>[];

    List<int> decoded = bytes;
    // 检查 GZIP 魔数 (0x1F, 0x8B)
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        decoded = gzip.decode(bytes);
      } catch (e) {
        debugPrint('[IPTV] GZIP 解压失败，回退为原始字节：$e');
        decoded = bytes;
      }
    } else if (bytes.length >= 2 &&
        bytes[0] == 0x78 &&
        (bytes[1] == 0x01 || bytes[1] == 0x9c || bytes[1] == 0xda)) {
      // 检查 ZLIB 魔数 (0x78)
      try {
        decoded = zlib.decode(bytes);
      } catch (e) {
        debugPrint('[IPTV] ZLIB 解压失败，回退为原始字节：$e');
        decoded = bytes;
      }
    }

    final xmlContent = utf8.decode(decoded, allowMalformed: true);
    return parseXmlTv(xmlContent);
  }

  /// 按订阅声明顺序读取第一份可用 XMLTV，单个镜像损坏不影响直播目录。
  Future<List<EpgChannelSchedule>> fetchFirstAvailableXmlTv(
    Iterable<String> urls,
  ) async {
    final candidates = <String>{};
    for (final url in urls) {
      // fanmingming 的 .cn 域名已废弃不可达，重定向至稳定 .com 镜像，杜绝 5 秒连接超时
      if (url.contains('://live.fanmingming.cn/')) {
        candidates.add(
          url.replaceFirst(
            '://live.fanmingming.cn/',
            '://live.fanmingming.com/',
          ),
        );
      } else {
        candidates.add(url);
      }
    }

    // 注入高可用备用 EPG 镜像
    candidates.addAll(const <String>[
      'https://live.fanmingming.com/e.xml',
      'https://epg.112114.xyz/pp.xml',
    ]);

    for (final url in candidates) {
      try {
        final schedules = await fetchXmlTv(url);
        if (schedules.isNotEmpty) {
          debugPrint('[IPTV] 成功加载 ${schedules.length} 个频道的 EPG 节目单 ($url)');
          return schedules;
        }
      } catch (error) {
        debugPrint('[IPTV] EPG 镜像不可用 ($url)：$error');
      }
    }
    return <EpgChannelSchedule>[];
  }

  /// 解析 XMLTV 频道别名与节目，丢弃缺失频道、时间无效或倒置的条目。
  List<EpgChannelSchedule> parseXmlTv(String xmlContent) {
    if (xmlContent.trim().isEmpty) return <EpgChannelSchedule>[];
    try {
      final document = XmlDocument.parse(xmlContent);
      final displayNames = <String, List<String>>{};
      for (final channel in document.findAllElements('channel')) {
        final id = channel.getAttribute('id')?.trim();
        if (id == null || id.isEmpty) continue;
        displayNames[id] = channel
            .findElements('display-name')
            .map((element) => element.innerText.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList(growable: false);
      }

      final programsByChannel = <String, List<EpgProgram>>{};
      for (final programme in document.findAllElements('programme')) {
        final channelId = programme.getAttribute('channel')?.trim();
        final start = _parseXmlTvTimestamp(programme.getAttribute('start'));
        final stop = _parseXmlTvTimestamp(programme.getAttribute('stop'));
        final title =
            programme.findElements('title').firstOrNull?.innerText.trim();
        if (channelId == null ||
            channelId.isEmpty ||
            start == null ||
            stop == null ||
            !stop.isAfter(start) ||
            title == null ||
            title.isEmpty) {
          continue;
        }
        final overview =
            programme.findElements('desc').firstOrNull?.innerText.trim();
        programsByChannel.putIfAbsent(channelId, () => <EpgProgram>[]).add(
              EpgProgram(
                title: title,
                startTime: start,
                endTime: stop,
                overview:
                    overview == null || overview.isEmpty ? null : overview,
              ),
            );
      }

      final channelIds = <String>{
        ...displayNames.keys,
        ...programsByChannel.keys,
      };
      return channelIds.map((channelId) {
        final programs = programsByChannel[channelId] ?? <EpgProgram>[];
        programs
            .sort((left, right) => left.startTime.compareTo(right.startTime));
        return EpgChannelSchedule(
          channelId: channelId,
          displayNames: displayNames[channelId] ?? const <String>[],
          programs: List<EpgProgram>.unmodifiable(programs),
        );
      }).toList(growable: false);
    } catch (e) {
      debugPrint('[IPTV] XMLTV 解析异常：$e');
      return <EpgChannelSchedule>[];
    }
  }

  /// 把 XMLTV 时间线合并到直播目录，优先精确 `tvg-id`，再回退到频道别名。
  ///
  /// 名称匹配会移除画质、空白与“频道”等供应商噪声，但不会做包含匹配，
  /// 避免 CCTV-1 与 CCTV-11 这类相似名称发生串台。
  List<LiveChannel> applyEpgSchedules(
    List<LiveChannel> channels,
    List<EpgChannelSchedule> schedules, {
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final byId = <String, EpgChannelSchedule>{
      for (final schedule in schedules)
        schedule.channelId.toLowerCase(): schedule,
    };
    final byName = <String, EpgChannelSchedule>{};
    for (final schedule in schedules) {
      for (final name in schedule.displayNames) {
        byName.putIfAbsent(_normalizedChannelName(name), () => schedule);
      }
    }

    return channels.map((channel) {
      final schedule = byId[channel.id.toLowerCase()] ??
          byName[_normalizedChannelName(channel.name)];
      if (schedule == null) return channel;

      EpgProgram? current;
      EpgProgram? next;
      for (final program in schedule.programs) {
        if (!effectiveNow.isBefore(program.startTime) &&
            effectiveNow.isBefore(program.endTime)) {
          current = program;
          continue;
        }
        if (program.startTime.isAfter(effectiveNow)) {
          next = program;
          break;
        }
      }
      return LiveChannel(
        id: channel.id,
        name: channel.name,
        category: channel.category,
        channelNumber: channel.channelNumber,
        logoUrl: channel.logoUrl,
        routes: channel.routes,
        activeRouteIndex: channel.activeRouteIndex,
        currentProgram: current,
        nextProgram: next,
        epgPrograms: schedule.programs,
        catchupTemplate: channel.catchupTemplate,
      );
    }).toList(growable: false);
  }

  /// 使用 EPG 节目的起止时间展开标准回看模板，并解析为最终播放地址。
  ///
  /// `catchup-source` 既可能是完整 URL，也可能只是查询串；相对模板必须以
  /// 当前直播线路为基准解析，才能保留上游主机与路径契约。
  Uri? buildCatchupUri(LiveChannel channel, EpgProgram program) {
    final template = channel.catchupTemplate?.trim();
    final routeUrl = channel.activeRoute?.url;
    if (template == null || template.isEmpty || routeUrl == null) return null;

    final start = program.startTime.toLocal();
    final end = program.endTime.toLocal();
    final expanded = template
        .replaceAll(r'${(b)yyyyMMddHHmmss}', _compactDateTime(start))
        .replaceAll(r'${(e)yyyyMMddHHmmss}', _compactDateTime(end))
        .replaceAll(
          r'${(b)timestamp}',
          '${program.startTime.millisecondsSinceEpoch ~/ 1000}',
        )
        .replaceAll(
          r'${(e)timestamp}',
          '${program.endTime.millisecondsSinceEpoch ~/ 1000}',
        );
    return Uri.parse(routeUrl).resolve(expanded);
  }

  DateTime? _parseXmlTvTimestamp(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{14})(?:\s*([+-]\d{4}))?').firstMatch(value);
    if (match == null) return null;
    final raw = match.group(1)!;
    final year = int.parse(raw.substring(0, 4));
    final month = int.parse(raw.substring(4, 6));
    final day = int.parse(raw.substring(6, 8));
    final hour = int.parse(raw.substring(8, 10));
    final minute = int.parse(raw.substring(10, 12));
    final second = int.parse(raw.substring(12, 14));
    final offset = match.group(2);
    if (offset == null) {
      return DateTime(year, month, day, hour, minute, second);
    }
    final sign = offset.startsWith('-') ? -1 : 1;
    final offsetDuration = Duration(
      hours: int.parse(offset.substring(1, 3)),
      minutes: int.parse(offset.substring(3, 5)),
    );
    return DateTime.utc(year, month, day, hour, minute, second).subtract(
      sign == 1 ? offsetDuration : -offsetDuration,
    );
  }

  String _compactDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}'
        '${twoDigits(value.month)}${twoDigits(value.day)}'
        '${twoDigits(value.hour)}${twoDigits(value.minute)}'
        '${twoDigits(value.second)}';
  }

  /// 按顺序尝试同一订阅的不同交付地址，并可校验目标频道是否完整。
  ///
  /// 直播目录不应因为 CDN 域名短暂不可达或上游清单被截断而丢失整组频道；
  /// 调用方可以要求结果至少包含卫视等关键频道，再接受该交付地址。
  Future<List<LiveChannel>> fetchFirstAvailablePlaylist(
    List<String> urls, {
    bool Function(LiveChannel channel)? requiredChannel,
  }) async {
    List<LiveChannel> firstNonEmpty = <LiveChannel>[];
    for (final url in urls) {
      final channels = await fetchRemotePlaylist(url);
      if (channels.isEmpty) continue;
      firstNonEmpty = firstNonEmpty.isEmpty ? channels : firstNonEmpty;
      if (requiredChannel == null || channels.any(requiredChannel)) {
        return channels;
      }
    }
    return firstNonEmpty;
  }

  /// 按顺序尝试订阅镜像，并保留成功镜像携带的 EPG 元数据。
  Future<IptvPlaylistCatalog> fetchFirstAvailableCatalog(
    List<String> urls, {
    bool Function(LiveChannel channel)? requiredChannel,
  }) async {
    IptvPlaylistCatalog? firstNonEmpty;
    for (final url in urls) {
      final catalog = await fetchRemoteCatalog(url);
      if (catalog.channels.isEmpty) continue;
      firstNonEmpty ??= catalog;
      if (requiredChannel == null || catalog.channels.any(requiredChannel)) {
        return catalog;
      }
    }
    return firstNonEmpty ??
        const IptvPlaylistCatalog(channels: <LiveChannel>[]);
  }

  /// 并发加载多个直播订阅，并把同一频道的不同线路聚合为故障切换候选。
  ///
  /// 上游 IPTV 清单经常出现“目录仍在线、部分线路已失效”的半故障状态，
  /// 因此不能在第一个清单能解析时就停止；按规范化频道名合并后才能在播放前
  /// 对多条独立线路进行真实 HLS 分片探测。
  Future<List<LiveChannel>> fetchAndMergePlaylists(List<String> urls) async {
    final results = await Future.wait(
      urls.map(fetchRemotePlaylist),
    );
    return _mergeChannelRoutes(
      results.expand((channels) => channels).toList(growable: false),
    );
  }

  /// 依据稳定的业务分类筛选频道，不把空分类错误回退成完整频道列表。
  List<LiveChannel> filterChannelsByCategory(
    List<LiveChannel> channels,
    String category,
  ) {
    return channels.where((channel) {
      switch (category) {
        case '央视频道':
          return channel.category.contains('央视') ||
              channel.name.toUpperCase().contains('CCTV');
        case '卫视':
          return channel.category.contains('卫视') || channel.name.contains('卫视');
        case '4K/8K 专区':
          return channel.name.toUpperCase().contains('4K') ||
              channel.name.toUpperCase().contains('8K');
        case '体育赛事':
          return channel.name.contains('体育') || channel.category.contains('体育');
        default:
          return true;
      }
    }).toList(growable: false);
  }

  /// Parses extended M3U / M3U8 playlist strings into structured [LiveChannel] lists.
  List<LiveChannel> parseM3u(String m3uContent) {
    final channels = <LiveChannel>[];
    final lines = m3uContent.split(RegExp(r'\r?\n'));

    String currentCategory = '其他频道';
    String? currentName;
    String? currentLogo;
    String? currentTvgId;
    String? currentCatchup;
    Map<String, String>? currentHeaders;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        // Parse attributes
        final groupMatch = RegExp(r'group-title="([^"]+)"').firstMatch(line);
        if (groupMatch != null) {
          currentCategory = groupMatch.group(1) ?? currentCategory;
        }

        final logoMatch = RegExp(r'tvg-logo="([^"]+)"').firstMatch(line);
        if (logoMatch != null) {
          currentLogo = logoMatch.group(1);
        }

        final tvgIdMatch = RegExp(r'tvg-id="([^"]+)"').firstMatch(line);
        if (tvgIdMatch != null) {
          currentTvgId = tvgIdMatch.group(1);
        }

        final catchupMatch =
            RegExp(r'catchup-source="([^"]+)"').firstMatch(line);
        if (catchupMatch != null) {
          currentCatchup = catchupMatch.group(1);
        }

        final commaIndex = line.lastIndexOf(',');
        if (commaIndex != -1 && commaIndex < line.length - 1) {
          currentName = line.substring(commaIndex + 1).trim();
        }
      } else if (line.startsWith('#EXTVLCOPT:http-user-agent=')) {
        currentHeaders ??= <String, String>{};
        currentHeaders['User-Agent'] =
            line.substring('#EXTVLCOPT:http-user-agent='.length).trim();
      } else if (line.startsWith('#EXTVLCOPT:http-referrer=')) {
        currentHeaders ??= <String, String>{};
        currentHeaders['Referer'] =
            line.substring('#EXTVLCOPT:http-referrer='.length).trim();
      } else if (line.startsWith('#EXTHTTP:')) {
        try {
          final jsonStr = line.substring('#EXTHTTP:'.length).trim();
          final map = json.decode(jsonStr) as Map<String, dynamic>;
          currentHeaders ??= <String, String>{};
          map.forEach((k, v) => currentHeaders![k] = v.toString());
        } catch (_) {}
      } else if (!line.startsWith('#')) {
        // Playable URL line
        if (currentName != null &&
            currentName.isNotEmpty &&
            _isStreamUrl(line)) {
          final url = line;
          final isIpv6 =
              url.contains('[24') || url.contains('[20') || url.contains('[28');

          final route = LiveStreamRoute(
            name: '线路 1',
            url: url,
            isIpv6: isIpv6,
            headers: currentHeaders,
          );

          channels.add(
            LiveChannel(
              id: currentTvgId ?? 'ch_${channels.length + 1}',
              name: currentName,
              category: currentCategory,
              logoUrl: currentLogo,
              routes: <LiveStreamRoute>[route],
              catchupTemplate: currentCatchup,
            ),
          );
        }

        currentName = null;
        currentLogo = null;
        currentTvgId = null;
        currentCatchup = null;
        currentHeaders = null;
      }
    }

    return _mergeChannelRoutes(channels);
  }

  /// Parses standard Chinese grouped TXT format (e.g. `央视频道,#genre# \n CCTV-1,http://...`).
  List<LiveChannel> parseTxt(String txtContent) {
    final channels = <LiveChannel>[];
    final lines = txtContent.split(RegExp(r'\r?\n'));
    String currentCategory = '常用频道';

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.contains(',#genre#')) {
        currentCategory = trimmed.split(',')[0].trim();
        continue;
      }

      final commaParts = trimmed.split(',');
      if (commaParts.length >= 2) {
        final channelName = commaParts[0].trim();
        final rawUrlPart = commaParts.sublist(1).join(',').trim();

        final dollarParts = rawUrlPart.split(r'$');
        final streamUrl = dollarParts[0].trim();
        if (channelName.isEmpty || !_isStreamUrl(streamUrl)) continue;
        final routeLabel =
            dollarParts.length > 1 ? dollarParts[1].trim() : '默认线路';

        final isIpv6 = streamUrl.contains('[24') ||
            streamUrl.contains('[20') ||
            streamUrl.contains('[28');

        final route = LiveStreamRoute(
          name: routeLabel,
          url: streamUrl,
          isIpv6: isIpv6,
        );

        channels.add(
          LiveChannel(
            id: 'txt_${channelName.hashCode.abs()}',
            name: channelName,
            category: currentCategory,
            routes: <LiveStreamRoute>[route],
          ),
        );
      }
    }

    return _mergeChannelRoutes(channels);
  }

  /// Rejects error-page text while retaining non-HTTP IPTV transport URLs.
  bool _isStreamUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// Merges duplicate channels with the same name into a single [LiveChannel] with multiple candidate routes.
  List<LiveChannel> _mergeChannelRoutes(List<LiveChannel> list) {
    final map = <String, LiveChannel>{};

    for (final ch in list) {
      final key = _normalizedChannelName(ch.name);
      if (!map.containsKey(key)) {
        map[key] = ch;
      } else {
        final existing = map[key]!;
        final updatedRoutes = List<LiveStreamRoute>.from(existing.routes)
          ..addAll(
            ch.routes.where(
              (route) => !existing.routes.any(
                (candidate) => candidate.url == route.url,
              ),
            ),
          );
        map[key] = existing.copyWith(routes: updatedRoutes);
      }
    }

    return map.values.toList();
  }

  String _normalizedChannelName(String name) {
    return name
        .toUpperCase()
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'\b(?:HD|FHD|UHD|4K|8K)\b'), '')
        .replaceAll(RegExp(r'(高清|超清|标清|频道)'), '')
        .replaceAll(RegExp(r'[\s_-]+'), '');
  }

  /// Dynamically resolves an official CCTV live or VOD stream via CNTV / VDN JSON API.
  Future<String?> resolveCctvStream(String guid) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://vdn.apps.cntv.cn/api/getHttpVideoInfo.do',
        queryParameters: <String, dynamic>{
          'pid': guid,
          'tz': -8,
          'from': '000news',
        },
      );

      final data = response.data;
      if (data != null && data['hls_url'] != null) {
        return data['hls_url'].toString();
      }
      if (data != null && data['video'] != null) {
        final chapters = data['video']['chapters'] as List?;
        if (chapters != null && chapters.isNotEmpty) {
          return chapters[0]['url']?.toString();
        }
      }
    } catch (e) {
      debugPrint('Error resolving CCTV stream for guid $guid: $e');
    }
    return null;
  }

  /// 多线路并发竞速，第一条读取到真实媒体分片的线路立即胜出并取消其他请求。
  ///
  /// 逐条等待会把多个 3 秒网络超时串成十几秒；首胜竞速配合总时间预算既能
  /// 保证检测真实性，也能让存在官方兜底的频道快速进入下一阶段。
  Future<LiveStreamRoute?> probeFirstHealthyRoute(
    Iterable<LiveStreamRoute> routes, {
    Duration maxWait = const Duration(milliseconds: 2200),
    int maxCandidates = 6,
  }) async {
    return (await probeRoutes(
      routes,
      maxWait: maxWait,
      maxCandidates: maxCandidates,
    ))
        .healthyRoute;
  }

  /// 区分已验证的 HLS 失败与未知状态；非 HLS、未探测及预算中止不能排除原生播放。
  Future<({LiveStreamRoute? healthyRoute, bool allRoutesFailed})> probeRoutes(
    Iterable<LiveStreamRoute> routes, {
    Duration maxWait = const Duration(milliseconds: 2200),
    int maxCandidates = 6,
  }) async {
    final allRoutes = routes.toList(growable: false);
    final candidates = allRoutes.take(maxCandidates).toList(growable: false);
    if (candidates.isEmpty) {
      return (healthyRoute: null, allRoutesFailed: false);
    }
    final coversAllHlsRoutes = candidates.length == allRoutes.length &&
        candidates.every((route) {
          final uri = Uri.tryParse(route.url);
          return uri != null &&
              (uri.scheme == 'http' || uri.scheme == 'https') &&
              uri.path.toLowerCase().endsWith('.m3u8');
        });

    final now = DateTime.now();
    for (final route in candidates) {
      final cached = _healthyRouteCache[route.url];
      if (cached != null && cached.expiresAt.isAfter(now)) {
        return (
          healthyRoute: route.copyWith(
            latencyMs: cached.latencyMs,
            speedMib: cached.speedMib,
          ),
          allRoutesFailed: false,
        );
      }
    }

    final completer =
        Completer<({LiveStreamRoute? healthyRoute, bool allRoutesFailed})>();
    final cancelTokens = <CancelToken>[
      for (var index = 0; index < candidates.length; index++) CancelToken(),
    ];
    var remaining = candidates.length;
    var allRoutesFailed = coversAllHlsRoutes;

    void complete(LiveStreamRoute? route, {bool allRoutesFailed = false}) {
      if (completer.isCompleted) return;
      completer.complete(
        (healthyRoute: route, allRoutesFailed: allRoutesFailed),
      );
      for (final token in cancelTokens) {
        if (!token.isCancelled) token.cancel('已有线路胜出或探测预算已结束');
      }
    }

    final budgetTimer = Timer(maxWait, () => complete(null));
    for (var index = 0; index < candidates.length; index++) {
      unawaited(
        _probeRouteResult(
          candidates[index],
          cancelToken: cancelTokens[index],
          requestTimeout: const Duration(milliseconds: 900),
        ).then((result) {
          if (!result.failed) allRoutesFailed = false;
          final route = result.route;
          if (route.latencyMs >= 0) {
            _healthyRouteCache[route.url] = _RouteProbeCacheEntry(
              expiresAt: DateTime.now().add(const Duration(minutes: 5)),
              latencyMs: route.latencyMs,
              speedMib: route.speedMib,
            );
            complete(route);
          }
        }).whenComplete(() {
          remaining--;
          if (remaining == 0) {
            complete(null, allRoutesFailed: allRoutesFailed);
          }
        }),
      );
    }

    final result = await completer.future;
    budgetTimer.cancel();
    return result;
  }

  /// Measures route latency through the first media bytes, without claiming throughput.
  Future<LiveStreamRoute> probeRoute(
    LiveStreamRoute route, {
    CancelToken? cancelToken,
    Duration requestTimeout = const Duration(seconds: 3),
  }) async {
    return (await _probeRouteResult(
      route,
      cancelToken: cancelToken,
      requestTimeout: requestTimeout,
    ))
        .route;
  }

  /// Transport timeouts and cancelled probes cannot disqualify native playback.
  Future<({LiveStreamRoute route, bool failed})> _probeRouteResult(
    LiveStreamRoute route, {
    CancelToken? cancelToken,
    required Duration requestTimeout,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final res = await _probeHlsRoute(
        route,
        cancelToken: cancelToken,
        requestTimeout: requestTimeout,
      );
      sw.stop();
      if (res) {
        return (
          route: route.copyWith(
            latencyMs: sw.elapsedMilliseconds,
            speedMib: 0.0,
          ),
          failed: false,
        );
      }
      return (route: route.copyWith(latencyMs: -1), failed: true);
    } on DioException catch (error) {
      return (
        route: route.copyWith(latencyMs: -1),
        failed: error.type == DioExceptionType.badResponse,
      );
    } catch (_) {
      return (route: route.copyWith(latencyMs: -1), failed: false);
    } finally {
      sw.stop();
    }
  }

  /// 验证 HLS 清单及其实际媒体分片，避免把“清单 200、分片 5XX”误判为可播。
  Future<bool> _probeHlsRoute(
    LiveStreamRoute route, {
    CancelToken? cancelToken,
    required Duration requestTimeout,
  }) async {
    var manifestUri = Uri.parse(route.url);
    for (var depth = 0; depth < 2; depth++) {
      final response = await _dio.get<String>(
        manifestUri.toString(),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.plain,
          headers: route.headers,
          sendTimeout: requestTimeout,
          receiveTimeout: requestTimeout,
        ),
      );
      if (response.statusCode != 200 ||
          !(response.data ?? '').contains('#EXTM3U')) {
        return false;
      }

      final mediaPath = (response.data ?? '')
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .firstWhere(
            (line) => line.isNotEmpty && !line.startsWith('#'),
            orElse: () => '',
          );
      if (mediaPath.isEmpty) return false;
      final mediaUri = response.realUri.resolve(mediaPath);
      if (mediaPath.toLowerCase().contains('.m3u8')) {
        manifestUri = mediaUri;
        continue;
      }

      final segment = await _dio.get<ResponseBody>(
        mediaUri.toString(),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: <String, String>{
            'Range': 'bytes=0-65535',
            ...?route.headers,
          },
          sendTimeout: requestTimeout,
          receiveTimeout: requestTimeout,
        ),
      );
      final body = segment.data;
      if (body == null) return false;
      if (segment.statusCode != 200 && segment.statusCode != 206) {
        await body.stream.listen(null).cancel();
        return false;
      }
      // A successful response header is not media evidence; any cancels the
      // subscription after the first bytes, including servers ignoring Range.
      return body.stream
          .timeout(requestTimeout)
          .any((chunk) => chunk.isNotEmpty);
    }
    return false;
  }
}

class _RouteProbeCacheEntry {
  const _RouteProbeCacheEntry({
    required this.expiresAt,
    required this.latencyMs,
    required this.speedMib,
  });

  final DateTime expiresAt;
  final int latencyMs;
  final double speedMib;
}
