import 'sync_entity.dart';

/// Bidirectional Sync Conflict Resolver utilizing Last-Write-Wins (LWW).
///
/// **What**: Merges local and remote entity lists deterministically.
///
/// **Why**: Implements Section 2.1 of sync-storage-engine skill & APP-12. Avoids
/// state oscillation and resurrection of deleted items across multi-device clients.
class LwwConflictResolver {
  const LwwConflictResolver();

  /// Resolves conflicts between two collections of [SyncEntity].
  ///
  /// - Tombstones are honored based on their `updatedAt` timestamp.
  /// - When [historyProgressAware] is true, larger playback progress timestamps take
  ///   precedence between active playback history entries.
  List<SyncEntity> resolve(
    List<SyncEntity> local,
    List<SyncEntity> remote, {
    bool historyProgressAware = false,
  }) {
    final merged = <String, SyncEntity>{};

    for (final entity in local) {
      if (entity.entityId.isNotEmpty) {
        merged[entity.entityId] = entity;
      }
    }

    for (final remoteEntity in remote) {
      final id = remoteEntity.entityId;
      if (id.isEmpty) continue;

      final localEntity = merged[id];
      if (localEntity == null) {
        merged[id] = remoteEntity;
        continue;
      }

      // Progress-aware merge for playback history
      if (historyProgressAware &&
          !localEntity.isDeleted &&
          !remoteEntity.isDeleted) {
        final localProg = localEntity.progressTimestamp ?? 0;
        final remoteProg = remoteEntity.progressTimestamp ?? 0;
        if (remoteProg != localProg) {
          merged[id] = remoteProg > localProg ? remoteEntity : localEntity;
          continue;
        }
      }

      // Standard Last-Write-Wins (LWW)
      if (remoteEntity.updatedAt > localEntity.updatedAt) {
        merged[id] = remoteEntity;
      }
    }

    final result = merged.values.toList()
      ..sort((a, b) => a.entityId.compareTo(b.entityId));
    return result;
  }
}
