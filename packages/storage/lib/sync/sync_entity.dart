/// Synchronizable Entity Model for Multi-Device WebDAV Sync (Section 5.10 & APP-12).
///
/// **What**: Standard envelope for all synced records (history, favorites, sources, settings).
///
/// **Why**: Implements Last-Write-Wins (LWW) conflict resolution with tombstone soft deletions,
/// ensuring concurrent edits across devices resolve deterministically.
class SyncEntity {
  const SyncEntity({
    required this.entityId,
    required this.updatedAt,
    this.isDeleted = false,
    this.data = const <String, dynamic>{},
    this.progressTimestamp,
  });

  /// Unique identifier of the entity (e.g., 'tmdb_movie_12345' or 'siteKey_vodId').
  final String entityId;

  /// Monotonic update timestamp in milliseconds since epoch.
  final int updatedAt;

  /// Tombstone flag for soft deletion synchronization.
  final bool isDeleted;

  /// Payload data fields.
  final Map<String, dynamic> data;

  /// Optional playback position timestamp for media progress resolution.
  final int? progressTimestamp;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'entityId': entityId,
        'updatedAt': updatedAt,
        'isDeleted': isDeleted,
        'data': data,
        if (progressTimestamp != null) 'progressTimestamp': progressTimestamp,
      };

  factory SyncEntity.fromJson(Map<String, dynamic> json) {
    return SyncEntity(
      entityId: json['entityId']?.toString() ?? json['id']?.toString() ?? '',
      updatedAt: _parseTimestamp(json['updatedAt'] ?? json['updatedAtMs']),
      isDeleted: json['isDeleted'] == true,
      data: json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : Map<String, dynamic>.from(json),
      progressTimestamp: json['progressTimestamp'] is num
          ? (json['progressTimestamp'] as num).toInt()
          : null,
    );
  }

  static int _parseTimestamp(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
