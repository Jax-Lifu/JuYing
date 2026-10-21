import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

void main() {
  testWidgets('焦点和鼠标悬停激活后保持布局尺寸且不创建缩放变换', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    const childKey = ValueKey<String>('focus-child');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(AppThemeColors.cinemaDark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TvFocusWrapper(
              focusNode: focusNode,
              child: const SizedBox(
                key: childKey,
                width: 240,
                height: 64,
              ),
            ),
          ),
        ),
      ),
    );

    final wrapper = find.byType(TvFocusWrapper);
    final child = find.byKey(childKey);
    final wrapperSizeBefore = tester.getSize(wrapper);
    final childSizeBefore = tester.getSize(child);

    focusNode.requestFocus();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getSize(wrapper), wrapperSizeBefore);
    expect(tester.getSize(child), childSizeBefore);

    focusNode.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(wrapper));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getSize(wrapper), wrapperSizeBefore);
    expect(tester.getSize(child), childSizeBefore);
    expect(
      find.descendant(of: wrapper, matching: find.byType(AnimatedScale)),
      findsNothing,
    );

    final animatedContainer = tester.widget<AnimatedContainer>(
      find.descendant(
        of: wrapper,
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = animatedContainer.decoration! as BoxDecoration;
    final focusGlow = decoration.boxShadow!.single;

    expect(focusGlow.offset, Offset.zero);
    expect(focusGlow.spreadRadius, 0);
    expect(focusGlow.blurRadius, 6);
  });
}
