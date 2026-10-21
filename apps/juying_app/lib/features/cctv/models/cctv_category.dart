import 'package:flutter/foundation.dart';

/// Represents a distinct content category within the official CCTV portal.
@immutable
class CctvCategory {
  const CctvCategory({
    required this.id,
    required this.name,
    required this.firstCategory,
    this.channelId = '',
    this.iconName,
  });

  /// Unique internal category identifier.
  final String id;

  /// Official CCTV API channel identifier (e.g. `CHAL1460955899450127` or empty for all channels).
  final String channelId;

  /// Human-readable category label (e.g. `少儿动画`).
  final String name;

  /// CCTV REST query filter value (e.g. `动画片`, `电视剧`, `纪录片`, `综艺`, `特别节目`, `科教`, `戏曲`).
  final String firstCategory;

  /// Icon identifier for category tabs.
  final String? iconName;

  /// Preset flagship categories supported by CCTV official archive.
  static const List<CctvCategory> presetCategories = <CctvCategory>[
    CctvCategory(
      id: 'cctv_movie',
      name: '电影',
      firstCategory: '电影',
      iconName: 'movie',
    ),
    CctvCategory(
      id: 'cctv_animation',
      name: '少儿动画',
      firstCategory: '动画片',
      iconName: 'child_care',
    ),
    CctvCategory(
      id: 'cctv_drama',
      name: '经典剧场',
      firstCategory: '电视剧',
      iconName: 'live_tv',
    ),
    CctvCategory(
      id: 'cctv_documentary',
      name: '央视纪录片',
      firstCategory: '纪录片',
      iconName: 'menu_book',
    ),
    CctvCategory(
      id: 'cctv_variety',
      name: '经典综艺',
      firstCategory: '综艺',
      iconName: 'celebration',
    ),
    CctvCategory(
      id: 'cctv_special',
      name: '特别节目',
      firstCategory: '特别节目',
      iconName: 'star',
    ),
    CctvCategory(
      id: 'cctv_science',
      name: '科教博览',
      firstCategory: '科教',
      iconName: 'science',
    ),
    CctvCategory(
      id: 'cctv_opera',
      name: '戏曲天地',
      firstCategory: '戏曲',
      iconName: 'theater_comedy',
    ),
  ];
}
