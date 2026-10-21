import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Supported application language definitions across major global regions.
///
/// **What**: Maps language presets to standard Flutter [Locale] and assets/i18n JSON identifiers.
///
/// **Why**: Media aggregation clients used across international regions or TV setups
/// require dynamic, reactive language switching across Chinese, Japanese, Korean, English,
/// French, German, Spanish, and Russian.
enum AppLanguage {
  zhCN('简体中文', Locale('zh', 'CN'), 'zh_CN'),
  zhTW('繁體中文', Locale('zh', 'TW'), 'zh_TW'),
  enUS('English', Locale('en', 'US'), 'en_US'),
  jaJP('日本語', Locale('ja', 'JP'), 'ja_JP'),
  koKR('한국어', Locale('ko', 'KR'), 'ko_KR'),
  frFR('Français', Locale('fr', 'FR'), 'fr_FR'),
  deDE('Deutsch', Locale('de', 'DE'), 'de_DE'),
  esES('Español', Locale('es', 'ES'), 'es_ES'),
  ruRU('Русский', Locale('ru', 'RU'), 'ru_RU');

  const AppLanguage(this.label, this.locale, this.code);
  final String label;
  final Locale locale;
  final String code;
}

/// JSON-backed asynchronous and synchronous internationalization service.
class I18nService {
  I18nService._();
  static final I18nService instance = I18nService._();

  final Map<String, Map<String, String>> _cache =
      <String, Map<String, String>>{};

  /// Preloads JSON translation files from asset bundles into high-speed memory cache.
  Future<void> init() async {
    for (final lang in AppLanguage.values) {
      await loadLanguage(lang.code);
    }
  }

  /// Loads an individual language JSON file from `assets/i18n/{code}.json`.
  Future<void> loadLanguage(String code) async {
    try {
      final jsonString = await rootBundle.loadString('assets/i18n/$code.json');
      final Map<String, dynamic> decoded =
          json.decode(jsonString) as Map<String, dynamic>;
      _cache[code] =
          decoded.map((k, v) => MapEntry<String, String>(k, v.toString()));
    } catch (_) {
      // Fallback handled gracefully
    }
  }

  /// Directly sets dictionary for testing and offline isolation environments.
  void setTranslations(String code, Map<String, String> translations) {
    _cache[code] = translations;
  }

  /// Looks up localized string by key and language code with fallback cascading.
  String get(String key, {String langCode = 'zh_CN'}) {
    final map = _cache[langCode] ?? _cache['zh_CN'];
    if (map != null && map.containsKey(key)) {
      return map[key]!;
    }
    final fallbackMap = _cache['zh_CN'] ?? _builtinFallback['zh_CN'];
    if (fallbackMap != null && fallbackMap.containsKey(key)) {
      return fallbackMap[key]!;
    }
    return _builtinFallback['zh_CN']?[key] ?? key;
  }

  static const Map<String, Map<String, String>> _builtinFallback =
      <String, Map<String, String>>{
    'zh_CN': <String, String>{
      'download_unsupported_hls_layout': '暂不支持此视频格式的离线缓存，请在线播放或更换线路',
      'nav_home': '首页推荐',
      'nav_live': '电视直播',
      'nav_search': '聚合搜索',
      'nav_settings': '系统设置',
      'home_top_pick': '今日主推',
      'home_official_4k': '央视官方 4K 原画',
      'home_play_now': '立即播放',
      'home_detail': '节目详情',
      'home_switch_site': '当前数据源站点',
      'home_cctv_animation': '🔥 央视官方片库 · 少儿热播',
      'home_cctv_drama': '✨ 经典剧场与全频道点播',
      'home_hot_recommend': '🔥 热门影视推荐',
      'home_tvbox_site': 'TVBox 站点',
      'live_title': '电视直播中心',
      'live_epg_title': '📺 节目单 (EPG)',
      'live_fullscreen': '全屏播放',
      'live_current_program': '当前节目',
      'live_broadcasting': '直播中',
      'live_next_program': '后续预告',
      'live_cat_cctv': '央视频道',
      'live_cat_satellite': '地方卫视',
      'live_cat_4k': '4K/8K 专区',
      'live_cat_sports': '体育赛事',
      'search_hint': '输入片名首字母拼音或名称 (如 QYN 或 庆余年)',
      'search_hot_keywords': '🔥 热门搜索',
      'search_searching': '正在并发聚合检索多站源...',
      'search_no_results': '未找到相关影视内容',
      'search_sources_count': '个播放源',
      'detail_source_lines': '播放源与线路',
      'detail_no_overview': '暂无简介',
      'detail_episodes': '选集列表',
      'player_buffering': '正在缓冲媒体流...',
      'player_switch_source': '换源',
      'player_episodes': '选集',
      'player_danmaku': '弹幕',
      'player_danmaku_on': '弹幕已开启',
      'player_danmaku_off': '弹幕已隐藏',
      'player_audio_delay': '音轨延迟',
      'player_sub_delay': '字幕延迟',
      'player_aspect_ratio': '画面比例',
      'player_speed': '倍速',
      'player_retry': '重试播放',
      'player_back': '返回上一页',
      'player_failover_toast': '⚡ 已自动熔断切换至',
      'settings_title': '⚙️ 设置中心',
      'settings_section_playback': '播放内核与解码策略',
      'settings_hardware_decoding': '硬件解码加速 (GPU)',
      'settings_hardware_decoding_sub': '默认启用，若遇芯片异常将自动平滑降级至软解',
      'settings_ipv6_preferred': 'IPv6 双栈网络优先',
      'settings_ipv6_preferred_sub': '启动时探测 IPv6，自动提升超高清 4K 直播线路优先级',
      'settings_auto_failover': '3 秒故障自动熔断换源',
      'settings_auto_failover_sub': '直播或点播卡顿 >3000ms 或遇死链时，无感切换至健康线路',
      'settings_section_appearance': '界面个性化与多语言',
      'settings_theme': '界面主题风格',
      'settings_language': '显示语言',
      'settings_section_sources': '媒体源与 TVBox 订阅配置',
      'settings_tvbox_config': 'TVBox 接口仓管理',
      'settings_iptv_config': 'IPTV 直播源管理',
      'settings_webdav_config': 'WebDAV 多端同步',
      'settings_remote_portal': '手机局域网远程配置门户',
      'settings_remote_portal_sub': '同 Wi-Fi 手机扫码或浏览器访问：',
      'settings_remote_portal_desc':
          '已开启本地回环代理与局域网 Web 服务\n支持手机一键推源、配置 NAS 账号或直投视频',
    },
  };
}

/// Static helper facade for localized string resolution.
class AppStrings {
  static String tr(String key, {String langCode = 'zh_CN'}) {
    return I18nService.instance.get(key, langCode: langCode);
  }
}

/// Extension on [BuildContext] for ergonomic i18n access across widgets.
extension AppStringsContext on BuildContext {
  String tr(String key) {
    final locale = Localizations.maybeLocaleOf(this);
    final langKey = locale != null
        ? '${locale.languageCode}_${locale.countryCode ?? "CN"}'
        : 'zh_CN';
    return AppStrings.tr(key, langCode: langKey);
  }
}
