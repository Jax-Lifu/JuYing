import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/history/playback_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed history update does not block subsequent playback saves',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final service = PlaybackHistoryService.instance;
    await expectLater(
      service.updateHistory((_) => throw const FormatException('bad snapshot')),
      throwsFormatException,
    );
    await service.saveHistory(
      const PlaybackHistoryItem(
        id: 'after_failure',
        title: '仍可保存',
        posterUrl: '',
        episodeName: '第1集',
        episodeIndex: 1,
        positionMs: 1,
        durationMs: 10,
        timestampMs: 1,
      ),
    );
    expect((await service.getHistory()).single.id, 'after_failure');
  });

  test('旧版分集记录合并时保留最新进度并补齐节目封面', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'juying_playback_history': jsonEncode(<Map<String, Object>>[
        <String, Object>{
          'id': '汪汪队立大功 第八季_22',
          'title': '汪汪队立大功 第八季',
          'posterUrl': '',
          'episodeName': '第22集 寻找小鸡郁金香',
          'episodeIndex': 22,
          'positionMs': 120000,
          'durationMs': 632000,
          'timestampMs': now,
        },
        <String, Object>{
          'id': 'cctv_album_paw_patrol_8',
          'title': '汪汪队立大功 第八季',
          'posterUrl': 'https://example.com/paw-patrol.jpg',
          'episodeName': '第1集 拯救逃跑鸡',
          'episodeIndex': 1,
          'positionMs': 0,
          'durationMs': 632000,
          'timestampMs': now - 1000,
        },
      ]),
    });

    final history = await PlaybackHistoryService.instance.getHistory();

    expect(history, hasLength(1));
    expect(history.single.id, 'cctv_album_paw_patrol_8');
    expect(history.single.posterUrl, 'https://example.com/paw-patrol.jpg');
    expect(history.single.episodeIndex, 22);
    expect(history.single.positionMs, 120000);
  });
}
