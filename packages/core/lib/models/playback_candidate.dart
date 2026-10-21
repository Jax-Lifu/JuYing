/// Represents an individual playable episode within a specific candidate source.
class PlaybackEpisode {
  const PlaybackEpisode({
    required this.name,
    required this.url,
    this.sortIndex = 1,
    this.duration = Duration.zero,
    this.badge,
    this.headers,
    this.webHeaders,
    this.officialPageUrl,
    this.thumbnailUrl,
    this.resolvePlayback,
    this.requiresWebView = false,
  });

  /// Display name of the episode (e.g. `第01集`, `1080P原画`, `预告`).
  final String name;

  /// Media URL, or a source play ID while [resolvePlayback] is pending.
  final String url;

  /// Resolves only the selected episode so expiring URLs and request headers
  /// are obtained at playback time, without fetching every episode's player API.
  final Future<PlaybackEpisode> Function()? resolvePlayback;

  /// The resolved URL is a player page that must yield a media URL before mpv opens it.
  final bool requiresWebView;

  /// Numeric sequence index for sequential auto-playing next episode.
  final int sortIndex;

  /// Matches a named episode across source order changes. Only explicit 第N集
  /// labels normalize spaces/leading zeros; unnamed entries use their index.
  bool matchesIdentity({required String name, required int sortIndex}) {
    String normalizedName(String value) => value.trim().replaceFirstMapped(
          RegExp(r'^第\s*0*(\d+)\s*集$'),
          (match) => '第${match.group(1)}集',
        );

    final ownName = normalizedName(this.name);
    final otherName = normalizedName(name);
    return ownName.isNotEmpty
        ? ownName == otherName
        : otherName.isEmpty && this.sortIndex == sortIndex;
  }

  /// Source-declared programme duration used while HLS demuxers temporarily
  /// report the duration of only the first media segment.
  final Duration duration;

  /// Quality or format badge (e.g. `4K`, `VIP`, `国语`).
  final String? badge;

  /// Custom HTTP headers required for anti-leeching (User-Agent, Referer, Cookie).
  final Map<String, String>? headers;

  /// 可选的解析页导航请求头；空 Map 表示不要把媒体凭据发送给解析站。
  final Map<String, String>? webHeaders;

  /// CCTV 官网剧集页。官网 WebView 通过自身 DRM 链路提供高清与超清，
  /// 不把受保护的临时媒体地址泄漏到通用播放候选模型中。
  final String? officialPageUrl;

  /// 站源提供的单集缩略图，仅用于播放候选 UI，不污染规范媒体实体。
  final String? thumbnailUrl;

  /// Compact label used in dense episode grids (for example `第12集`).
  ///
  /// CCTV titles repeat the full programme name before every episode number;
  /// extracting the stable episode marker keeps adjacent buttons distinguishable.
  String get shortName {
    final match = RegExp(r'第\s*(\d+)\s*集').firstMatch(name);
    return match == null ? name : '第${match.group(1)}集';
  }

  /// Descriptive text following the episode marker, if the source provides it.
  String? get subtitle {
    final match = RegExp(r'第\s*\d+\s*集').firstMatch(name);
    if (match == null) return null;
    final value = name.substring(match.end).trim();
    return value.isEmpty ? null : value;
  }
}

/// Represents a specific playable stream source candidate (Candidate Layer).
///
/// **Why**: A canonical [MediaItem] can have dozens of playable sources (Spider Site A,
/// Spider Site B, Aliyun Drive 4K, 115 Drive, Local Samba NAS). Decoupling source routes
/// from identity allows real-time health probing, bitrate sorting, and in-place line switching.
class PlaybackCandidate {
  const PlaybackCandidate({
    required this.sourceKey,
    required this.sourceName,
    required this.lineName,
    this.episodes = const <PlaybackEpisode>[],
    this.resolution = '1080P',
    this.latencyMs,
    this.isCloudDrive = false,
    this.isVip = false,
  });

  /// Unique key of the source spider/adapter (e.g. `site_fantaiying`, `aliyun_pan`).
  final String sourceKey;

  /// Human-readable source provider name (e.g. `饭太硬`, `肥猫专线`, `阿里云盘`).
  final String sourceName;

  /// Specific line or route identifier (e.g. `线路1 (4K极速)`, `蓝光专线`).
  final String lineName;

  /// Ordered list of available episodes under this specific line.
  final List<PlaybackEpisode> episodes;

  /// Estimated video resolution tag (`4K`, `1080P`, `720P`).
  final String resolution;

  /// Measured network response latency in milliseconds.
  final int? latencyMs;

  /// Whether this source candidate originates from a personal cloud drive.
  final bool isCloudDrive;

  /// Whether this source candidate requires special VIP or login tokens.
  final bool isVip;
}
