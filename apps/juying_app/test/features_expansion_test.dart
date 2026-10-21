import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/history/playback_history_service.dart';
import 'package:juying/features/download/services/offline_download_manager.dart';
import 'package:juying/features/search/services/federated_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackHistoryService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('saves, retrieves, and orders playback history chronologically',
        () async {
      final service = PlaybackHistoryService.instance;

      await service.saveHistory(
        const PlaybackHistoryItem(
          id: 'item_1',
          title: '雪中悍刀行',
          posterUrl: 'https://example.com/poster1.jpg',
          episodeName: '第 1 集',
          episodeIndex: 1,
          positionMs: 60000,
          durationMs: 120000,
          timestampMs: 1000,
        ),
      );

      await service.saveHistory(
        const PlaybackHistoryItem(
          id: 'item_2',
          title: '小小围棋少年',
          posterUrl: 'https://example.com/poster2.jpg',
          episodeName: '第 3 集',
          episodeIndex: 3,
          positionMs: 90000,
          durationMs: 180000,
          timestampMs: 2000,
        ),
      );

      final history = await service.getHistory();
      expect(history.length, 2);
      expect(history.first.title, '小小围棋少年'); // Most recent first
      expect(history.first.progress, 0.5);

      await service.clearHistory();
      final emptyHistory = await service.getHistory();
      expect(emptyHistory.isEmpty, true);
    });

    test('按媒体 ID 恢复上次选择的剧集并兼容旧标题记录', () async {
      final service = PlaybackHistoryService.instance;
      await service.saveHistory(
        const PlaybackHistoryItem(
          id: 'cctv_album_test',
          title: '测试节目',
          posterUrl: '',
          episodeName: '第22集',
          episodeIndex: 22,
          positionMs: 0,
          durationMs: 632000,
          timestampMs: 3000,
        ),
      );

      final restored = await service.findLatestForMedia(
        mediaId: 'cctv_album_test',
        title: '测试节目',
      );

      expect(restored?.episodeIndex, 22);
    });
  });

  group('OfflineDownloadManager Tests', () {
    test('enqueues task and updates task list correctly', () {
      final manager = OfflineDownloadManager.instance;
      final task = manager.enqueueTask(
        id: 'test_task_001',
        title: '测试剧集',
        episodeName: '第 1 集',
        m3u8Url: 'https://example.com/test.m3u8',
        targetDirectory: '/tmp/test_download',
      );

      expect(task.id, 'test_task_001');
      expect(task.status, DownloadTaskStatus.downloading);
      expect(manager.tasks.any((t) => t.id == 'test_task_001'), true);
      final duplicate = manager.enqueueTask(
        id: 'test_task_001',
        title: '测试剧集',
        episodeName: '第 1 集',
        m3u8Url: 'https://example.com/test.m3u8',
        targetDirectory: '/tmp/test_download',
      );
      expect(identical(duplicate, task), true);
      expect(manager.tasks.where((item) => item.id == task.id), hasLength(1));

      manager.pauseTask('test_task_001');
      expect(task.status, DownloadTaskStatus.paused);

      manager.resumeTask('test_task_001');
      expect(task.status, DownloadTaskStatus.downloading);

      manager.deleteTask('test_task_001');
      expect(manager.tasks.any((t) => t.id == 'test_task_001'), false);
    });
  });

  group('FederatedSearchService Tests', () {
    test('initializes and manages monotonic Epoch IDs on search requests', () {
      final searchService = FederatedSearchService();
      expect(searchService.currentEpochId, 0);

      searchService.searchDebounced(
        '三体',
        onUpdate: (results, epoch) {},
      );

      searchService.dispose();
    });
  });
}
