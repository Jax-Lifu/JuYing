import 'package:flutter/foundation.dart';

/// 仅用于本地诊断的播放结果；刻意不含 URL、Cookie、查询词、标题或档案 ID。
enum PlaybackTelemetryEvent { opening, ready, failed, qualityChanged, ended }

enum PlaybackTelemetryMode { native, officialPage }

class PlaybackTelemetryRecord {
  const PlaybackTelemetryRecord({
    required this.event,
    required this.mode,
    required this.sourceId,
    required this.sourceEpisodeId,
    required this.platform,
    required this.recordedAt,
    this.errorCode,
  });

  final PlaybackTelemetryEvent event;
  final PlaybackTelemetryMode mode;
  final String sourceId;
  final String sourceEpisodeId;
  final String platform;
  final DateTime recordedAt;
  final String? errorCode;
}

abstract interface class PlaybackTelemetrySink {
  void record(PlaybackTelemetryRecord value);
}

/// 会话内、容量受限的本地诊断缓冲区。后续“导出诊断包”只能从这里取脱敏事件。
class PlaybackTelemetry extends ChangeNotifier
    implements PlaybackTelemetrySink {
  PlaybackTelemetry({this.maximumRecords = 120, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static final shared = PlaybackTelemetry();

  final int maximumRecords;
  final DateTime Function() _clock;
  final List<PlaybackTelemetryRecord> _records = [];

  List<PlaybackTelemetryRecord> get records => List.unmodifiable(_records);

  @override
  void record(PlaybackTelemetryRecord value) {
    _records.add(value);
    if (_records.length > maximumRecords) _records.removeAt(0);
    notifyListeners();
  }

  void recordEvent({
    required PlaybackTelemetryEvent event,
    required PlaybackTelemetryMode mode,
    required String sourceId,
    required String sourceEpisodeId,
    required String platform,
    String? errorCode,
  }) =>
      record(
        PlaybackTelemetryRecord(
          event: event,
          mode: mode,
          sourceId: sourceId,
          sourceEpisodeId: sourceEpisodeId,
          platform: platform,
          recordedAt: _clock().toUtc(),
          errorCode: errorCode,
        ),
      );

  void clear() {
    if (_records.isEmpty) return;
    _records.clear();
    notifyListeners();
  }
}
