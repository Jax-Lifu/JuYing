import '../models/live_program.dart';
import '../models/unified_media.dart';

/// 可选的统一直播节目单能力；不会让 UI 读取来源专有 EPG 字段。
abstract interface class LiveProgramGuide {
  Future<List<LiveProgram>> programGuide(
    MediaItem item, {
    DateTime? now,
  });
}
