import 'package:test/test.dart';
import 'package:juying_storage/juying_storage.dart';

void main() {
  group('WebDAV Multi-Device Sync & Conflict Resolution Tests (APP-12)', () {
    const resolver = LwwConflictResolver();

    test('LWW resolves to newer entity when remote is newer', () {
      final local = [
        const SyncEntity(
          entityId: 'fav_movie_1',
          updatedAt: 1000,
          data: {'title': '流浪地球'},
        ),
      ];
      final remote = [
        const SyncEntity(
          entityId: 'fav_movie_1',
          updatedAt: 2000,
          data: {'title': '流浪地球 2'},
        ),
      ];

      final merged = resolver.resolve(local, remote);
      expect(merged, hasLength(1));
      expect(merged.first.updatedAt, equals(2000));
      expect(merged.first.data['title'], equals('流浪地球 2'));
    });

    test('Tombstone soft deletion overrides older active record', () {
      final local = [
        const SyncEntity(
          entityId: 'source_cctv_1',
          updatedAt: 1000,
          isDeleted: false,
          data: {'name': 'CCTV-1'},
        ),
      ];
      final remote = [
        const SyncEntity(
          entityId: 'source_cctv_1',
          updatedAt: 1500,
          isDeleted: true,
        ),
      ];

      final merged = resolver.resolve(local, remote);
      expect(merged, hasLength(1));
      expect(merged.first.isDeleted, isTrue);
    });

    test('Playback progress timestamp takes precedence for history items', () {
      final local = [
        const SyncEntity(
          entityId: 'history_ep1',
          updatedAt: 3000,
          progressTimestamp: 500000, // 500s played
        ),
      ];
      final remote = [
        const SyncEntity(
          entityId: 'history_ep1',
          updatedAt:
              3500, // Sync occurred later on another device but had less progress
          progressTimestamp: 120000, // 120s played
        ),
      ];

      final merged =
          resolver.resolve(local, remote, historyProgressAware: true);
      expect(merged, hasLength(1));
      expect(merged.first.progressTimestamp, equals(500000));
    });
  });
}
