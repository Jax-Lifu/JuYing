/// Represents an individual stream route for an IPTV channel.
class LiveStreamRoute {
  const LiveStreamRoute({
    required this.name,
    required this.url,
    this.isIpv6 = false,
    this.resolution = '1080P',
    this.latencyMs = -1,
    this.speedMib = 0.0,
    this.headers,
  });

  /// Name or label of the route (e.g. `线路1 (电信IPv6)`, `线路2 (移动IPv4)`).
  final String name;

  /// HLS / FLV / RTMP stream endpoint.
  final String url;

  /// Whether this stream route requires IPv6 network connectivity.
  final bool isIpv6;

  /// Resolution metadata (e.g. `4K`, `1080P`).
  final String resolution;

  /// Measured response latency in milliseconds (-1 if unmeasured).
  final int latencyMs;

  /// Measured throughput download speed in MiB/s.
  final double speedMib;

  /// Injected headers (e.g. User-Agent, Referer).
  final Map<String, String>? headers;

  LiveStreamRoute copyWith({
    String? name,
    String? url,
    bool? isIpv6,
    String? resolution,
    int? latencyMs,
    double? speedMib,
    Map<String, String>? headers,
  }) {
    return LiveStreamRoute(
      name: name ?? this.name,
      url: url ?? this.url,
      isIpv6: isIpv6 ?? this.isIpv6,
      resolution: resolution ?? this.resolution,
      latencyMs: latencyMs ?? this.latencyMs,
      speedMib: speedMib ?? this.speedMib,
      headers: headers ?? this.headers,
    );
  }
}

/// Represents an EPG (Electronic Program Guide) program entry.
class EpgProgram {
  const EpgProgram({
    required this.title,
    required this.startTime,
    required this.endTime,
    this.overview,
  });

  /// Program title (e.g. `今日说法`, `新闻联播`).
  final String title;

  /// Start timestamp.
  final DateTime startTime;

  /// End timestamp.
  final DateTime endTime;

  /// Optional episode summary.
  final String? overview;

  /// Whether this program is currently broadcasting live.
  bool get isLive {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  /// Calculated progress ratio (0.0 to 1.0) of the current broadcast.
  double get progressRatio {
    final now = DateTime.now();
    if (now.isBefore(startTime)) return 0.0;
    if (now.isAfter(endTime)) return 1.0;
    final total = endTime.difference(startTime).inSeconds;
    if (total <= 0) return 0.0;
    final elapsed = now.difference(startTime).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}

/// XMLTV 中单个频道的节目时间线与匹配别名。
///
/// XMLTV 的频道 ID 通常由 EPG 提供方定义，未必与直播源的 `tvg-id` 一致；
/// 保留全部 `display-name` 才能在 ID 失配时安全回退到规范化名称匹配。
class EpgChannelSchedule {
  const EpgChannelSchedule({
    required this.channelId,
    required this.displayNames,
    required this.programs,
  });

  final String channelId;
  final List<String> displayNames;
  final List<EpgProgram> programs;
}

/// 一份 IPTV 订阅解析后的频道目录及其声明的 XMLTV 数据源。
class IptvPlaylistCatalog {
  const IptvPlaylistCatalog({
    required this.channels,
    this.epgUrls = const <String>[],
  });

  final List<LiveChannel> channels;
  final List<String> epgUrls;
}

/// Represents a canonical live TV channel containing multiple failover stream lines and EPG schedule.
///
/// **Why**: In live broadcasting, single streams frequently stall or experience bandwidth fluctuations.
/// Bundling multiple candidate routes under a unified [LiveChannel] enables automatic 3-second
/// circuit-breaker line switching and IPv4/IPv6 intelligent route sorting.
class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    required this.category,
    this.channelNumber,
    this.logoUrl,
    this.routes = const <LiveStreamRoute>[],
    this.activeRouteIndex = 0,
    this.currentProgram,
    this.nextProgram,
    this.epgPrograms = const <EpgProgram>[],
    this.catchupTemplate,
  });

  /// Canonical channel identifier (e.g. `cctv1`, `zhejiang_hd`).
  final String id;

  /// Human-readable channel title (e.g. `CCTV-1 综合`).
  final String name;

  /// Genre category (e.g. `央视频道`, `地方卫视`, `4K专区`, `体育赛事`).
  final String category;

  /// Optional integer channel number for TV numeric keypad quick jumping (e.g. `101`).
  final int? channelNumber;

  /// Channel logo icon image URL.
  final String? logoUrl;

  /// Available candidate stream routes sorted by measured health and latency.
  final List<LiveStreamRoute> routes;

  /// Index of the currently active stream route in [routes].
  final int activeRouteIndex;

  /// Currently broadcasting program metadata.
  final EpgProgram? currentProgram;

  /// Upcoming next program metadata.
  final EpgProgram? nextProgram;

  /// 当前 XMLTV 时间窗内的完整节目列表，用于展示预告与发起回看。
  final List<EpgProgram> epgPrograms;

  /// Template string for timeshift catchup playback (e.g. `${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}`).
  final String? catchupTemplate;

  /// Active stream route.
  LiveStreamRoute? get activeRoute =>
      (routes.isNotEmpty && activeRouteIndex < routes.length)
          ? routes[activeRouteIndex]
          : null;

  LiveChannel copyWith({
    String? id,
    String? name,
    String? category,
    int? channelNumber,
    String? logoUrl,
    List<LiveStreamRoute>? routes,
    int? activeRouteIndex,
    EpgProgram? currentProgram,
    EpgProgram? nextProgram,
    List<EpgProgram>? epgPrograms,
    String? catchupTemplate,
  }) {
    return LiveChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      channelNumber: channelNumber ?? this.channelNumber,
      logoUrl: logoUrl ?? this.logoUrl,
      routes: routes ?? this.routes,
      activeRouteIndex: activeRouteIndex ?? this.activeRouteIndex,
      currentProgram: currentProgram ?? this.currentProgram,
      nextProgram: nextProgram ?? this.nextProgram,
      epgPrograms: epgPrograms ?? this.epgPrograms,
      catchupTemplate: catchupTemplate ?? this.catchupTemplate,
    );
  }
}
