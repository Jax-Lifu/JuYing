import 'package:flutter_test/flutter_test.dart';
import 'package:juying/app.dart';
import 'package:juying/core/config/app_config.dart';

void main() {
  testWidgets('renders the application shell', (tester) async {
    await tester.pumpWidget(JuYingApp(
      config: AppConfig.development(),
      sourceConfiguration: AppConfig.developmentSourceConfiguration(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('聚映'), findsWidgets);
    expect(find.text('首页'), findsOneWidget);
  });
}
