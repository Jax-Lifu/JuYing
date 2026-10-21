/// Apple-style Design System and TV Focus UI Kit for JuYing.
///
/// **What**: Provides Apple cinema-inspired design tokens, glassmorphism containers with
/// adaptive low-performance fallback, TV focus glow wrappers, and responsive layout breakpoints.
///
/// **Why**: Implements ADR-010, APP-13, and Section 5.11. Unifies visual language across
/// Windows, Android Mobile, and Android TV while safeguarding 60fps fluidity on low-end hardware.
library;

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

export 'src/tv_focus_glow.dart';

/// TV responsive screen layout breakpoints (Section 5.11 & APP-02).
enum ScreenFormFactor {
  mobile,
  tablet,
  desktop,
  tv,
}

/// Centralized Apple-inspired Cinema Design Tokens (ADR-010 & Section 5.11).
class AppleDesignTokens {
  const AppleDesignTokens._();

  // --- Palette: Cinema Dark ---
  static const Color backgroundDeep = Color(0xFF0A0C10);
  static const Color backgroundCanvas = Color(0xFF12161F);
  static const Color surfaceCard = Color(0xFF1C212D);
  static const Color surfaceCardGlass = Color(0x991C212D);
  static const Color surfaceSolidFallback = Color(0xF01C212D);

  static const Color textPrimary = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textTertiary = Color(0xFF484F58);

  static const Color brandPrimary = Color(0xFF0A84FF); // Apple Cinema Blue
  static const Color brandAccent = Color(0xFF5E5CE6); // Apple Indigo
  static const Color focusGlow = Color(0x660A84FF);

  static const Color statusSuccess = Color(0xFF30D158);
  static const Color statusWarning = Color(0xFFFFD60A);
  static const Color statusError = Color(0xFFFF453A);

  // --- Corner Radius Hierarchy ---
  static const double radiusSmall = 6.0;
  static const double radiusMedium = 10.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;

  static const BorderRadius borderSmall =
      BorderRadius.all(Radius.circular(radiusSmall));
  static const BorderRadius borderMedium =
      BorderRadius.all(Radius.circular(radiusMedium));
  static const BorderRadius borderLarge =
      BorderRadius.all(Radius.circular(radiusLarge));
  static const BorderRadius borderXLarge =
      BorderRadius.all(Radius.circular(radiusXLarge));

  // --- Blur Intensity Tokens ---
  static const double blurSubtle = 8.0;
  static const double blurMedium = 16.0;
  static const double blurProminent = 24.0;

  // --- Motion & Spring Curves ---
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationStandard = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 350);

  static const Curve curveSpring = Curves.easeOutCubic;
  static const Curve curveEnter = Curves.easeOutQuint;
}

/// Low-Performance Mode Configuration and Fallback Policy (APP-13 & R15).
///
/// **What**: Dynamically disables high-overhead GPU BackdropFilter blur and complex
/// continuous animations on low-spec Android TV boxes or user preference.
///
/// **Why**: Prevents frame dropping and UI thread blocking on weak Mali/PowerVR TV chipsets.
class LowPerformancePolicy {
  const LowPerformancePolicy({
    this.isLowPerformanceMode = false,
    this.reduceMotion = false,
  });

  final bool isLowPerformanceMode;
  final bool reduceMotion;

  /// Resolves effective blur radius based on performance policy.
  double resolveBlur(double requestedBlur) {
    if (isLowPerformanceMode) {
      return 0.0;
    }
    return requestedBlur;
  }

  /// Resolves surface color: uses solid semi-transparent background when blur is disabled.
  Color resolveSurface({
    Color normalGlass = AppleDesignTokens.surfaceCardGlass,
    Color fallbackSolid = AppleDesignTokens.surfaceSolidFallback,
  }) {
    if (isLowPerformanceMode) {
      return fallbackSolid;
    }
    return normalGlass;
  }

  /// Whether animations should execute in full or snap immediately.
  Duration resolveDuration(Duration requestedDuration) {
    if (reduceMotion || isLowPerformanceMode) {
      return Duration.zero;
    }
    return requestedDuration;
  }
}

/// Adaptive Apple-style Glass Container (ADR-010).
///
/// **What**: Renders translucent frosted glass with border highlights when performance allows;
/// seamlessly falls back to opaque high-contrast dark canvas under Low-Performance Mode.
class AppleGlassCard extends StatelessWidget {
  const AppleGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = AppleDesignTokens.borderMedium,
    this.blurRadius = AppleDesignTokens.blurMedium,
    this.isLowPerformanceMode = false,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blurRadius;
  final bool isLowPerformanceMode;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor =
        borderColor ?? AppleDesignTokens.focusGlow.withValues(alpha: 0.15);

    if (isLowPerformanceMode || blurRadius <= 0.0) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppleDesignTokens.surfaceSolidFallback,
          borderRadius: borderRadius,
          border: Border.all(color: effectiveBorderColor),
        ),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurRadius, sigmaY: blurRadius),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppleDesignTokens.surfaceCardGlass,
            borderRadius: borderRadius,
            border: Border.all(color: effectiveBorderColor),
          ),
          child: child,
        ),
      ),
    );
  }
}
