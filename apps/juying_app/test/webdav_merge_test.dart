import 'package:flutter_test/flutter_test.dart';
import 'package:juying/features/sync/services/webdav_sync_service.dart';

void main() {
  group('WebDavSyncService Merge Tests', () {
    late WebDavSyncService service;

    setUp(() {
      service = WebDavSyncService();
    });

    test('merges local and remote bundles using LWW timestamp correctly', () {
      const local = SyncBundle(
        deviceId: 'device_tv',
        updatedAtMs: 1000,
        history: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'movie_1',
            'title': '庆余年',
            'progress': 0.3,
            'updatedAtMs': 1000,
          },
          <String, dynamic>{
            'id': 'movie_2',
            'title': '三体',
            'progress': 0.8,
            'updatedAtMs': 900,
          },
        ],
      );

      const remote = SyncBundle(
        deviceId: 'device_phone',
        updatedAtMs: 1200,
        history: <Map<String, dynamic>>[
          // Newer progress on phone for movie_1
          <String, dynamic>{
            'id': 'movie_1',
            'title': '庆余年',
            'progress': 0.9,
            'updatedAtMs': 1200,
          },
          // New movie watched on phone
          <String, dynamic>{
            'id': 'movie_3',
            'title': '繁花',
            'progress': 0.5,
            'updatedAtMs': 1100,
          },
        ],
      );

      final merged = service.mergeBundles(local, remote);

      expect(merged.history.length, 3);

      final movie1 = merged.history.firstWhere((e) => e['id'] == 'movie_1');
      expect(movie1['progress'], 0.9); // Remote was newer (1200 > 1000)

      final movie2 = merged.history.firstWhere((e) => e['id'] == 'movie_2');
      expect(movie2['progress'], 0.8);

      final movie3 = merged.history.firstWhere((e) => e['id'] == 'movie_3');
      expect(movie3['progress'], 0.5);

      expect(merged.updatedAtMs, 1200);
    });

    test('keeps newer tombstone and merges favorite fields independently', () {
      const local = SyncBundle(
        deviceId: 'windows',
        updatedAtMs: 2000,
        favorites: <Map<String, dynamic>>[
          <String, dynamic>{
            'entityId': 'movie_1',
            'title': '本地标题',
            'category': '电影',
            'updatedAt': 2000,
            'fieldUpdatedAt': <String, int>{
              'title': 2000,
              'category': 1000,
            },
          },
          <String, dynamic>{
            'entityId': 'movie_2',
            'updatedAt': 1000,
            'isDeleted': false,
          },
        ],
      );
      const remote = SyncBundle(
        deviceId: 'tv',
        updatedAtMs: 3000,
        favorites: <Map<String, dynamic>>[
          <String, dynamic>{
            'entityId': 'movie_1',
            'title': '远端旧标题',
            'category': '收藏',
            'updatedAt': 2100,
            'fieldUpdatedAt': <String, int>{
              'title': 1500,
              'category': 2100,
            },
          },
          <String, dynamic>{
            'entityId': 'movie_2',
            'updatedAt': 3000,
            'isDeleted': true,
          },
        ],
      );

      final merged = service.mergeBundles(local, remote);
      final movie1 = merged.favorites.firstWhere(
        (item) => item['entityId'] == 'movie_1',
      );
      final movie2 = merged.favorites.firstWhere(
        (item) => item['entityId'] == 'movie_2',
      );

      expect(movie1['title'], '本地标题');
      expect(movie1['category'], '收藏');
      expect(movie1['fieldUpdatedAt'], containsPair('title', 2000));
      expect(movie2['isDeleted'], isTrue);

      final mergedAgain = service.mergeBundles(
        merged,
        const SyncBundle(
          deviceId: 'offline-phone',
          updatedAtMs: 1750,
          favorites: <Map<String, dynamic>>[
            <String, dynamic>{
              'entityId': 'movie_1',
              'title': '离线旧标题',
              'updatedAt': 1750,
            },
          ],
        ),
      );
      expect(mergedAgain.favorites.first['title'], '本地标题');
    });

    test('merges settings with per-field timestamps', () {
      const local = SyncBundle(
        deviceId: 'windows',
        updatedAtMs: 1000,
        settings: <String, dynamic>{
          'theme': 'dark',
          'volume': 20,
          '_fieldUpdatedAt': <String, int>{'theme': 3000, 'volume': 1000},
        },
      );
      const remote = SyncBundle(
        deviceId: 'tv',
        updatedAtMs: 2000,
        settings: <String, dynamic>{
          'theme': 'light',
          'volume': 80,
          '_fieldUpdatedAt': <String, int>{'theme': 1500, 'volume': 2000},
        },
      );

      final settings = service.mergeBundles(local, remote).settings;

      expect(settings['theme'], 'dark');
      expect(settings['volume'], 80);
    });

    test('keeps a remote-only setting when local bundle is partial', () {
      const local = SyncBundle(deviceId: 'windows', updatedAtMs: 3000);
      const remote = SyncBundle(
        deviceId: 'tv',
        updatedAtMs: 1000,
        settings: <String, dynamic>{'subtitleEnabled': true},
      );

      final settings = service.mergeBundles(local, remote).settings;

      expect(settings['subtitleEnabled'], isTrue);
      expect(
          settings['_fieldUpdatedAt'], containsPair('subtitleEnabled', 1000));

      final mergedAgain = service.mergeBundles(
        SyncBundle(deviceId: 'windows', updatedAtMs: 3000, settings: settings),
        const SyncBundle(
          deviceId: 'tv',
          updatedAtMs: 2000,
          settings: <String, dynamic>{'subtitleEnabled': false},
        ),
      );
      expect(mergedAgain.settings['subtitleEnabled'], isFalse);
    });
  });
}
