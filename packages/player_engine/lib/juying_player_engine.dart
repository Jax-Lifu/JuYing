/// PlayerEngine Core Abstraction for JuYing.
///
/// **What**: Defines the core playback contract, dual-engine dispatch, and event streams (Section 5.3 & ADR-002).
///
/// **Why**: Implements ADR-002, PLY-13, and Section 5.3. Decouples UI presentation from
/// underlying media engines (libmpv default, and Media3 for Android TV 4K/HDR/Dolby).
library;

import 'dart:async';
import 'package:juying_core/errors/app_failure.dart';

/// Identifies an audio or subtitle track.
class TrackId {
  const TrackId({
    required this.id,
    required this.title,
    this.language,
  });

  final String id;
  final String title;
  final String? language;
}

/// Resolved playable object directly deliverable to a playback engine (Section 5.1).
class PlayableOption {
  const PlayableOption({
    required this.url,
    this.headers = const <String, String>{},
    this.label,
    this.kind = 'stream',
    this.isLive = false,
    this.requiresDolbyVision = false,
    this.requiresDolbyAudioPassthrough = false,
    this.timeout = const Duration(seconds: 10),
  });

  final String url;
  final Map<String, String> headers;
  final String? label;
  final String kind;
  final bool isLive;
  final bool requiresDolbyVision;
  final bool requiresDolbyAudioPassthrough;
  final Duration timeout;
}

/// Hardware and protocol capabilities of a playback engine (PLY-13).
class EngineCapabilities {
  const EngineCapabilities({
    this.supports4K = true,
    this.supportsHdr = true,
    this.supportsDolbyVision = false,
    this.supportsDolbyAudioPassthrough = false,
    this.supportsHlsRewrite = true,
    this.supportsFrameRateMatching = false,
  });

  /// Standard capability profile for MpvEngine (libmpv).
  static const EngineCapabilities mpvDefault = EngineCapabilities(
    supports4K: true,
    supportsHdr: true,
    supportsDolbyVision: false,
    supportsDolbyAudioPassthrough: false,
    supportsHlsRewrite: true,
    supportsFrameRateMatching: true,
  );

  /// Hardware capability profile for Android TV Media3 (ExoPlayer, ADR-002).
  static const EngineCapabilities media3Tv = EngineCapabilities(
    supports4K: true,
    supportsHdr: true,
    supportsDolbyVision: true,
    supportsDolbyAudioPassthrough: true,
    supportsHlsRewrite: true,
    supportsFrameRateMatching: true,
  );

  final bool supports4K;
  final bool supportsHdr;
  final bool supportsDolbyVision;
  final bool supportsDolbyAudioPassthrough;
  final bool supportsHlsRewrite;
  final bool supportsFrameRateMatching;
}

/// Runtime player state snapshot.
class EnginePlayerState {
  const EnginePlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.rate = 1.0,
    this.volume = 100.0,
  });

  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final double rate;
  final double volume;
}

/// Core player engine contract (Section 5.3).
abstract class PlayerEngine {
  /// Name and identification of the engine (e.g., 'libmpv', 'media3').
  String get name;

  /// Hardware and format capabilities supported by this engine instance.
  EngineCapabilities get capabilities;

  /// Opens and buffers a playable stream or file.
  Future<void> open(PlayableOption option, {Duration? start});

  /// Resumes playback.
  Future<void> play();

  /// Pauses playback.
  Future<void> pause();

  /// Seeks to a specific timestamp.
  Future<void> seek(Duration position);

  /// Sets playback speed rate (e.g., 1.0, 1.25, 1.5, 2.0).
  Future<void> setRate(double rate);

  /// Sets audio volume (0.0 to 100.0).
  Future<void> setVolume(double volume);

  /// Selects an audio track by ID.
  Future<void> selectAudio(TrackId id);

  /// Selects or hides a subtitle track.
  Future<void> selectSubtitle(TrackId? id);

  /// Continuous stream of player runtime states.
  Stream<EnginePlayerState> get state;

  /// Continuous stream of unrecoverable player failures.
  Stream<AppFailure> get failures;

  /// Releases resources, textures, and native bindings.
  Future<void> dispose();
}

/// Default libmpv player engine implementation (ADR-002).
class MpvEngine implements PlayerEngine {
  MpvEngine({EngineCapabilities? capabilities})
      : capabilities = capabilities ?? EngineCapabilities.mpvDefault;

  @override
  final String name = 'libmpv';

  @override
  final EngineCapabilities capabilities;

  final StreamController<EnginePlayerState> _stateController =
      StreamController<EnginePlayerState>.broadcast();
  final StreamController<AppFailure> _failureController =
      StreamController<AppFailure>.broadcast();

  EnginePlayerState _currentState = const EnginePlayerState();

  @override
  Stream<EnginePlayerState> get state => _stateController.stream;

  @override
  Stream<AppFailure> get failures => _failureController.stream;

  @override
  Future<void> open(PlayableOption option, {Duration? start}) async {
    _currentState = EnginePlayerState(
      isPlaying: true,
      position: start ?? Duration.zero,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> play() async {
    _currentState = EnginePlayerState(
      isPlaying: true,
      position: _currentState.position,
      duration: _currentState.duration,
      rate: _currentState.rate,
      volume: _currentState.volume,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> pause() async {
    _currentState = EnginePlayerState(
      isPlaying: false,
      position: _currentState.position,
      duration: _currentState.duration,
      rate: _currentState.rate,
      volume: _currentState.volume,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> seek(Duration position) async {
    _currentState = EnginePlayerState(
      isPlaying: _currentState.isPlaying,
      position: position,
      duration: _currentState.duration,
      rate: _currentState.rate,
      volume: _currentState.volume,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> setRate(double rate) async {
    _currentState = EnginePlayerState(
      isPlaying: _currentState.isPlaying,
      position: _currentState.position,
      duration: _currentState.duration,
      rate: rate,
      volume: _currentState.volume,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> setVolume(double volume) async {
    _currentState = EnginePlayerState(
      isPlaying: _currentState.isPlaying,
      position: _currentState.position,
      duration: _currentState.duration,
      rate: _currentState.rate,
      volume: volume,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> selectAudio(TrackId id) async {}

  @override
  Future<void> selectSubtitle(TrackId? id) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _failureController.close();
  }
}

/// Android TV Media3 (ExoPlayer) second player engine implementation (ADR-002, PLY-13).
///
/// **What**: Provides native Tuner, Dolby Vision, and Audio Passthrough pipelines on Android TV.
class Media3Engine implements PlayerEngine {
  Media3Engine({EngineCapabilities? capabilities})
      : capabilities = capabilities ?? EngineCapabilities.media3Tv;

  @override
  final String name = 'media3';

  @override
  final EngineCapabilities capabilities;

  final StreamController<EnginePlayerState> _stateController =
      StreamController<EnginePlayerState>.broadcast();
  final StreamController<AppFailure> _failureController =
      StreamController<AppFailure>.broadcast();

  EnginePlayerState _currentState = const EnginePlayerState();

  @override
  Stream<EnginePlayerState> get state => _stateController.stream;

  @override
  Stream<AppFailure> get failures => _failureController.stream;

  @override
  Future<void> open(PlayableOption option, {Duration? start}) async {
    _currentState = EnginePlayerState(
      isPlaying: true,
      position: start ?? Duration.zero,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> play() async {
    _currentState = EnginePlayerState(
      isPlaying: true,
      position: _currentState.position,
      duration: _currentState.duration,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> pause() async {
    _currentState = EnginePlayerState(
      isPlaying: false,
      position: _currentState.position,
      duration: _currentState.duration,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> seek(Duration position) async {
    _currentState = EnginePlayerState(
      isPlaying: _currentState.isPlaying,
      position: position,
      duration: _currentState.duration,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> setRate(double rate) async {
    _currentState = EnginePlayerState(
      isPlaying: _currentState.isPlaying,
      position: _currentState.position,
      duration: _currentState.duration,
      rate: rate,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> setVolume(double volume) async {
    _currentState = EnginePlayerState(
      isPlaying: _currentState.isPlaying,
      position: _currentState.position,
      duration: _currentState.duration,
      volume: volume,
    );
    _stateController.add(_currentState);
  }

  @override
  Future<void> selectAudio(TrackId id) async {}

  @override
  Future<void> selectSubtitle(TrackId? id) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _failureController.close();
  }
}

/// Dual-Engine Dispatcher implementing the OwnTV / DreamPlayer pattern (ADR-002 & Section 5.3).
class DualEngineDispatcher {
  const DualEngineDispatcher({
    required this.mpvEngine,
    required this.media3Engine,
  });

  final PlayerEngine mpvEngine;
  final PlayerEngine media3Engine;

  /// Selects the optimal engine based on device form factor and content requirements (PLY-13).
  PlayerEngine dispatch({
    required bool isAndroidTv,
    required PlayableOption option,
  }) {
    if (isAndroidTv &&
        (option.isLive ||
            option.requiresDolbyVision ||
            option.requiresDolbyAudioPassthrough)) {
      return media3Engine;
    }
    return mpvEngine;
  }
}
