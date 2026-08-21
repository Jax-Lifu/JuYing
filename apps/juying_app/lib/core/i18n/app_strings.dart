import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('zh', 'CN'), Locale('en')];

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings(Locale('zh', 'CN'));

  bool get _isEnglish => locale.languageCode == 'en';

  String get appName => _isEnglish ? 'juying' : '聚映';
  String get home => _isEnglish ? 'Home' : '首页';
  String get search => _isEnglish ? 'Search' : '搜索';
  String get kids => _isEnglish ? 'Kids' : '儿童';
  String get library => _isEnglish ? 'Library' : '媒体库';
  String get settings => _isEnglish ? 'Settings' : '设置';
  String get frameworkPreview =>
      _isEnglish ? 'Framework preview · no media connected' : '框架预览 · 暂未接入媒体';
  String get appearanceAndLanguage =>
      _isEnglish ? 'Appearance & language' : '外观与语言';
  String get contentAndPlayback => _isEnglish ? 'Content & playback' : '内容与播放';
  String get familyAndDevice => _isEnglish ? 'Family & device' : '家庭与设备';
  String get theme => _isEnglish ? 'Theme' : '主题';
  String get systemTheme => _isEnglish ? 'System default' : '跟随系统';
  String get lightTheme => _isEnglish ? 'Light' : '亮色';
  String get darkTheme => _isEnglish ? 'Dark' : '暗色';
  String get highContrastTheme => _isEnglish ? 'High contrast' : '高对比度';
  String get language => _isEnglish ? 'Language' : '语言';
  String get contentSources => _isEnglish ? 'Content sources' : '内容来源';
  String configuredSources(int count) =>
      _isEnglish ? '$count configured' : '$count 个已配置';
  String get sourceManagement => _isEnglish ? 'Manage sources' : '管理内容来源';
  String get sourceDisabled => _isEnglish ? 'Disabled' : '已停用';
  String get sourceEnabled => _isEnglish ? 'Enabled' : '已启用';
  String get externalConfigDiagnostics =>
      _isEnglish ? 'External config diagnostics' : '外部配置安全检测';
  String get externalConfigDiagnosticsHint => _isEnglish
      ? 'Reachability and static risk scan; never imported for playback'
      : '仅检测可达性和静态风险，不导入播放';
  String get playbackPreferences =>
      _isEnglish ? 'Playback preferences' : '播放偏好';
  String get playbackPreferencesHint => _isEnglish
      ? 'Quality, subtitles, audio and decoder policy'
      : '清晰度、字幕、音轨、解码策略';
  String get accessibility =>
      _isEnglish ? 'Subtitles & accessibility' : '字幕与无障碍';
  String get accessibilityHint => _isEnglish
      ? 'Text size, contrast, audio description and screen reader'
      : '字号、对比度、音频描述、读屏';
  String get familyMembers => _isEnglish ? 'Family members' : '家庭成员';
  String get familyMembersHint =>
      _isEnglish ? 'Separate adult and child profiles' : '成人与儿童独立档案';
  String get devicesAndSync => _isEnglish ? 'Devices & sync' : '设备与同步';
  String get devicesAndSyncHint =>
      _isEnglish ? 'Reserved for end-to-end sync' : '端到端同步能力预留';
  String get privacyAndCompliance =>
      _isEnglish ? 'Privacy & compliance' : '隐私与合规';
  String get privacyAndComplianceHint => _isEnglish
      ? 'Source authorization, data export and deletion'
      : '来源授权、数据导出与清除';
  String get clearLocalProfileData =>
      _isEnglish ? 'Clear this profile’s local data' : '清除此档案的本机数据';
  String get clearLocalProfileDataHint => _isEnglish
      ? 'History, favorites and playback preferences only'
      : '仅历史、收藏、播放偏好与儿童观看时长';
  String get clearProfileDataTitle =>
      _isEnglish ? 'Clear local profile data?' : '清除本机档案数据？';
  String get clearProfileDataBody => _isEnglish
      ? 'This removes only the current profile’s history, favorites and playback preferences from this device. It cannot be undone.'
      : '这将仅清除当前档案在本机的历史、收藏、播放偏好与儿童观看时长，且无法撤销。';
  String get cancel => _isEnglish ? 'Cancel' : '取消';
  String get clear => _isEnglish ? 'Clear' : '清除';
  String get profileDataCleared =>
      _isEnglish ? 'Local profile data cleared' : '已清除本机档案数据';
  String get clearProfileDataFailed => _isEnglish
      ? 'Could not clear profile data. Please try again.'
      : '无法清除档案数据，请重试。';
  String get playbackDiagnostics =>
      _isEnglish ? 'Playback diagnostics' : '播放诊断';
  String get playbackDiagnosticsHint => _isEnglish
      ? 'Recent redacted playback events on this device'
      : '此设备最近的脱敏播放事件';
  String get noPlaybackDiagnostics =>
      _isEnglish ? 'No playback events yet' : '暂无播放诊断事件';
  String get clearDiagnostics => _isEnglish ? 'Clear diagnostics' : '清空诊断';
  String get nativePlayback => _isEnglish ? 'Native' : '原生播放';
  String get officialPlayback => _isEnglish ? 'Official page' : '官网播放';
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales
      .any((item) => item.languageCode == locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture<AppStrings>(AppStrings(locale));

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
