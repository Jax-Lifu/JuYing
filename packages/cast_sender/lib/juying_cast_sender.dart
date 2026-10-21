/// DLNA Media Controller (DMC) Sender for JuYing.
///
/// **What**: Coordinates device discovery, URL pushing, and remote transport
/// controls (Play, Pause, Stop, Seek, Volume) as well as device profile fallback (CAST-01~05).
///
/// **Why**: Implements Section 5.7 DLNA sender pipeline.
library;

export 'src/dlna_cast_service.dart';

/// Playback transport state on remote DMR.
enum CastTransportState {
  stopped,
  playing,
  paused,
  transitioning,
  noMediaPresent,
}
