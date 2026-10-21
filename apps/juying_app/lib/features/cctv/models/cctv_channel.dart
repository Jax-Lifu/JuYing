import 'package:flutter/foundation.dart';

/// Represents an official CCTV broadcast live stream channel.
@immutable
class CctvChannel {
  const CctvChannel({
    required this.id,
    required this.name,
    required this.number,
    required this.logoUrl,
    required this.streamGuid,
    this.resolution = '1080P 50FPS',
    this.is4K = false,
  });

  final String id;
  final String name;
  final String number;
  final String logoUrl;
  final String streamGuid;
  final String resolution;
  final bool is4K;

  /// CCTV 直播官网按历史频道别名组织页面，不能直接由展示编号拼接。
  String get officialPageUrl {
    final pageSlug = switch (id) {
      'cctv9' => 'cctvjilu',
      'cctv14' => 'cctvchild',
      _ => id,
    };
    return 'https://tv.cctv.com/live/$pageSlug/index.shtml';
  }

  /// Preset official CCTV live broadcast channel directory.
  static const List<CctvChannel> officialChannels = <CctvChannel>[
    CctvChannel(
      id: 'cctv1',
      name: 'CCTV-1 综合',
      number: '01',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv1/cctv1.png',
      streamGuid: 'cctv1',
      resolution: '4K/1080P',
    ),
    CctvChannel(
      id: 'cctv4k',
      name: 'CCTV-4K 超高清',
      number: '4K',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv4k/cctv4k.png',
      streamGuid: 'cctv4k',
      resolution: '4K HDR 50FPS',
      is4K: true,
    ),
    CctvChannel(
      id: 'cctv2',
      name: 'CCTV-2 财经',
      number: '02',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv2/cctv2.png',
      streamGuid: 'cctv2',
    ),
    CctvChannel(
      id: 'cctv3',
      name: 'CCTV-3 综艺',
      number: '03',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv3/cctv3.png',
      streamGuid: 'cctv3',
    ),
    CctvChannel(
      id: 'cctv4',
      name: 'CCTV-4 中文国际',
      number: '04',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv4/cctv4.png',
      streamGuid: 'cctv4',
    ),
    CctvChannel(
      id: 'cctv5',
      name: 'CCTV-5 体育',
      number: '05',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv5/cctv5.png',
      streamGuid: 'cctv5',
      resolution: '1080P 50FPS',
    ),
    CctvChannel(
      id: 'cctv5plus',
      name: 'CCTV-5+ 体育赛事',
      number: '5+',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv5plus/cctv5plus.png',
      streamGuid: 'cctv5plus',
      resolution: '1080P 50FPS',
    ),
    CctvChannel(
      id: 'cctv6',
      name: 'CCTV-6 电影',
      number: '06',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv6/cctv6.png',
      streamGuid: 'cctv6',
    ),
    CctvChannel(
      id: 'cctv7',
      name: 'CCTV-7 国防军事',
      number: '07',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv7/cctv7.png',
      streamGuid: 'cctv7',
    ),
    CctvChannel(
      id: 'cctv8',
      name: 'CCTV-8 电视剧',
      number: '08',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv8/cctv8.png',
      streamGuid: 'cctv8',
    ),
    CctvChannel(
      id: 'cctv9',
      name: 'CCTV-9 纪录',
      number: '09',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv9/cctv9.png',
      streamGuid: 'cctv9',
      resolution: '4K/1080P',
    ),
    CctvChannel(
      id: 'cctv10',
      name: 'CCTV-10 科教',
      number: '10',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv10/cctv10.png',
      streamGuid: 'cctv10',
    ),
    CctvChannel(
      id: 'cctv11',
      name: 'CCTV-11 戏曲',
      number: '11',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv11/cctv11.png',
      streamGuid: 'cctv11',
    ),
    CctvChannel(
      id: 'cctv12',
      name: 'CCTV-12 社会与法',
      number: '12',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv12/cctv12.png',
      streamGuid: 'cctv12',
    ),
    CctvChannel(
      id: 'cctv13',
      name: 'CCTV-13 新闻',
      number: '13',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv13/cctv13.png',
      streamGuid: 'cctv13',
    ),
    CctvChannel(
      id: 'cctv14',
      name: 'CCTV-14 少儿',
      number: '14',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv14/cctv14.png',
      streamGuid: 'cctv14',
    ),
    CctvChannel(
      id: 'cctv15',
      name: 'CCTV-15 音乐',
      number: '15',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv15/cctv15.png',
      streamGuid: 'cctv15',
    ),
    CctvChannel(
      id: 'cctv16',
      name: 'CCTV-16 奥林匹克',
      number: '16',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv16/cctv16.png',
      streamGuid: 'cctv16',
      resolution: '4K/1080P 50FPS',
      is4K: true,
    ),
    CctvChannel(
      id: 'cctv17',
      name: 'CCTV-17 农业农村',
      number: '17',
      logoUrl: 'https://p1.img.cctvpic.com/live/cctv17/cctv17.png',
      streamGuid: 'cctv17',
    ),
  ];
}
