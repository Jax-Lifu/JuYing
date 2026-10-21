import 'package:flutter/foundation.dart';

/// Defines the top-level catalog categories matching https://tv.cctv.com/yxg/
enum CctvTopCategory {
  movie(id: 'dy', name: '电影', fc: '电影'),
  drama(id: 'dsj', name: '电视剧', fc: '电视剧'),
  animation(id: 'dhp', name: '动画片', fc: '动画片'),
  documentary(id: 'jlp', name: '纪录片', fc: '纪录片'),
  special(id: 'tbjm', name: '特别节目', fc: '特别节目');

  const CctvTopCategory({
    required this.id,
    required this.name,
    required this.fc,
  });

  final String id;
  final String name;
  final String fc;
}

/// View presentation mode for CCTV YXG archive.
enum CctvViewMode {
  grid,
  list,
}

/// Multi-dimensional filter state matching CCTV Official Archive portal (`tv.cctv.com/yxg`).
@immutable
class CctvFilterState {
  const CctvFilterState({
    this.topCategory = CctvTopCategory.drama,
    this.genre = '',
    this.area = '',
    this.year = '',
    this.letter = '',
    this.channelId = '',
    this.tag = '',
    this.viewMode = CctvViewMode.grid,
  });

  final CctvTopCategory topCategory;
  final String genre; // sc: e.g. 古装, 武侠, 亲子, 人文历史
  final String area; // area: e.g. 内地（大陆）, 港澳台, 欧美
  final String year; // year: e.g. 2026, 2024, 2020
  final String letter; // letter: e.g. A, B, C...
  final String channelId; // channelid for documentary/special
  final String tag; // special holiday tag: 春节, 中秋, 国庆
  final CctvViewMode viewMode;

  CctvFilterState copyWith({
    CctvTopCategory? topCategory,
    String? genre,
    String? area,
    String? year,
    String? letter,
    String? channelId,
    String? tag,
    CctvViewMode? viewMode,
  }) {
    return CctvFilterState(
      topCategory: topCategory ?? this.topCategory,
      genre: genre ?? this.genre,
      area: area ?? this.area,
      year: year ?? this.year,
      letter: letter ?? this.letter,
      channelId: channelId ?? this.channelId,
      tag: tag ?? this.tag,
      viewMode: viewMode ?? this.viewMode,
    );
  }

  /// Preset filter options for each dimension
  static const List<String> dramaGenres = <String>[
    '全部',
    '谍战',
    '悬疑',
    '刑侦',
    '历史',
    '古装',
    '武侠',
    '军旅',
    '战争',
    '喜剧',
    '青春',
    '言情',
    '偶像',
    '家庭',
    '年代',
    '革命',
    '农村',
    '都市',
    '其他',
  ];

  /// 央视影音电影片库当前使用的一级类型维度。
  ///
  /// 该枚举独立于电视剧类型，避免把同名影片错误聚合进连续剧候选线路。
  static const List<String> movieGenres = <String>[
    '全部',
    '偶像',
    '古装',
    '喜剧',
    '农村',
    '军旅',
    '惊悚',
    '爱情',
    '文艺',
    '战争',
    '历史',
    '谍战',
    '传记',
    '军事',
    '生活',
    '现代',
    '其他',
  ];

  static const List<String> animationGenres = <String>[
    '全部',
    '亲子',
    '搞笑',
    '冒险',
    '动作',
    '宠物',
    '体育',
    '益智',
    '历史',
    '教育',
    '校园',
    '言情',
    '武侠',
    '经典',
    '未来',
    '古代',
    '神话',
    '真人',
    '励志',
    '热血',
    '奇幻',
    '童话',
    '剧情',
    '夺宝',
    '其他',
  ];

  static const List<String> documentaryGenres = <String>[
    '全部',
    '人文历史',
    '人物',
    '军事',
    '探索',
    '社会',
    '自然',
    '时政',
    '经济',
    '科技',
  ];

  static const List<String> specialGenres = <String>[
    '全部',
    '新闻',
    '经济',
    '综艺',
    '体育',
    '军事',
    '影视',
    '科教',
    '戏曲',
    '青少',
    '音乐',
    '社会',
    '文化',
    '公益',
    '其他',
  ];

  static const List<String> areas = <String>[
    '全部',
    '内地（大陆）',
    '港澳台',
    '欧美',
    '其他',
  ];

  static const List<String> years = <String>[
    '全部',
    '2026',
    '2025',
    '2024',
    '2023',
    '2022',
    '2021',
    '2020',
    '2019',
    '2018',
    '2017',
    '2016',
    '2015',
    '2014',
    '2013',
    '2012',
    '2011',
    '2010',
    '2009',
    '2008',
    '2007',
    '2006',
    '2005',
    '2004',
    '2003',
    '2002',
    '2001',
    '2000',
    '1999',
    '1998',
    '1997',
  ];

  static const List<String> letters = <String>[
    '全部',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  static const List<Map<String, String>> channels = <Map<String, String>>[
    <String, String>{'name': '全部', 'id': ''},
    <String, String>{'name': 'CCTV-1 综合', 'id': 'CCTV-1综合,CCTV-1高清,CCTV-1综合高清'},
    <String, String>{'name': 'CCTV-2 财经', 'id': 'CCTV-2财经,CCTV-2高清,CCTV-2财经高清'},
    <String, String>{'name': 'CCTV-3 综艺', 'id': 'CCTV-3综艺,CCTV-3高清,CCTV-3综艺高清'},
    <String, String>{
      'name': 'CCTV-4 中文国际',
      'id': 'CCTV-4中文国际,CCTV-4高清,CCTV-4中文国际(亚)高清'
    },
    <String, String>{'name': 'CCTV-5 体育', 'id': 'CCTV-5体育,CCTV-5高清,CCTV-5体育高清'},
    <String, String>{'name': 'CCTV-6 电影', 'id': 'CCTV-6电影,CCTV-6高清,CCTV-6电影高清'},
    <String, String>{
      'name': 'CCTV-7 国防军事',
      'id': 'CCTV-7军事农业,CCTV-7高清,CCTV-7国防军事高清'
    },
    <String, String>{
      'name': 'CCTV-8 电视剧',
      'id': 'CCTV-8电视剧,CCTV-8高清,CCTV-8电视剧高清'
    },
    <String, String>{'name': 'CCTV-9 纪录', 'id': 'CCTV-9纪录,CCTV-9高清,CCTV-9纪录高清'},
    <String, String>{
      'name': 'CCTV-10 科教',
      'id': 'CCTV-10科教,CCTV-10高清,CCTV-10科教高清'
    },
    <String, String>{
      'name': 'CCTV-11 戏曲',
      'id': 'CCTV-11戏曲,CCTV-11高清,CCTV-11戏曲高清'
    },
    <String, String>{
      'name': 'CCTV-12 社会与法',
      'id': 'CCTV-12社会与法,CCTV-12高清,CCTV-12社会与法高清'
    },
    <String, String>{
      'name': 'CCTV-13 新闻',
      'id': 'CCTV-13新闻,CCTV-13高清,CCTV-13新闻高清'
    },
    <String, String>{
      'name': 'CCTV-14 少儿',
      'id': 'CCTV-14少儿,CCTV-14高清,CCTV-14少儿高清'
    },
    <String, String>{
      'name': 'CCTV-15 音乐',
      'id': 'CCTV-15音乐,CCTV-15高清,CCTV-15音乐高清'
    },
    <String, String>{'name': 'CCTV-17 农业农村', 'id': 'CCTV-17农业农村高清'},
  ];

  static const List<String> specialTags = <String>[
    '全部',
    '春节',
    '元宵',
    '清明',
    '劳动节',
    '端午',
    '中秋',
    '国庆',
    '元旦',
    '跨年',
    '315',
    '六一',
    '教师节',
    '七夕',
    '重阳',
  ];
}
