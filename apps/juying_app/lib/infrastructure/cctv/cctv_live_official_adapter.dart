import '../../domain/models/media_source.dart';
import '../../domain/models/unified_media.dart';
import '../../domain/ports/media_source_adapter.dart';
import 'cctv_channel_logo_resolver.dart';

class CctvLiveOfficialAdapter implements MediaSourceAdapter {
  static const sourceId = 'cctv-live-official';
  static final entryUri = Uri.parse(
    'https://tv.cctv.com/live/index.shtml?spm=C28340.Pu9TN9YUsfNZ.E2PQtIunpEaz.2',
  );

  static const _channels = <_CctvLiveChannel>[
    // 央视频道
    _CctvLiveChannel('cctv1', 'CCTV-1 综合', '央视频道', pageSlug: 'cctv1'),
    _CctvLiveChannel('cctv2', 'CCTV-2 财经', '央视频道', pageSlug: 'cctv2'),
    _CctvLiveChannel('cctv3', 'CCTV-3 综艺', '央视频道', pageSlug: 'cctv3'),
    _CctvLiveChannel('cctv4', 'CCTV-4 中文国际', '央视频道', pageSlug: 'cctv4'),
    _CctvLiveChannel('cctv5', 'CCTV-5 体育', '央视频道', pageSlug: 'cctv5'),
    _CctvLiveChannel('cctv5plus', 'CCTV-5+ 体育赛事', '央视频道', pageSlug: 'cctv5plus'),
    _CctvLiveChannel('cctv6', 'CCTV-6 电影', '央视频道', pageSlug: 'cctv6'),
    _CctvLiveChannel('cctv7', 'CCTV-7 国防军事', '央视频道', pageSlug: 'cctv7'),
    _CctvLiveChannel('cctv8', 'CCTV-8 电视剧', '央视频道', pageSlug: 'cctv8'),
    _CctvLiveChannel('cctv9', 'CCTV-9 纪录', '央视频道', pageSlug: 'cctvjilu'),
    _CctvLiveChannel('cctv10', 'CCTV-10 科教', '央视频道', pageSlug: 'cctv10'),
    _CctvLiveChannel('cctv11', 'CCTV-11 戏曲', '央视频道', pageSlug: 'cctv11'),
    _CctvLiveChannel('cctv12', 'CCTV-12 社会与法', '央视频道', pageSlug: 'cctv12'),
    _CctvLiveChannel('cctv13', 'CCTV-13 新闻', '央视频道', pageSlug: 'cctv13'),
    _CctvLiveChannel('cctvchild', 'CCTV-14 少儿', '央视频道', pageSlug: 'cctvchild'),
    _CctvLiveChannel('cctv15', 'CCTV-15 音乐', '央视频道', pageSlug: 'cctv15'),
    _CctvLiveChannel('cctv16', 'CCTV-16 奥林匹克', '央视频道', pageSlug: 'cctv16'),
    _CctvLiveChannel('cctv17', 'CCTV-17 农业农村', '央视频道', pageSlug: 'cctv17'),
    _CctvLiveChannel('cctv4k', 'CCTV 4K 超高清', '央视频道', pageSlug: 'cctv4k'),
    _CctvLiveChannel('cctv8k', 'CCTV 8K 超高清', '央视频道', pageSlug: 'cctv8k'),
    _CctvLiveChannel('cgtn', 'CGTN 英语新闻', '央视频道', pageSlug: 'cctv9'),
    _CctvLiveChannel('cgtndoc', 'CGTN 纪录频道', '央视频道', pageSlug: 'cctvjilu'),

    // 各省地方卫视频道
    _CctvLiveChannel('hunan', '湖南卫视', '地方卫视', officialUrl: 'https://www.mgtv.com/live/'),
    _CctvLiveChannel('zhejiang', '浙江卫视', '地方卫视', officialUrl: 'http://www.cztv.com/live'),
    _CctvLiveChannel('jiangsu', '江苏卫视', '地方卫视', officialUrl: 'https://www.jstv.com/live/'),
    _CctvLiveChannel('dongfang', '东方卫视', '地方卫视', officialUrl: 'https://www.kankanews.com/live/'),
    _CctvLiveChannel('beijing', '北京卫视', '地方卫视', officialUrl: 'https://www.bjd.com.cn/'),
    _CctvLiveChannel('guangdong', '广东卫视', '地方卫视', officialUrl: 'https://www.gdtv.cn/tvChannelDetail/43'),
    _CctvLiveChannel('shenzhen', '深圳卫视', '地方卫视', officialUrl: 'https://www.sztv.com.cn/'),
    _CctvLiveChannel('shandong', '山东卫视', '地方卫视', officialUrl: 'https://www.iqilu.com/html/live/'),
    _CctvLiveChannel('henan', '河南卫视', '地方卫视', officialUrl: 'https://www.hntv.tv/'),
    _CctvLiveChannel('sichuan', '四川卫视', '地方卫视', officialUrl: 'https://www.sctv.com/live/'),
    _CctvLiveChannel('hubei', '湖北卫视', '地方卫视', officialUrl: 'https://news.hbtv.com.cn/'),
    _CctvLiveChannel('anhui', '安徽卫视', '地方卫视', officialUrl: 'https://www.ahtv.cn/'),
    _CctvLiveChannel('tianjin', '天津卫视', '地方卫视', officialUrl: 'https://www.tjtv.com.cn/'),
    _CctvLiveChannel('chongqing', '重庆卫视', '地方卫视', officialUrl: 'https://www.cbg.cn/live/'),
    _CctvLiveChannel('liaoning', '辽宁卫视', '地方卫视', officialUrl: 'https://www.lntv.tv/'),
    _CctvLiveChannel('heilongjiang', '黑龙江卫视', '地方卫视', officialUrl: 'https://www.hljtv.com/'),
    _CctvLiveChannel('jilin', '吉林卫视', '地方卫视', officialUrl: 'https://www.jlntv.cn/'),
    _CctvLiveChannel('hebei', '河北卫视', '地方卫视', officialUrl: 'https://www.hebtv.com/'),
    _CctvLiveChannel('shanxi1', '山西卫视', '地方卫视', officialUrl: 'http://www.sxrtv.com/'),
    _CctvLiveChannel('shanxi3', '陕西卫视', '地方卫视', officialUrl: 'http://www.snrtv.com/'),
    _CctvLiveChannel('jiangxi', '江西卫视', '地方卫视', officialUrl: 'http://www.jxntv.cn/'),
    _CctvLiveChannel('dongnan', '东南卫视', '地方卫视', officialUrl: 'https://www.fjtv.net/'),
    _CctvLiveChannel('haixia', '海峡卫视', '地方卫视', officialUrl: 'https://www.fjtv.net/'),
    _CctvLiveChannel('guangxi', '广西卫视', '地方卫视', officialUrl: 'https://www.gxtv.cn/'),
    _CctvLiveChannel('guizhou', '贵州卫视', '地方卫视', officialUrl: 'https://www.gzstv.com/'),
    _CctvLiveChannel('yunnan', '云南卫视', '地方卫视', officialUrl: 'https://www.yntv.net/'),
    _CctvLiveChannel('neimenggu', '内蒙古卫视', '地方卫视', officialUrl: 'https://www.nmtv.cn/'),
    _CctvLiveChannel('xinjiang', '新疆卫视', '地方卫视', officialUrl: 'http://www.xjtvs.com.cn/'),
    _CctvLiveChannel('xizang', '西藏卫视', '地方卫视', officialUrl: 'http://www.vtibet.cn/'),
    _CctvLiveChannel('ningxia', '宁夏卫视', '地方卫视', officialUrl: 'http://www.nxtv.cn/'),
    _CctvLiveChannel('qinghai', '青海卫视', '地方卫视', officialUrl: 'http://www.qhtv.cn/'),
    _CctvLiveChannel('hainan', '海南卫视', '地方卫视', officialUrl: 'https://www.hnntv.cn/'),
    _CctvLiveChannel('bingtuan', '兵团卫视', '地方卫视', officialUrl: 'http://www.btzx.com.cn/'),
    _CctvLiveChannel('xiamen', '厦门卫视', '地方卫视', officialUrl: 'https://www.xmtv.cn/'),
  ];

  @override
  MediaSource get source => MediaSource(
        id: sourceId,
        name: 'CCTV 官方直播',
        kind: MediaSourceKind.officialWeb,
        entryUrl: entryUri.toString(),
        enabled: true,
        authorization: SourceAuthorization.officialEntryOnly,
        capabilities: const {
          SourceCapability.browse,
          SourceCapability.liveCatalog,
          SourceCapability.search,
          SourceCapability.episodes,
          SourceCapability.nativePublicPlayback,
          SourceCapability.officialFallback,
          SourceCapability.fullscreen,
        },
      );

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) async {
    if (query.category != MediaCategory.live) {
      return MediaCatalogPage(items: const [], page: query.page, total: 0);
    }
    final start = (query.page - 1) * query.pageSize;
    final end = (start + query.pageSize).clamp(0, _channels.length).toInt();
    final page = start >= _channels.length
        ? const <_CctvLiveChannel>[]
        : _channels.sublist(start, end);
    return MediaCatalogPage(
      items: page.map(_item).toList(growable: false),
      page: query.page,
      total: _channels.length,
    );
  }

  @override
  Future<List<MediaSearchHit>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    return _channels
        .where((channel) =>
            channel.name.toLowerCase().contains(normalized) ||
            channel.category.toLowerCase().contains(normalized))
        .map((channel) => MediaSearchHit(
              item: _item(channel),
              query: query,
              matchedField: 'title',
              relevance: 1,
            ))
        .toList(growable: false);
  }

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) async {
    _assertSource(item.sourceId);
    final channel = _channel(item.sourceItemId);
    final pageUri = _pageUri(channel);
    return [
      MediaEpisode(
        sourceId: sourceId,
        sourceEpisodeId: channel.id,
        title: channel.name,
        officialPageUri: pageUri,
        posterUri: item.posterUri,
      ),
    ];
  }

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) async {
    _assertSource(episode.sourceId);
    final channel = _channel(episode.sourceEpisodeId);
    final pageUri = _pageUri(channel);
    final streamUri = _nativeStreamUri(channel);
    return PlaybackDescriptor(
      sourceId: sourceId,
      sourceEpisodeId: channel.id,
      title: channel.name,
      officialPageUri: pageUri,
      nativeStreamUri: streamUri,
      posterUri: episode.posterUri,
      httpHeaders: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Referer': 'https://tv.cctv.com/',
      },
    );
  }

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(
    MediaEpisode episode,
  ) async {
    _assertSource(episode.sourceId);
    final channel = _channel(episode.sourceEpisodeId);
    final pageUri = _pageUri(channel);
    return PlaybackDescriptor(
      sourceId: sourceId,
      sourceEpisodeId: channel.id,
      title: channel.name,
      officialPageUri: pageUri,
      posterUri: episode.posterUri,
    );
  }

  Uri? _nativeStreamUri(_CctvLiveChannel channel) {
    final slug = channel.pageSlug ?? channel.id;
    return Uri.tryParse('https://play-live.cctv.com/live/$slug/index.m3u8') ??
        Uri.tryParse('http://ivi.bupt.edu.cn/hls/${channel.id}hd.m3u8');
  }

  MediaItem _item(_CctvLiveChannel channel) {
    final uri = _pageUri(channel);
    return MediaItem(
      sourceId: sourceId,
      sourceItemId: channel.id,
      title: channel.name,
      category: MediaCategory.live,
      officialDetailUri: uri,
      defaultEpisodePageUri: uri,
      sourceCategoryLabel: channel.category,
      brief: '${channel.category} · ${channel.name}',
      posterUri: CctvChannelLogoResolver.resolve(channel.name) ??
          CctvChannelLogoResolver.resolve(channel.id),
    );
  }

  _CctvLiveChannel _channel(String id) => _channels.firstWhere(
        (channel) => channel.id == id,
        orElse: () => throw StateError('未找到直播频道：$id'),
      );

  Uri _pageUri(_CctvLiveChannel channel) {
    if (channel.officialUrl != null) {
      return Uri.parse(channel.officialUrl!);
    }
    final slug = channel.pageSlug ?? channel.id;
    return Uri.parse('https://tv.cctv.com/live/$slug/index.shtml');
  }

  void _assertSource(String actualSourceId) {
    if (actualSourceId != sourceId) {
      throw StateError('来源标识不匹配：期望 $sourceId，实际 $actualSourceId');
    }
  }
}

class _CctvLiveChannel {
  const _CctvLiveChannel(
    this.id,
    this.name,
    this.category, {
    this.pageSlug,
    this.officialUrl,
  });

  final String id;
  final String name;
  final String category;
  final String? pageSlug;
  final String? officialUrl;
}
