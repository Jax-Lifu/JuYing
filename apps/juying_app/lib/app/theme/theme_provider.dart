import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juying/app/theme/app_theme_colors.dart';

/// Global state provider managing active visual theme preset.
///
/// **What**: Persists and broadcasts theme updates across the widget tree.
///
/// **Why**: Users on large TV screens and mobile OLED devices need instant real-time theme switching.
class ThemeNotifier extends StateNotifier<AppThemePreset> {
  ThemeNotifier() : super(AppThemePreset.cinemaDark);

  void setTheme(AppThemePreset preset) {
    state = preset;
  }
}

final StateNotifierProvider<ThemeNotifier, AppThemePreset> themeProvider =
    StateNotifierProvider<ThemeNotifier, AppThemePreset>((ref) {
  return ThemeNotifier();
});

/// Global provider managing Low Performance Mode toggle (APP-13, R15, ADR-010).
///
/// **What**: Toggles solid-color translucent fallbacks in place of expensive real-time
/// GPU BackdropFilter blurs on low-end Android TV hardware.
final StateProvider<bool> lowPerformanceModeProvider =
    StateProvider<bool>((ref) => false);
