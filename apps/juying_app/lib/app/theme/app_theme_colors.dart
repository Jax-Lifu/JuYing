import 'package:flutter/material.dart';

/// Supported visual theme presets for JuYing.
///
/// **Why**: Providing developer-beloved color themes (VS Code Dark+, One Dark Pro, Cinema Dark+,
/// OLED Pure Black, Cyberpunk, Midnight Blue, and System Adaptive) enables users on TV,
/// desktop monitors, and mobile OLED displays to customize their ideal visual experience.
enum AppThemePreset {
  system('跟随系统 (System Adaptive)', AppThemeColors.vscodeDark),
  vscodeDark('VS Code Dark+ (经典暗黑)', AppThemeColors.vscodeDark),
  oneDarkPro('One Dark Pro (Atom 风格)', AppThemeColors.oneDarkPro),
  cinemaDark('极光暗黑 (Cinema Dark+)', AppThemeColors.cinemaDark),
  oledBlack('极致纯黑 (OLED Pure Black)', AppThemeColors.oledBlack),
  cyberpunkNeon('赛博朋克 (Cyberpunk Neon)', AppThemeColors.cyberpunkNeon),
  midnightBlue('深海午夜 (Midnight Blue)', AppThemeColors.midnightBlue),
  cleanLight('明亮极简 (Clean Light)', AppThemeColors.cleanLight);

  const AppThemePreset(this.label, this.colors);
  final String label;
  final AppThemeColors colors;
}

@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.backgroundDeep,
    required this.surfaceCard,
    required this.surfaceElevation,
    required this.brandPrimary,
    required this.brandAccent,
    required this.focusBorder,
    required this.focusGlow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusError,
  });

  /// Deepest canvas background color.
  final Color backgroundDeep;

  /// Default surface background for media cards and list tiles.
  final Color surfaceCard;

  /// Elevated overlay color for dialogs, drawers, and floating toolbars.
  final Color surfaceElevation;

  /// Primary brand identity color used for active indicators and primary buttons.
  final Color brandPrimary;

  /// Accent highlight color used for badges, ratings, and VIP indicators.
  final Color brandAccent;

  /// High-visibility focus ring color for TV D-Pad remote navigation.
  final Color focusBorder;

  /// Subtle outer drop shadow / glow color for focused TV elements.
  final Color focusGlow;

  /// High-contrast primary foreground text color.
  final Color textPrimary;

  /// Medium-contrast secondary text color (genres, year, resolution badges).
  final Color textSecondary;

  /// Subdued tertiary text color for inactive tabs and subtle hints.
  final Color textTertiary;

  /// Status indicator for low latency streams and successful sync operations.
  final Color statusSuccess;

  /// Status indicator for degrading streams and fallback warnings.
  final Color statusWarning;

  /// Status indicator for broken routes, 404s, and circuit breaker trip events.
  final Color statusError;

  /// 1. VS Code Dark+ Theme (Classic developer dark palette).
  static const AppThemeColors vscodeDark = AppThemeColors(
    backgroundDeep: Color(0xFF1E1E1E),
    surfaceCard: Color(0xFF252526),
    surfaceElevation: Color(0xFF2D2D2D),
    brandPrimary: Color(0xFF007ACC),
    brandAccent: Color(0xFF4EC9B0),
    focusBorder: Color(0xFF007ACC),
    focusGlow: Color(0x80007ACC),
    textPrimary: Color(0xFFD4D4D4),
    textSecondary: Color(0xFF858585),
    textTertiary: Color(0xFF6A6A6A),
    statusSuccess: Color(0xFF4EC9B0),
    statusWarning: Color(0xFFDCDCAA),
    statusError: Color(0xFFF44747),
  );

  /// 2. One Dark Pro Theme (Iconic Atom / One Dark palette).
  static const AppThemeColors oneDarkPro = AppThemeColors(
    backgroundDeep: Color(0xFF282C34),
    surfaceCard: Color(0xFF21252B),
    surfaceElevation: Color(0xFF2F343F),
    brandPrimary: Color(0xFF61AFEF),
    brandAccent: Color(0xFF98C379),
    focusBorder: Color(0xFF61AFEF),
    focusGlow: Color(0x8061AFEF),
    textPrimary: Color(0xFFABB2BF),
    textSecondary: Color(0xFF5C6370),
    textTertiary: Color(0xFF4B5263),
    statusSuccess: Color(0xFF98C379),
    statusWarning: Color(0xFFE5C07B),
    statusError: Color(0xFFE06C75),
  );

  /// 3. Cinema Dark+ theme (Rich streaming UI).
  static const AppThemeColors cinemaDark = AppThemeColors(
    backgroundDeep: Color(0xFF0D1117),
    surfaceCard: Color(0xFF161B22),
    surfaceElevation: Color(0xFF21262D),
    brandPrimary: Color(0xFF238636),
    brandAccent: Color(0xFF58A6FF),
    focusBorder: Color(0xFF38EF7D),
    focusGlow: Color(0x6638EF7D),
    textPrimary: Color(0xFFF0F6FC),
    textSecondary: Color(0xFF8B949E),
    textTertiary: Color(0xFF6E7681),
    statusSuccess: Color(0xFF2EA043),
    statusWarning: Color(0xFFD29922),
    statusError: Color(0xFFF85149),
  );

  /// 4. Pure OLED Black theme for maximum contrast.
  static const AppThemeColors oledBlack = AppThemeColors(
    backgroundDeep: Color(0xFF000000),
    surfaceCard: Color(0xFF121212),
    surfaceElevation: Color(0xFF1E1E1E),
    brandPrimary: Color(0xFF1F6FEB),
    brandAccent: Color(0xFFFFD166),
    focusBorder: Color(0xFF58A6FF),
    focusGlow: Color(0x6658A6FF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFA0A0A0),
    textTertiary: Color(0xFF707070),
    statusSuccess: Color(0xFF238636),
    statusWarning: Color(0xFFF59E0B),
    statusError: Color(0xFFEF4444),
  );

  /// 5. Cyberpunk Neon theme.
  static const AppThemeColors cyberpunkNeon = AppThemeColors(
    backgroundDeep: Color(0xFF0E0B1F),
    surfaceCard: Color(0xFF1B1538),
    surfaceElevation: Color(0xFF2B2254),
    brandPrimary: Color(0xFFFF007F),
    brandAccent: Color(0xFF00F0FF),
    focusBorder: Color(0xFF00F0FF),
    focusGlow: Color(0x8000F0FF),
    textPrimary: Color(0xFFFBFBFF),
    textSecondary: Color(0xFFA9A0D0),
    textTertiary: Color(0xFF746B9D),
    statusSuccess: Color(0xFF00FF66),
    statusWarning: Color(0xFFFFD600),
    statusError: Color(0xFFFF3366),
  );

  /// 6. Midnight Blue theme.
  static const AppThemeColors midnightBlue = AppThemeColors(
    backgroundDeep: Color(0xFF0B132B),
    surfaceCard: Color(0xFF1C2541),
    surfaceElevation: Color(0xFF2E3A59),
    brandPrimary: Color(0xFF3A86FF),
    brandAccent: Color(0xFFFFBE0B),
    focusBorder: Color(0xFFFFBE0B),
    focusGlow: Color(0x66FFBE0B),
    textPrimary: Color(0xFFF0F4F8),
    textSecondary: Color(0xFF8D99AE),
    textTertiary: Color(0xFF5C677D),
    statusSuccess: Color(0xFF06D6A0),
    statusWarning: Color(0xFFFFB703),
    statusError: Color(0xFFEF233C),
  );

  /// 7. Clean Light theme (High-clarity daytime mode).
  static const AppThemeColors cleanLight = AppThemeColors(
    backgroundDeep: Color(0xFFF6F8FA),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceElevation: Color(0xFFEAECEF),
    brandPrimary: Color(0xFF0969DA),
    brandAccent: Color(0xFF1A7F37),
    focusBorder: Color(0xFF0969DA),
    focusGlow: Color(0x660969DA),
    textPrimary: Color(0xFF1F2328),
    textSecondary: Color(0xFF59636E),
    textTertiary: Color(0xFF8C959F),
    statusSuccess: Color(0xFF1A7F37),
    statusWarning: Color(0xFF9A6700),
    statusError: Color(0xFFCF222E),
  );

  @override
  AppThemeColors copyWith({
    Color? backgroundDeep,
    Color? surfaceCard,
    Color? surfaceElevation,
    Color? brandPrimary,
    Color? brandAccent,
    Color? focusBorder,
    Color? focusGlow,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? statusSuccess,
    Color? statusWarning,
    Color? statusError,
  }) {
    return AppThemeColors(
      backgroundDeep: backgroundDeep ?? this.backgroundDeep,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceElevation: surfaceElevation ?? this.surfaceElevation,
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandAccent: brandAccent ?? this.brandAccent,
      focusBorder: focusBorder ?? this.focusBorder,
      focusGlow: focusGlow ?? this.focusGlow,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusWarning: statusWarning ?? this.statusWarning,
      statusError: statusError ?? this.statusError,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      backgroundDeep: Color.lerp(backgroundDeep, other.backgroundDeep, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceElevation:
          Color.lerp(surfaceElevation, other.surfaceElevation, t)!,
      brandPrimary: Color.lerp(brandPrimary, other.brandPrimary, t)!,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!,
      focusBorder: Color.lerp(focusBorder, other.focusBorder, t)!,
      focusGlow: Color.lerp(focusGlow, other.focusGlow, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
    );
  }
}
