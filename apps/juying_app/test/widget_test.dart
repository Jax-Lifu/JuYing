import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/main.dart';

void main() {
  setUpAll(() async {
    // Seed i18n translations from local JSON file for widget test environment
    var file = File('assets/i18n/zh_CN.json');
    if (!await file.exists()) {
      file = File('apps/juying_app/assets/i18n/zh_CN.json');
    }
    if (await file.exists()) {
      final content = await file.readAsString();
      final map = json.decode(content) as Map<String, dynamic>;
      I18nService.instance.setTranslations(
        'zh_CN',
        map.map((k, v) => MapEntry(k, v.toString())),
      );
    }
  });

  testWidgets('JuYing app initial smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: JuYingApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify that primary navigation and branding renders properly.
    expect(find.text('聚'), findsOneWidget);
    expect(find.text('首页推荐'), findsOneWidget);
    expect(find.text('央视专区'), findsOneWidget);
    expect(find.text('电视直播'), findsOneWidget);
    expect(find.text('局域网/NAS'), findsOneWidget);
  });
}
