import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/features/download/presentation/download_page.dart';
import 'package:juying/features/download/services/offline_download_manager.dart';

void main() {
  setUpAll(() async {
    var file = File('assets/i18n/en_US.json');
    if (!await file.exists()) {
      file = File('apps/juying_app/assets/i18n/en_US.json');
    }
    if (await file.exists()) {
      final content = await file.readAsString();
      final map = json.decode(content) as Map<String, dynamic>;
      I18nService.instance.setTranslations(
        'en_US',
        map.map((k, v) => MapEntry(k, v.toString())),
      );
    }
  });

  testWidgets(
      'download page explains unsupported offline layouts in the locale',
      (tester) async {
    final manager = OfflineDownloadManager.instance;
    late DownloadTask task;
    await tester.runAsync(() async {
      task = manager.enqueueTask(
        id: 'unsupported-layout-message',
        title: 'Test video',
        episodeName: 'Episode 1',
        m3u8Url: 'http://127.0.0.1:1/cancelled.m3u8',
        targetDirectory: Directory.systemTemp.path,
      );
      manager.pauseTask(task.id);
      await manager.waitForTask(task.id);
    });
    addTearDown(() => manager.deleteTask(task.id));
    task.status = DownloadTaskStatus.failed;
    task.failureReason = 'unsupported_hls_layout';

    await tester.pumpWidget(
      const MaterialApp(locale: Locale('en', 'US'), home: DownloadPage()),
    );
    expect(
      find.text('Offline downloads are not supported for this video format. '
          'Play online or choose another source.'),
      findsOneWidget,
    );
    expect(find.text('播放'), findsNothing);
    expect(tester.takeException(), isNull);

    task.failureReason = null;
    await tester.pumpWidget(
      MaterialApp(key: UniqueKey(), home: const DownloadPage()),
    );
    expect(find.text('❌ 下载失败'), findsOneWidget);
  });
}
