import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:juying_ui_kit/juying_ui_kit.dart';

/// Provides Apple TV-inspired focus visuals and D-Pad key handling (ADR-010 & ADR-016).
///
/// **What**: Wraps any interactive card or button, providing automatic spatial focus
/// handling, Apple Cinema focus glow, progressive scaling, and IR remote debounce.
///
/// **Why**: On Android TV and keyboard-driven desktop setups, users rely entirely on
/// high-visibility spatial focus rings. Inexpensive IR remote controls often exhibit key bounce
/// (chatter), so a 60ms debounce barrier prevents accidental double triggers.
class TvFocusGlow extends StatefulWidget {
  const TvFocusGlow({
    super.key,
    required this.child,
    this.onTap,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = AppleDesignTokens.borderMedium,
    this.showGlow = true,
    this.scale = 1.04,
    this.enableScale = true,
    this.blurRadius = 6.0,
    this.spreadRadius = 0.0,
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

  /// Scaling factor when focused.
  final double scale;

  /// Whether to apply scale transform on focus. Defaults to true.
  final bool enableScale;

  /// Outer glow blur radius when focused.
  final double blurRadius;

  /// Outer glow spread radius when focused.
  final double spreadRadius;

  /// Whether running in low performance mode (disables continuous scale animation).
  final bool isLowPerformanceMode;

  @override
  State<TvFocusGlow> createState() => _TvFocusGlowState();
}

class _TvFocusGlowState extends State<TvFocusGlow> {
  late FocusNode _internalFocusNode;
  bool _isFocused = false;
  bool _isHovered = false;
  int _lastActionTimestamp = 0;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode();
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    }
    super.dispose();
  }

  /// Debounces action triggers by 60ms to eliminate IR remote key chatter.
  void _handleAction() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastActionTimestamp < 60) return;
    _lastActionTimestamp = now;
    widget.onTap?.call();
  }

  void _onFocusChanged(bool hasFocus) {
    if (_isFocused != hasFocus) {
      setState(() {
        _isFocused = hasFocus;
      });
      widget.onFocusChange?.call(hasFocus);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.gameButtonA) {
        _handleAction();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final effectiveScale = widget.isLowPerformanceMode
        ? 1.0
        : (isHighlighted ? widget.scale : 1.0);

    final container = AnimatedContainer(
      duration: widget.isLowPerformanceMode
          ? Duration.zero
          : AppleDesignTokens.durationFast,
      curve: AppleDesignTokens.curveSpring,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: isHighlighted
              ? AppleDesignTokens.brandPrimary
              : Colors.transparent,
          width: isHighlighted ? 2.5 : 0.0,
        ),
        boxShadow:
            (isHighlighted && widget.showGlow && !widget.isLowPerformanceMode)
                ? <BoxShadow>[
                    BoxShadow(
                      color: AppleDesignTokens.focusGlow,
                      blurRadius: widget.blurRadius,
                      spreadRadius: widget.spreadRadius,
                    ),
                  ]
                : null,
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: widget.child,
      ),
    );

    final content = (!widget.enableScale || widget.scale == 1.0)
        ? container
        : AnimatedScale(
            scale: effectiveScale,
            duration: widget.isLowPerformanceMode
                ? Duration.zero
                : AppleDesignTokens.durationFast,
            curve: AppleDesignTokens.curveSpring,
            child: container,
          );

    return Focus(
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChanged,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _handleAction,
          child: content,
        ),
      ),
    );
  }
}
