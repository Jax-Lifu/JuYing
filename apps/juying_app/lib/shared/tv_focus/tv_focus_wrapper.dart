import 'package:flutter/material.dart';
import 'package:juying_ui_kit/juying_ui_kit.dart';

/// Provides unified TV D-Pad focus visuals and key press handling (ADR-010 & ADR-016).
///
/// **What**: Backwards-compatible wrapper delegating to [TvFocusGlow] in `juying_ui_kit`.
///
/// **Why**: Centralizes Apple Cinema focus rings and 60fps low-performance mode in the UI kit
/// while preserving existing call sites across `apps/juying_app`.
class TvFocusWrapper extends StatelessWidget {
  const TvFocusWrapper({
    super.key,
    required this.child,
    this.onTap,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.showGlow = true,
    this.isLowPerformanceMode = false,
  });

  /// The child widget to be scaled and wrapped with focus styling.
  final Widget child;

  /// Callback triggered when D-Pad Center / Enter / Space or Click is confirmed.
  final VoidCallback? onTap;

  /// Optional external listener for focus state transitions.
  final ValueChanged<bool>? onFocusChange;

  /// Explicit FocusNode. If omitted, an internal FocusNode will be managed.
  final FocusNode? focusNode;

  /// Whether this widget should automatically claim focus on initial render.
  final bool autofocus;

  /// Shape radius for the focus ring and clip boundary.
  final BorderRadius borderRadius;

  /// Whether to render a restrained outer glow around the focused control.
  final bool showGlow;

  /// Whether running in low performance mode.
  final bool isLowPerformanceMode;

  @override
  Widget build(BuildContext context) {
    return TvFocusGlow(
      onTap: onTap,
      onFocusChange: onFocusChange,
      focusNode: focusNode,
      autofocus: autofocus,
      borderRadius: borderRadius,
      showGlow: showGlow,
      enableScale: false,
      isLowPerformanceMode: isLowPerformanceMode,
      child: child,
    );
  }
}
