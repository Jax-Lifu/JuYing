import 'package:juying_core/models/media_item.dart';

/// Origin of a playback request.
enum PlaybackOrigin {
  local,
  dmr,
  airplay,
}

/// Lifecycle state of a playback session.
enum PlaybackSessionState {
  idle,
  opening,
  playing,
  paused,
  buffering,
  completed,
  failed,
}

/// Active runtime playback session entity.
///
/// **What**: Encapsulates the media work, playback origin, position, and lifecycle state.
///
/// **Why**: Implements Section 5.1 and ADR-007 of the JuYing guidance document.
/// Decouples playback execution from triggering sources (local click, DLNA push, AirPlay).
class PlaybackSession {
  const PlaybackSession({
    required this.id,
    required this.origin,
    required this.media,
    this.state = PlaybackSessionState.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.errorMessage,
  });

  /// Unique session identifier.
  final String id;

  /// Originating protocol of this playback request (local, dmr, airplay).
  final PlaybackOrigin origin;

  /// Target media entity.
  final MediaItem media;

  /// Current session state.
  final PlaybackSessionState state;

  /// Current playback timestamp.
  final Duration position;

  /// Total duration of media.
  final Duration duration;

  /// Diagnostic error message if [state] is [PlaybackSessionState.failed].
  final String? errorMessage;

  PlaybackSession copyWith({
    String? id,
    PlaybackOrigin? origin,
    MediaItem? media,
    PlaybackSessionState? state,
    Duration? position,
    Duration? duration,
    String? errorMessage,
  }) {
    return PlaybackSession(
      id: id ?? this.id,
      origin: origin ?? this.origin,
      media: media ?? this.media,
      state: state ?? this.state,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
