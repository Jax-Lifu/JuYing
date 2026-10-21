import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

enum PlaybackFailureKind { network, decoder, manifest, unknown }

/// Manages cross-platform video playback lifecycle, hardware decoding fallback, and stream watchdog.
///
/// **What**: Wraps `media_kit` (libmpv), exposing streams for playback state, position, buffering,
/// audio/subtitle track selection, and aspect ratio modes.
///
/// **Why**: Media aggregation clients connect to heterogeneous live and VOD streams.
/// Distinguishing initial media handshake latency from mid-stream stalls prevents premature circuit breaker
/// trips while still offering swift failover when a stream truly drops.
class PlayerEngine {
  PlayerEngine({
    this.onCircuitBreakerTrip,
    this.onError,
  }) {
    _initPlayer();
  }

  /// Exercises playback events without allocating a native video texture.
  @visibleForTesting
  PlayerEngine.forTesting(
    Player player, {
    this.onCircuitBreakerTrip,
    this.onError,
  }) : _player = player {
    _listenEvents();
    _setupWatchdog();
  }

  /// Callback invoked when a stream experiences an unrecoverable stall (>3000ms after starting playback).
  final VoidCallback? onCircuitBreakerTrip;

  /// Callback invoked when playback encounters an unrecoverable decoder or network error.
  final void Function(String error)? onError;

  late final Player _player;
  late final VideoController _videoController;

  Timer? _bufferingWatchdogTimer;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  int _bufferingStallMs = 0;
  bool _isDisposed = false;
  bool _isHardwareDecodingFailed = false;
  bool _hasStartedPlaying = false;
  bool _isInitialLoading = true;
  Duration _initialPosition = Duration.zero;
  int _lastTripTimestamp = 0;

  Player get player => _player;
  VideoController get videoController => _videoController;
  bool get hasStartedPlaying => _hasStartedPlaying;

  /// mpv 对不可跳转流返回的是 seek 能力提示，对静音或特殊音频路由返回 no sound 警告。
  /// 媒体本身仍在正常解码视频画面，将它们当成致命错误会打断正常视频播放。
  @visibleForTesting
  static bool isRecoverablePlaybackWarning(String error) {
    final lower = error.toLowerCase();
    return lower.contains('--force-seekable=yes') ||
        lower.contains('could not open/initialize audio device') ||
        lower.contains('no sound');
  }

  /// 错误分类决定恢复策略：网络错误交给线路熔断，只有解码器错误才关闭硬解。
  @visibleForTesting
  static PlaybackFailureKind classifyFailure(Object error) {
    final message = error.toString().toLowerCase();
    if (<String>[
      'decoder',
      'codec',
      'hwdec',
      'd3d11',
      'texture',
      'video output',
    ].any(message.contains)) {
      return PlaybackFailureKind.decoder;
    }
    if (<String>[
      'm3u8',
      'manifest',
      'playlist',
      'demux',
      'invalid data',
    ].any(message.contains)) {
      return PlaybackFailureKind.manifest;
    }
    if (<String>[
      'http 403',
      'http 404',
      'http 500',
      'network',
      'dns',
      'timed out',
      'timeout',
      'connection',
      'failed to open stream',
    ].any(message.contains)) {
      return PlaybackFailureKind.network;
    }
    return PlaybackFailureKind.unknown;
  }

  void _initPlayer() {
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
        logLevel: kDebugMode ? MPVLogLevel.warn : MPVLogLevel.error,
      ),
    );

    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    _listenEvents();
    _setupWatchdog();
  }

  void _listenEvents() {
    _subscriptions.add(_player.stream.position.listen((pos) {
      if (_isDisposed) return;
      // playing=true and the resume offset can precede decoded playback.
      if (!_isInitialLoading ||
          pos > _initialPosition + const Duration(milliseconds: 100)) {
        _hasStartedPlaying = true;
        _isInitialLoading = false;
        _bufferingStallMs = 0;
      }
    }));

    _subscriptions.add(_player.stream.buffering.listen((buffering) {
      if (_isDisposed) return;
      if (!buffering && _player.state.playing) {
        _bufferingStallMs = 0;
      }
    }));

    _subscriptions.add(_player.stream.error.listen((err) {
      if (_isDisposed) return;
      final message = err.toString();
      if (isRecoverablePlaybackWarning(message)) {
        debugPrint('[PlayerEngine] Ignored non-fatal seek warning: $message');
        return;
      }
      debugPrint('[PlayerEngine] Stream error received: $message');
      // The caller owns error recovery; notifying both callbacks skips a route.
      if (onError != null) {
        onError!(message);
      } else if (classifyFailure(message) == PlaybackFailureKind.network) {
        _triggerFailover('播放线路网络错误');
      }
    }));
  }

  /// Starts periodic polling to detect unrecoverable buffering stalls (>3000ms after initial play).
  void _setupWatchdog() {
    _bufferingWatchdogTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (_isDisposed) return;

        // HLS manifest and first-segment downloads need more time than mid-play stalls.
        if (_isInitialLoading) {
          if (!_player.state.playing) {
            _bufferingStallMs = 0;
            return;
          }
          _bufferingStallMs += 500;
          if (_bufferingStallMs >= 30000) {
            // Initial load timed out
            _triggerFailover('初始连接超时 (30秒)');
          }
          return;
        }

        // Mid-stream stall watchdog (only when playing and buffering)
        if (_player.state.buffering && _player.state.playing) {
          _bufferingStallMs += 500;
          if (_bufferingStallMs >= 3000) {
            _triggerFailover('播放流卡顿超过 3 秒');
          }
        } else {
          _bufferingStallMs = 0;
        }
      },
    );
  }

  void _triggerFailover(String reason) {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Cooldown barrier of 4 seconds between consecutive trips
    if (now - _lastTripTimestamp < 4000) return;
    _lastTripTimestamp = now;
    _bufferingStallMs = 0;
    _isHardwareDecodingFailed = false;

    debugPrint('[PlayerEngine] Watchdog circuit breaker tripped: $reason');
    onCircuitBreakerTrip?.call();
  }

  /// Opens and plays a media stream with automatic hardware decoding failure recovery.
  Future<void> openStream(
    String url, {
    Map<String, String>? headers,
    Duration? startPosition,
  }) async {
    _isInitialLoading = true;
    _hasStartedPlaying = false;
    _bufferingStallMs = 0;
    // media_kit 会把非空 start 转为 mpv 的 start 属性；即使是 0 秒也会
    // 对不可 seek 的直播触发错误，因此只有真正需要续播时才传入。
    final effectiveStart =
        startPosition != null && startPosition > Duration.zero
            ? startPosition
            : null;
    _initialPosition = effectiveStart ?? Duration.zero;

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // Vendor direct-audio paths can reject OpenSLES; let mpv try AudioTrack next.
        await _setNativeProperty('ao', 'opensles,audiotrack');
      }
      await _configureDemuxer(url);
      final media = Media(
        url,
        httpHeaders: headers,
        start: effectiveStart,
      );
      await _player.open(media);
    } catch (e) {
      final failureKind = classifyFailure(e);
      if (failureKind == PlaybackFailureKind.decoder &&
          !_isHardwareDecodingFailed) {
        _isHardwareDecodingFailed = true;
        debugPrint(
            'Hardware decoding error detected ($e), falling back to software decoding...');
        await _setNativeProperty('hwdec', 'no');
        await _configureDemuxer(url);
        final fallbackPosition = _player.state.position > Duration.zero
            ? _player.state.position
            : effectiveStart;
        final media = Media(
          url,
          httpHeaders: headers,
          start: fallbackPosition,
        );
        await _player.open(media);
      } else {
        rethrow;
      }
    }
  }

  /// Forces libavformat to own HLS manifests instead of letting libmpv treat
  /// the M3U8 as a queue of independent 10-second transport-stream files.
  ///
  /// CCTV responds with a non-RFC8216 MIME type on some CDNs. Without this
  /// hint older Windows libmpv builds may reopen every TS entry, resetting the
  /// position and showing a buffering transition at each segment boundary.
  Future<void> _configureDemuxer(String url) async {
    final isHls =
        Uri.tryParse(url)?.path.toLowerCase().endsWith('.m3u8') == true;
    await _setNativeProperty('demuxer-lavf-format', isHls ? 'hls' : '');
    await _setNativeProperty('cache', 'yes');
    await _setNativeProperty('cache-on-disk', 'no');
    await _setNativeProperty(
      'demuxer-readahead-secs',
      isHls ? '30' : '10',
    );
  }

  Future<void> _setNativeProperty(String name, String value) async {
    final platform = _player.platform;
    if (platform is NativePlayer) await platform.setProperty(name, value);
  }

  /// Adjusts audio lip-sync delay offset in milliseconds (-5000ms to +5000ms).
  Future<void> setAudioDelay(double delaySeconds) async {
    await _setNativeProperty('audio-delay', delaySeconds.toString());
  }

  /// Adjusts subtitle synchronization delay offset in milliseconds (-5000ms to +5000ms).
  Future<void> setSubtitleDelay(double delaySeconds) async {
    await _setNativeProperty('sub-delay', delaySeconds.toString());
  }

  /// Changes playback rate while preserving audio pitch.
  Future<void> setRate(double rate) async {
    await _player.setRate(rate);
  }

  /// Toggles pause / play state.
  Future<void> playOrPause() async {
    await _player.playOrPause();
  }

  /// Seeks to specified position.
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Releases player instances and background watchdog timers.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _bufferingWatchdogTimer?.cancel();
    await Future.wait(
        _subscriptions.map((subscription) => subscription.cancel()));
    _subscriptions.clear();
    await _player.dispose();
  }
}
