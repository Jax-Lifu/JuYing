import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/playback/playback_telemetry.dart';

void main() {
  test('播放诊断只保留受限数量的脱敏来源事件', () {
    final telemetry = PlaybackTelemetry(
      maximumRecords: 2,
      clock: () => DateTime.utc(2026, 8, 19),
    );

    for (var index = 0; index < 3; index++) {
      telemetry.recordEvent(
        event: PlaybackTelemetryEvent.ready,
        mode: PlaybackTelemetryMode.native,
        sourceId: 'webdav-local',
        sourceEpisodeId: 'file-$index',
        platform: 'windows',
      );
    }

    expect(telemetry.records, hasLength(2));
    expect(telemetry.records.first.sourceEpisodeId, 'file-1');
    expect(
      telemetry.records
          .singleWhere((item) => item.sourceEpisodeId == 'file-2')
          .recordedAt,
      DateTime.utc(2026, 8, 19),
    );
  });

  test('用户清空诊断只影响会话内缓冲区', () {
    final telemetry = PlaybackTelemetry();
    telemetry.recordEvent(
      event: PlaybackTelemetryEvent.failed,
      mode: PlaybackTelemetryMode.officialPage,
      sourceId: 'cctv-official',
      sourceEpisodeId: 'episode-1',
      platform: 'windows',
      errorCode: 'official_ready_timeout',
    );

    telemetry.clear();

    expect(telemetry.records, isEmpty);
  });
}
