import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { system, light, dark, highContrast }

/// 运行时设置，所有值都可安全持久化；不保存账号、播放 URL 或来源凭据。
class AppSettingsController extends ChangeNotifier {
  AppSettingsController({
    required Locale fallbackLocale,
    SharedPreferencesAsync? preferences,
  })  : _locale = fallbackLocale,
        _preferences = preferences;

  static const _themeKey = 'settings.theme.v1';
  static const _localeKey = 'settings.locale.v1';
  final SharedPreferencesAsync? _preferences;
  AppThemePreference _theme = AppThemePreference.system;
  Locale _locale;

  AppThemePreference get theme => _theme;
  Locale get locale => _locale;
  ThemeMode get themeMode => switch (_theme) {
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  bool get highContrast => _theme == AppThemePreference.highContrast;

  Future<void> initialize() async {
    try {
      final preferences = _preferences ?? SharedPreferencesAsync();
      final storedTheme = await preferences.getString(_themeKey);
      final storedLocale = await preferences.getString(_localeKey);
      _theme = AppThemePreference.values
              .where((value) => value.name == storedTheme)
              .firstOrNull ??
          _theme;
      if (storedLocale != null) _locale = localeFromTag(storedLocale);
      notifyListeners();
    } catch (_) {
      // 首次启动或平台存储不可用时使用开发配置的默认值。
    }
  }

  Future<void> setTheme(AppThemePreference preference) async {
    _theme = preference;
    notifyListeners();
    try {
      await (_preferences ?? SharedPreferencesAsync()).setString(
        _themeKey,
        preference.name,
      );
    } catch (_) {}
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
    try {
      await (_preferences ?? SharedPreferencesAsync()).setString(
        _localeKey,
        locale.toLanguageTag(),
      );
    } catch (_) {}
  }
}

Locale localeFromTag(String tag) {
  final parts = tag.split(RegExp('[-_]'));
  return Locale(parts.first, parts.length > 1 ? parts[1] : null);
}
