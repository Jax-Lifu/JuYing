import 'package:flutter/material.dart';

import 'package:juying/app/theme/app_theme_colors.dart';

/// Provides unified ThemeData configurations across all supported platforms.
///
/// **What**: Assembles Material 3 visual schemes, typography hierarchies, card shapes,
/// and custom ThemeExtensions for dark-mode-first TV and desktop environments.
///
/// **Why**: Television displays and desktop monitors require darker default canvases
/// and crisp font weights (Medium/SemiBold) to avoid edge bleeding and eye fatigue.
abstract class AppTheme {
  /// Builds standard dark theme using the specified [colors] token set.
  static ThemeData buildTheme(AppThemeColors colors) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: colors.backgroundDeep,
      canvasColor: colors.backgroundDeep,
      colorScheme: ColorScheme.dark(
        surface: colors.surfaceCard,
        primary: colors.brandPrimary,
        secondary: colors.brandAccent,
        error: colors.statusError,
      ),
      extensions: <ThemeExtension<dynamic>>[
        colors,
      ],
      cardTheme: CardThemeData(
        color: colors.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.backgroundDeep,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: colors.textPrimary,
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: colors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: colors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: colors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
        bodyMedium: TextStyle(
          color: colors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.normal,
        ),
        labelSmall: TextStyle(
          color: colors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Convenience extension on [BuildContext] to access [AppThemeColors] directly.
extension AppThemeContext on BuildContext {
  /// Resolves active [AppThemeColors] from the current widget tree context.
  AppThemeColors get colors =>
      Theme.of(this).extension<AppThemeColors>() ?? AppThemeColors.cinemaDark;
}
