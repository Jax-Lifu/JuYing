import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/core/models/live_channel.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/cctv/models/cctv_channel.dart';
import 'package:juying/features/live/services/iptv_service.dart';
import 'package:juying/features/player/presentation/cctv_official_web_player_page.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// IPTV Live Channel broadcasting center with multi-line switching and EPG schedule timeline.
///
/// **What**: Displays categories, channel rosters with latency badges, EPG timeline progress,
/// and fast switching interfaces with instant transition to fullscreen live player.
///
/// **Why**: Linear TV viewers expect sub-second channel tuning, prominent live program indicators,
/// and seamless multi-line failover between IPv4 and IPv6 routes.
class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  static const List<String> _playlistDeliveryUrls = <String>[
    'https://live.fanmingming.com/tv/m3u/global.m3u',
    'https://raw.githubusercontent.com/Ftindy/IPTV-URL/main/cctv.m3u',
    'https://epg.112114.xyz/pp.m3u',
    'https://live.fanmingming.com/tv/m3u/ipv6.m3u',
    'https://raw.githubusercontent.com/ssili126/tv/main/itvlist.m3u',
  ];

  /// 央视频官网为省级卫视保留播放授权与动态签名，Windows 端在公网
  /// M3U 分片不可达时直接保留该官网上下文播放，不复制其临时媒体地址。
  static const Map<String, String> _yangshipinSatellitePids = <String, String>{
    '北京卫视': '600002309',
    '江苏卫视': '600002521',
    '东方卫视': '600002483',
    '浙江卫视': '600002520',
    '湖南卫视': '600002475',
    '湖北卫视': '600002508',
    '广东卫视': '600002485',
    '广西卫视': '600002509',
    '黑龙江卫视': '600002498',
    '海南卫视': '600002506',
    '重庆卫视': '600002531',
    '深圳卫视': '600002481',
    '四川卫视': '600002516',
    '河南卫视': '600002525',
    '东南卫视': '600002484',
    '贵州卫视': '600002490',
    '江西卫视': '600002503',
    '辽宁卫视': '600002505',
    '安徽卫视': '600002532',
    '河北卫视': '600002493',
    '山东卫视': '600002513',
    '天津卫视': '600152137',
    '吉林卫视': '600190405',
    '陕西卫视': '600190400',
    '宁夏卫视': '600190737',
    '内蒙古卫视': '600190401',
    '云南卫视': '600190402',
    '山西卫视': '600190407',
    '青海卫视': '600190406',
    '西藏卫视': '600190403',
    '甘肃卫视': '600190408',
  };

  final IptvService _iptvService = IptvService();
  int _selectedCategoryIndex = 0;
  int _selectedChannelIndex = 0;
  List<LiveChannel> _channels = <LiveChannel>[];
  final Set<String> _probingChannelIds = <String>{};
  final bool _isLoading = false;

  final List<String> _categories = const <String>[
    '央视频道',
    '卫视',
    '4K/8K 专区',
    '体育赛事',
  ];

  final List<LiveChannel> _defaultChannels = <LiveChannel>[
    LiveChannel(
      id: 'cctv1',
      name: 'CCTV-1 综合 (1080P)',
      category: '央视频道',
      channelNumber: 1,
      routes: const <LiveStreamRoute>[
        LiveStreamRoute(
          name: '电信IPv6 专线',
          url:
              'http://[2409:8087:8:21::18]:6610/otttv.bj.chinamobile.com/PLTV/88888888/224/3221226895/1.m3u8',
          isIpv6: true,
          resolution: '1080P',
          latencyMs: 28,
        ),
        LiveStreamRoute(
          name: '北京联通 直播',
          url:
              'http://[2409:8087:8:21::18]:6610/otttv.bj.chinamobile.com/PLTV/88888888/224/3221226895/1.m3u8',
          isIpv6: false,
          resolution: '1080P',
          latencyMs: 42,
        ),
      ],
      currentProgram: EpgProgram(
        title: '今日说法 / 新闻联播',
        startTime: DateTime.now().subtract(const Duration(minutes: 20)),
        endTime: DateTime.now().add(const Duration(minutes: 20)),
      ),
      nextProgram: EpgProgram(
        title: '时代楷模发布厅',
        startTime: DateTime.now().add(const Duration(minutes: 20)),
        endTime: DateTime.now().add(const Duration(minutes: 60)),
      ),
    ),
    LiveChannel(
      id: 'cctv2',
      name: 'CCTV-2 财经 (4K)',
      category: '央视频道',
      channelNumber: 2,
      routes: const <LiveStreamRoute>[
        LiveStreamRoute(
          name: '线路1 (超高清4K)',
          url:
              'http://[2409:8087:8:21::18]:6610/otttv.bj.chinamobile.com/PLTV/88888888/224/3221226893/1.m3u8',
          isIpv6: true,
          resolution: '4K',
          latencyMs: 32,
        ),
      ],
      currentProgram: EpgProgram(
        title: '正点财经',
        startTime: DateTime.now().subtract(const Duration(minutes: 10)),
        endTime: DateTime.now().add(const Duration(minutes: 50)),
      ),
    ),
    LiveChannel(
      id: 'cctv5',
      name: 'CCTV-5 体育 (50fps)',
      category: '央视频道',
      channelNumber: 5,
      routes: const <LiveStreamRoute>[
        LiveStreamRoute(
          name: '线路1 (低延迟原画)',
          url:
              'http://[2409:8087:8:21::18]:6610/otttv.bj.chinamobile.com/PLTV/88888888/224/3221226469/1.m3u8',
          resolution: '1080P',
          latencyMs: 18,
        ),
      ],
      currentProgram: EpgProgram(
        title: '体育新闻 / 现场直播',
        startTime: DateTime.now().subtract(const Duration(minutes: 35)),
        endTime: DateTime.now().add(const Duration(minutes: 25)),
      ),
    ),
    LiveChannel(
      id: 'cctv13',
      name: 'CCTV-13 新闻',
      category: '央视频道',
      channelNumber: 13,
      routes: const <LiveStreamRoute>[
        LiveStreamRoute(
          name: '线路1 (官方流)',
          url:
              'http://[2409:8087:8:21::18]:6610/otttv.bj.chinamobile.com/PLTV/88888888/224/3221226316/1.m3u8',
          resolution: '1080P',
          latencyMs: 22,
        ),
      ],
      currentProgram: EpgProgram(
        title: '新闻直播间',
        startTime: DateTime.now().subtract(const Duration(minutes: 15)),
        endTime: DateTime.now().add(const Duration(minutes: 45)),
      ),
    ),
    LiveChannel(
      id: 'cctv14',
      name: 'CCTV-14 少儿',
      category: '央视频道',
      channelNumber: 14,
      routes: const <LiveStreamRoute>[
        LiveStreamRoute(
          name: '线路1 (少儿高清)',
          url:
              'http://[2409:8087:8:21::18]:6610/otttv.bj.chinamobile.com/PLTV/88888888/224/3221226317/1.m3u8',
          resolution: '1080P',
          latencyMs: 25,
        ),
      ],
      currentProgram: EpgProgram(
        title: '动画大放映',
        startTime: DateTime.now().subtract(const Duration(minutes: 5)),
        endTime: DateTime.now().add(const Duration(minutes: 55)),
      ),
    ),
  ];

  @override
  void initState() {
    super.initState();
    // 首帧先展示内置的官方可兜底目录；磁盘缓存与远端刷新都不能阻塞页面。
    _channels = _buildAvailableCatalog(_defaultChannels);
    unawaited(_loadLiveChannels());
  }

  Future<void> _loadLiveChannels() async {
    final cachedChannels = await _iptvService.readCachedCatalog();
    if (mounted && cachedChannels.isNotEmpty) {
      setState(() => _channels = _buildAvailableCatalog(cachedChannels));
    }

    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString('pref_iptv_playlist_url')?.trim() ?? '';
    final urls = <String>[
      if (customUrl.isNotEmpty) customUrl,
      ..._playlistDeliveryUrls,
    ];

    // 主订阅成功即可刷新 UI，备用地址只在主地址失败时使用；不再等待多个
    // 镜像与大体积聚合清单全部结束。
    final remoteCatalog = await _iptvService.fetchFirstAvailableCatalog(urls);
    final remoteChannels = remoteCatalog.channels;
    if (remoteChannels.isEmpty) return;
    var availableCatalog = _buildAvailableCatalog(remoteChannels);

    if (mounted) {
      setState(() => _channels = availableCatalog);
    }
    final schedules = await _iptvService.fetchFirstAvailableXmlTv(
      remoteCatalog.epgUrls,
    );
    if (schedules.isNotEmpty) {
      availableCatalog = _iptvService.applyEpgSchedules(
        availableCatalog,
        schedules,
      );
      if (mounted) {
        setState(() => _channels = availableCatalog);
      }
    }
    await _iptvService.cacheCatalog(availableCatalog);
  }

  /// 目录仅保留具备官方播放兜底的央视与省级卫视，避免把聚合清单中大量
  /// 仅有失效临时 URL 的频道暴露给用户。远端标准流仍保留并优先竞速。
  List<LiveChannel> _buildAvailableCatalog(List<LiveChannel> source) {
    final result = <LiveChannel>[];

    for (final official in CctvChannel.officialChannels) {
      LiveChannel? matched;
      for (final channel in source) {
        if (_matchOfficialCctvChannel(channel)?.id == official.id) {
          matched = channel;
          break;
        }
      }
      result.add(
        matched ??
            LiveChannel(
              id: official.id,
              name: official.name,
              category: '央视频道',
              channelNumber: int.tryParse(official.number),
              logoUrl: _cctvLogoUrl(official),
            ),
      );
    }

    for (final official in _yangshipinSatellitePids.entries) {
      LiveChannel? matched;
      for (final channel in source) {
        if (_matchYangshipinSatellite(channel)?.value == official.value) {
          matched = channel;
          break;
        }
      }
      result.add(
        matched ??
            LiveChannel(
              id: 'yangshipin_${official.value}',
              name: official.key,
              category: '卫视',
            ),
      );
    }

    return result;
  }

  List<LiveChannel> get _filteredChannels {
    final activeCat = _categories[_selectedCategoryIndex];
    return _iptvService.filterChannelsByCategory(_channels, activeCat);
  }

  List<PlaybackCandidate> _convertLiveRoutesToCandidates(LiveChannel channel) {
    return channel.routes.map((r) {
      return PlaybackCandidate(
        sourceKey: 'live_${channel.id}_${r.name}',
        sourceName: channel.name,
        lineName: r.name,
        resolution: r.resolution,
        episodes: <PlaybackEpisode>[
          PlaybackEpisode(
            name: channel.name,
            url: r.url,
            headers: r.headers,
          ),
        ],
      );
    }).toList();
  }

  CctvChannel? _matchOfficialCctvChannel(LiveChannel channel) {
    final name = channel.name.toUpperCase().replaceAll(' ', '');
    String? id;
    if (name.contains('CCTV-4K') || name.contains('CCTV4K')) {
      id = 'cctv4k';
    } else if (name.contains('CCTV-5+') || name.contains('CCTV5+')) {
      id = 'cctv5plus';
    } else {
      final match = RegExp(r'CCTV-?(\d+)').firstMatch(name);
      if (match != null) id = 'cctv${int.parse(match.group(1)!)}';
    }
    if (id == null) return null;
    for (final candidate in CctvChannel.officialChannels) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  PlaybackEpisode _officialLiveEpisode(CctvChannel channel, int index) {
    return PlaybackEpisode(
      name: channel.name,
      url: channel.officialPageUrl,
      sortIndex: index + 1,
      badge: channel.resolution,
      officialPageUrl: channel.officialPageUrl,
      thumbnailUrl: _cctvLogoUrl(channel),
    );
  }

  String _cctvLogoUrl(CctvChannel channel) {
    final assetName =
        channel.id == 'cctv5plus' ? 'CCTV5+' : channel.id.toUpperCase();
    return 'https://live.fanmingming.com/tv/$assetName.png';
  }

  void _openOfficialCctvPlayer(CctvChannel selected) {
    final episodes = <PlaybackEpisode>[
      for (var index = 0; index < CctvChannel.officialChannels.length; index++)
        _officialLiveEpisode(CctvChannel.officialChannels[index], index),
    ];
    final currentEpisode = episodes.firstWhere(
      (episode) => episode.officialPageUrl == selected.officialPageUrl,
    );

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => CctvOfficialWebPlayerPage(
          title: selected.name,
          currentEpisode: currentEpisode,
          episodes: episodes,
          isLive: true,
        ),
      ),
    );
  }

  MapEntry<String, String>? _matchYangshipinSatellite(LiveChannel channel) {
    final normalizedName = channel.name.replaceAll(RegExp(r'[\s(（].*$'), '');
    for (final entry in _yangshipinSatellitePids.entries) {
      if (normalizedName.contains(entry.key)) return entry;
    }
    return null;
  }

  /// 返回频道订阅声明的台标；卫视缺失台标时按央视频频道标准名补齐。
  ///
  /// fanmingming 的清单仍可能声明旧 `.cn` 域名，而该域名在部分 Windows
  /// 网络环境会 TLS 握手失败，因此统一切到内容相同的 `.com` 镜像。
  String? _channelLogoUrl(LiveChannel channel) {
    final officialCctv = _matchOfficialCctvChannel(channel);
    if (officialCctv != null) return _cctvLogoUrl(officialCctv);

    final declaredLogo = channel.logoUrl?.trim();
    if (declaredLogo != null && declaredLogo.isNotEmpty) {
      return declaredLogo.replaceFirst(
        'https://live.fanmingming.cn/',
        'https://live.fanmingming.com/',
      );
    }

    final satellite = _matchYangshipinSatellite(channel);
    if (satellite == null) return null;
    return 'https://live.fanmingming.com/tv/'
        '${Uri.encodeComponent(satellite.key)}.png';
  }

  Widget _channelLogo(
    LiveChannel channel,
    int fallbackNumber,
    AppThemeColors colors,
  ) {
    final logoUrl = _channelLogoUrl(channel);
    final fallback = Center(
      child: Text(
        '$fallbackNumber',
        style: TextStyle(
          color: colors.brandAccent,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    if (logoUrl == null) return fallback;

    return Padding(
      padding: const EdgeInsets.all(5),
      child: Image.network(
        logoUrl,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        cacheWidth: 96,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  PlaybackEpisode _yangshipinLiveEpisode(
    MapEntry<String, String> channel,
    int index,
  ) {
    final pageUrl = 'https://www.yangshipin.cn/tv/home?pid=${channel.value}';
    return PlaybackEpisode(
      name: channel.key,
      url: pageUrl,
      sortIndex: index + 1,
      badge: '官方直播',
      officialPageUrl: pageUrl,
      thumbnailUrl:
          'https://live.fanmingming.com/tv/${Uri.encodeComponent(channel.key)}.png',
    );
  }

  void _openYangshipinSatellitePlayer(MapEntry<String, String> selected) {
    final channels = _yangshipinSatellitePids.entries.toList(growable: false);
    final episodes = <PlaybackEpisode>[
      for (var index = 0; index < channels.length; index++)
        _yangshipinLiveEpisode(channels[index], index),
    ];
    final selectedPageUrl =
        'https://www.yangshipin.cn/tv/home?pid=${selected.value}';
    final currentEpisode = episodes.firstWhere(
      (episode) => episode.officialPageUrl == selectedPageUrl,
    );

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => CctvOfficialWebPlayerPage(
          title: selected.key,
          currentEpisode: currentEpisode,
          episodes: episodes,
          isLive: true,
        ),
      ),
    );
  }

  /// 播放前快速验证线路健康度并进入原生播放器，支持多线路自动熔断切台。
  Future<void> _openLivePlayer(LiveChannel channel) async {
    final officialCctv = _matchOfficialCctvChannel(channel);
    final yangshipinSatellite = _matchYangshipinSatellite(channel);

    if (_probingChannelIds.contains(channel.id)) return;
    setState(() => _probingChannelIds.add(channel.id));

    final routes = List<LiveStreamRoute>.of(channel.routes)
      ..sort((left, right) {
        if (left.isIpv6 == right.isIpv6) return 0;
        return left.isIpv6 ? 1 : -1;
      });

    LiveStreamRoute? healthyRoute;
    var allRoutesFailed = routes.isEmpty;
    if (routes.isNotEmpty) {
      final probe = await _iptvService.probeRoutes(
        routes,
        maxWait: const Duration(milliseconds: 1000),
      );
      healthyRoute = probe.healthyRoute;
      allRoutesFailed = probe.allRoutesFailed;
    }

    if (!mounted) return;
    setState(() => _probingChannelIds.remove(channel.id));

    // Only completed HLS failures rule out native routes. Unsupported formats,
    // unprobed candidates and a spent race budget still need a native attempt.
    if (allRoutesFailed && Platform.isWindows) {
      if (officialCctv != null) {
        _openOfficialCctvPlayer(officialCctv);
        return;
      }
      if (yangshipinSatellite != null) {
        _openYangshipinSatellitePlayer(yangshipinSatellite);
        return;
      }
    }

    if (routes.isNotEmpty) {
      final orderedRoutes = <LiveStreamRoute>[
        if (healthyRoute != null) healthyRoute,
        ...routes.where((r) => r.url != healthyRoute?.url),
      ];

      final playableChannel = channel.copyWith(routes: orderedRoutes);
      final candidates = _convertLiveRoutesToCandidates(playableChannel);
      final activeEp =
          candidates.isNotEmpty && candidates.first.episodes.isNotEmpty
              ? candidates.first.episodes.first
              : PlaybackEpisode(
                  name: channel.name,
                  url: playableChannel.activeRoute?.url ?? '',
                );

      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (context) => VideoPlayerPage(
            title: channel.name,
            currentEpisode: activeEp,
            isLive: true,
            onLiveChannelStep: (offset) =>
                _openAdjacentLiveChannel(channel, offset),
            candidate: candidates.isNotEmpty ? candidates.first : null,
            allCandidates: candidates,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${channel.name} 暂无可播放的直播线路')),
    );
  }

  /// 以频道声明的回看模板构造独立播放项，继续复用统一 media_kit 播放页。
  void _openCatchupProgram(LiveChannel channel, EpgProgram program) {
    final catchupUri = _iptvService.buildCatchupUri(channel, program);
    if (catchupUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该频道未提供可用的回看地址')),
      );
      return;
    }
    final episode = PlaybackEpisode(
      name: program.title,
      url: catchupUri.toString(),
      headers: channel.activeRoute?.headers,
    );
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => VideoPlayerPage(
          title: '${channel.name} · ${program.title}',
          currentEpisode: episode,
        ),
      ),
    );
  }

  String _programTime(EpgProgram program) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final start = program.startTime.toLocal();
    final end = program.endTime.toLocal();
    return '${twoDigits(start.hour)}:${twoDigits(start.minute)}'
        ' - ${twoDigits(end.hour)}:${twoDigits(end.minute)}';
  }

  void _openAdjacentLiveChannel(LiveChannel current, int offset) {
    if (!mounted) return;
    final channels = _filteredChannels;
    if (channels.length < 2) return;
    var currentIndex = channels.indexWhere(
      (channel) => channel.id == current.id && channel.name == current.name,
    );
    if (currentIndex < 0) currentIndex = 0;
    final targetIndex = (currentIndex + offset) % channels.length;
    setState(() => _selectedChannelIndex = targetIndex);
    unawaited(_openLivePlayer(channels[targetIndex]));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final currentList = _filteredChannels;
    final safeIndex =
        _selectedChannelIndex < currentList.length ? _selectedChannelIndex : 0;
    final selectedChannel =
        currentList.isNotEmpty ? currentList[safeIndex] : null;

    return Scaffold(
      backgroundColor: colors.backgroundDeep,
      body: Row(
        children: <Widget>[
          // Left Category Column
          Container(
            width: 200,
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              border: Border(
                right: BorderSide(
                  color: colors.surfaceElevation,
                ),
              ),
            ),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final isSelected = _selectedCategoryIndex == index;
                return TvFocusWrapper(
                  onTap: () {
                    setState(() {
                      _selectedCategoryIndex = index;
                      _selectedChannelIndex = 0;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colors.brandPrimary.withAlpha(40)
                          : Colors.transparent,
                      border: Border(
                        left: BorderSide(
                          color: isSelected
                              ? colors.brandPrimary
                              : Colors.transparent,
                          width: 4,
                        ),
                      ),
                    ),
                    child: Text(
                      _categories[index],
                      style: TextStyle(
                        color: isSelected
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Middle Channel List
          Expanded(
            flex: 3,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : currentList.isEmpty
                    ? Center(
                        child: Text(
                          '当前分类暂无可用频道',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: currentList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final channel = currentList[index];
                          final isSelected = safeIndex == index;

                          return TvFocusWrapper(
                            onTap: () {
                              setState(() {
                                _selectedChannelIndex = index;
                              });
                              _openLivePlayer(channel);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colors.surfaceElevation
                                    : colors.surfaceCard,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: colors.backgroundDeep,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: _channelLogo(
                                      channel,
                                      channel.channelNumber ?? index + 1,
                                      colors,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            Text(
                                              channel.name,
                                              style: TextStyle(
                                                color: colors.textPrimary,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (channel.activeRoute?.isIpv6 ==
                                                true)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: colors.brandPrimary
                                                      .withAlpha(60),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'IPv6',
                                                  style: TextStyle(
                                                    color: colors.focusBorder,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        if (channel.currentProgram != null)
                                          Row(
                                            children: <Widget>[
                                              Icon(
                                                Icons.fiber_manual_record,
                                                size: 10,
                                                color: colors.statusSuccess,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  '正在播出: ${channel.currentProgram!.title}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: colors.textSecondary,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (channel.activeRoute != null)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: <Widget>[
                                        Text(
                                          '${channel.activeRoute!.latencyMs} ms',
                                          style: TextStyle(
                                            color: colors.statusSuccess,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          channel.activeRoute!.resolution,
                                          style: TextStyle(
                                            color: colors.textTertiary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Right EPG Program Schedule Panel
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceCard,
                border: Border(
                  left: BorderSide(
                    color: colors.surfaceElevation,
                  ),
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: selectedChannel == null
                  ? const SizedBox.shrink()
                  : ListView(
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              '📺 节目单 (EPG)',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TvFocusWrapper(
                              onTap: () => _openLivePlayer(selectedChannel),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: colors.brandPrimary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '全屏播放',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (selectedChannel.currentProgram != null) ...<Widget>[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.surfaceElevation,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: <Widget>[
                                    Text(
                                      '当前节目',
                                      style: TextStyle(
                                        color: colors.brandAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '直播中',
                                      style: TextStyle(
                                        color: colors.focusBorder,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  selectedChannel.currentProgram!.title,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: selectedChannel
                                      .currentProgram!.progressRatio,
                                  backgroundColor: colors.backgroundDeep,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      colors.brandPrimary),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (selectedChannel.catchupTemplate != null &&
                            selectedChannel.epgPrograms.any(
                              (program) => program.endTime.isBefore(
                                DateTime.now(),
                              ),
                            )) ...<Widget>[
                          Text(
                            '近期回看',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final program in selectedChannel.epgPrograms
                              .where(
                                (item) => item.endTime.isBefore(DateTime.now()),
                              )
                              .toList(growable: false)
                              .reversed
                              .take(3))
                            TvFocusWrapper(
                              onTap: () => _openCatchupProgram(
                                selectedChannel,
                                program,
                              ),
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.replay,
                                  color: colors.brandAccent,
                                  size: 20,
                                ),
                                title: Text(
                                  program.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  _programTime(program),
                                  style: TextStyle(
                                    color: colors.textTertiary,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          '后续预告',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (selectedChannel.nextProgram != null) ...<Widget>[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.schedule,
                              color: colors.textTertiary,
                              size: 20,
                            ),
                            title: Text(
                              selectedChannel.nextProgram!.title,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '即将播出',
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
