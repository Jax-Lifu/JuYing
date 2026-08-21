/// 解析直播频道（CCTV、各大卫视等）的官方高清图标/封面。
abstract final class CctvChannelLogoResolver {
  static const _baseCdn = 'https://live.fanmingming.com/tv';

  static Uri? resolve(String? nameOrId) {
    if (nameOrId == null) return null;
    final normalized = nameOrId.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    // CCTV 5+ / 5plus 特殊匹配
    if (normalized.contains('cctv5+') ||
        normalized.contains('cctv-5+') ||
        normalized.contains('cctv 5+') ||
        normalized.contains('5plus') ||
        normalized.contains('5+')) {
      return Uri.parse('$_baseCdn/CCTV5plus.png');
    }

    // CCTV 4K / 8K
    if (normalized.contains('cctv') && normalized.contains('4k')) {
      return Uri.parse('$_baseCdn/CCTV4K.png');
    }
    if (normalized.contains('cctv') && normalized.contains('8k')) {
      return Uri.parse('$_baseCdn/CCTV8K.png');
    }

    // CCTV-1 到 CCTV-17
    final cctvMatch = RegExp(r'cctv[-_\s]?(\d{1,2})').firstMatch(normalized);
    if (cctvMatch != null) {
      final num = int.tryParse(cctvMatch.group(1)!);
      if (num != null && num >= 1 && num <= 17) {
        return Uri.parse('$_baseCdn/CCTV$num.png');
      }
    }

    // 按别名匹配 CCTV
    if (normalized.contains('cctvchild') ||
        (normalized.contains('cctv') && normalized.contains('少儿'))) {
      return Uri.parse('$_baseCdn/CCTV14.png');
    }
    if (normalized.contains('cctvjilu') ||
        (normalized.contains('cctv') &&
            (normalized.contains('纪录') || normalized.contains('记录')))) {
      return Uri.parse('$_baseCdn/CCTV9.png');
    }
    if (normalized.contains('cctv') && normalized.contains('新闻')) {
      return Uri.parse('$_baseCdn/CCTV13.png');
    }
    if (normalized.contains('cctv') && normalized.contains('体育')) {
      return Uri.parse('$_baseCdn/CCTV5.png');
    }
    if (normalized.contains('cctv') && normalized.contains('电影')) {
      return Uri.parse('$_baseCdn/CCTV6.png');
    }
    if (normalized.contains('cctv') && normalized.contains('综艺')) {
      return Uri.parse('$_baseCdn/CCTV3.png');
    }
    if (normalized.contains('cctv') && normalized.contains('财经')) {
      return Uri.parse('$_baseCdn/CCTV2.png');
    }
    if (normalized.contains('cctv') && normalized.contains('国防军事')) {
      return Uri.parse('$_baseCdn/CCTV7.png');
    }
    if (normalized.contains('cctv') && normalized.contains('电视剧')) {
      return Uri.parse('$_baseCdn/CCTV8.png');
    }
    if (normalized.contains('cctv') && normalized.contains('科教')) {
      return Uri.parse('$_baseCdn/CCTV10.png');
    }
    if (normalized.contains('cctv') && normalized.contains('戏曲')) {
      return Uri.parse('$_baseCdn/CCTV11.png');
    }
    if (normalized.contains('cctv') && normalized.contains('社会与法')) {
      return Uri.parse('$_baseCdn/CCTV12.png');
    }
    if (normalized.contains('cctv') && normalized.contains('音乐')) {
      return Uri.parse('$_baseCdn/CCTV15.png');
    }
    if (normalized.contains('cctv') && normalized.contains('奥林匹克')) {
      return Uri.parse('$_baseCdn/CCTV16.png');
    }
    if (normalized.contains('cctv') && normalized.contains('农业农村')) {
      return Uri.parse('$_baseCdn/CCTV17.png');
    }
    if (normalized.contains('cctv') && normalized.contains('中文国际')) {
      return Uri.parse('$_baseCdn/CCTV4.png');
    }

    // CGTN
    if (normalized.contains('cgtn') &&
        (normalized.contains('doc') || normalized.contains('纪录'))) {
      return Uri.parse('$_baseCdn/CGTNDocumentary.png');
    }
    if (normalized.contains('cgtn')) {
      return Uri.parse('$_baseCdn/CGTN.png');
    }

    // 卫视频道
    const satellites = [
      '湖南卫视',
      '浙江卫视',
      '东方卫视',
      '江苏卫视',
      '北京卫视',
      '广东卫视',
      '深圳卫视',
      '安徽卫视',
      '山东卫视',
      '天津卫视',
      '四川卫视',
      '重庆卫视',
      '湖北卫视',
      '河南卫视',
      '江西卫视',
      '辽宁卫视',
      '河北卫视',
      '东南卫视',
      '贵州卫视',
      '云南卫视',
      '黑龙江卫视',
      '吉林卫视',
      '海南卫视',
      '内蒙古卫视',
      '新疆卫视',
      '西藏卫视',
      '青海卫视',
      '宁夏卫视',
      '广西卫视',
      '陕西卫视',
      '山西卫视',
    ];

    for (final satellite in satellites) {
      if (nameOrId.contains(satellite) ||
          nameOrId.contains(satellite.replaceAll('卫视', ''))) {
        return Uri.parse('$_baseCdn/${Uri.encodeComponent(satellite)}.png');
      }
    }

    return null;
  }
}
