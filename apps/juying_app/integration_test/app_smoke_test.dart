import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/proxy/local_proxy_server.dart';
import 'package:juying/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await I18nService.instance.init();
  });

  tearDown(() async {
    await LocalProxyServer.instance.gateway.stop();
  });

  testWidgets(
      'Windows app opens settings and exposes paired LAN QR only on demand',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: JuYingApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(find.text('系统设置'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('⚙️ 设置中心'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);

    await tester.tap(find.text('开启局域网门户'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining(RegExp(r'配对码：\d{6}')), findsOneWidget);
    expect(find.text('关闭局域网门户'), findsOneWidget);

    await tester.tap(find.text('关闭局域网门户'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
  });
}
