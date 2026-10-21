import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juying/app/theme/app_theme_colors.dart';

void main() {
  group('Multi-Theme Preset Tests', () {
    test('provides 8 distinct theme presets with valid design tokens', () {
      expect(AppThemePreset.values.length, 8);

      // VS Code Dark+
      final vscode = AppThemeColors.vscodeDark;
      expect(vscode.backgroundDeep, const Color(0xFF1E1E1E));
      expect(vscode.brandPrimary, const Color(0xFF007ACC));

      // One Dark Pro
      final onedark = AppThemeColors.oneDarkPro;
      expect(onedark.backgroundDeep, const Color(0xFF282C34));
      expect(onedark.brandPrimary, const Color(0xFF61AFEF));

      // Cinema Dark+
      final cinema = AppThemeColors.cinemaDark;
      expect(cinema.backgroundDeep, const Color(0xFF0D1117));

      // OLED Pure Black
      final oled = AppThemeColors.oledBlack;
      expect(oled.backgroundDeep, const Color(0xFF000000));

      // Cyberpunk Neon
      final cyberpunk = AppThemeColors.cyberpunkNeon;
      expect(cyberpunk.backgroundDeep, const Color(0xFF0E0B1F));

      // Midnight Blue
      final midnight = AppThemeColors.midnightBlue;
      expect(midnight.backgroundDeep, const Color(0xFF0B132B));

      // Clean Light
      final light = AppThemeColors.cleanLight;
      expect(light.backgroundDeep, const Color(0xFFF6F8FA));
      expect(light.surfaceCard, const Color(0xFFFFFFFF));
    });

    test('supports smooth lerp transition between theme tokens', () {
      final t1 = AppThemeColors.vscodeDark;
      final t2 = AppThemeColors.oneDarkPro;

      final lerped = t1.lerp(t2, 0.5);
      expect(lerped.backgroundDeep, isNotNull);
    });
  });
}
