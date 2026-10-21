import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juying_ui_kit/juying_ui_kit.dart';

void main() {
  group('UI Kit Apple-Style Tokens & Low-Performance Tests (ADR-010 & APP-13)',
      () {
    test('AppleDesignTokens defines consistent cinema dark palette', () {
      expect(AppleDesignTokens.backgroundDeep, isNotNull);
      expect(AppleDesignTokens.brandPrimary, equals(const Color(0xFF0A84FF)));
      expect(AppleDesignTokens.blurMedium, equals(16.0));
    });

    test(
        'LowPerformancePolicy eliminates blur and uses solid fallback in low-spec mode',
        () {
      const normalPolicy = LowPerformancePolicy(isLowPerformanceMode: false);
      expect(normalPolicy.resolveBlur(16.0), equals(16.0));
      expect(normalPolicy.resolveSurface(),
          equals(AppleDesignTokens.surfaceCardGlass));
      expect(normalPolicy.resolveDuration(const Duration(milliseconds: 250)),
          equals(const Duration(milliseconds: 250)));

      const lowPerfPolicy = LowPerformancePolicy(isLowPerformanceMode: true);
      expect(lowPerfPolicy.resolveBlur(16.0), equals(0.0));
      expect(lowPerfPolicy.resolveSurface(),
          equals(AppleDesignTokens.surfaceSolidFallback));
      expect(lowPerfPolicy.resolveDuration(const Duration(milliseconds: 250)),
          equals(Duration.zero));
    });

    testWidgets(
        'AppleGlassCard renders BackdropFilter normally and solid box in low-performance mode',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppleGlassCard(
              isLowPerformanceMode: false,
              child: Text('Normal Mode'),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Normal Mode'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppleGlassCard(
              isLowPerformanceMode: true,
              child: Text('Low Perf Mode'),
            ),
          ),
        ),
      );
      // BackdropFilter should NOT be rendered in low-performance mode
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Low Perf Mode'), findsOneWidget);
    });

    testWidgets('TvFocusGlow reacts to focus and triggers onTap',
        (tester) async {
      var tapped = false;
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvFocusGlow(
              focusNode: focusNode,
              onTap: () => tapped = true,
              child: const Text('Focus Card'),
            ),
          ),
        ),
      );

      expect(find.text('Focus Card'), findsOneWidget);
      expect(tapped, isFalse);

      // Request focus
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      // Simulate D-Pad Enter key press
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });
}
