import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/receiver/presentation/receiver_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ReceiverPage renders DMR status, AirPlay card, and controls',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ReceiverPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('投屏接收端服务 (DMR & AirPlay)'), findsOneWidget);
    expect(find.text('接收端服务正在运行'), findsOneWidget);
    expect(find.text('AirPlay 接收服务 (APL-01~05 / ADR-004)'), findsOneWidget);
    expect(find.text('服务参数设置 (DMR-05)'), findsOneWidget);
    expect(find.text('聚映家庭大屏'), findsOneWidget);

    // Toggle switch off
    final switchFinder = find.byType(Switch).first;
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(find.text('接收端服务已停用'), findsOneWidget);
  });
}
