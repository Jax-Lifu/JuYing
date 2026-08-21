import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../application/playback/playback_history_store.dart';
import '../../../application/playback/playback_preference_store.dart';
import '../../../application/playback/playback_telemetry.dart';
import '../../../application/profiles/child_usage_store.dart';
import '../../../core/platform/window_controls.dart';
import '../../../domain/models/media_source.dart';
import '../../../domain/models/unified_media.dart';
import '../infrastructure/native_player_backend.dart';

/// 跨平台的原生播放器页面，基于 media_kit 与原生解码渲染。
/// 支持 HLS、MP4、MKV、Samba (smb://)、NFS (nfs://)、WebDAV 与直播电视频道直连切换。
enum PlayerAspectRatio {
  auto('自适应'),
  ratio16_9('16:9'),
  ratio4_3('4:3'),
  fill('铺满全屏');

  const PlayerAspectRatio(this.label);
  final String label;
}

class NativePlayerPage extends StatefulWidget {
  const NativePlayerPage({
    required this.playback,
    required this.episodes,
    required this.resolveEpisode,
    required this.profileId,
    required this.sourceCapabilities,
    this.childDailyLimitMinutes,
    this.windowControls = const WindowsWindowControls(),
    this.telemetry,
    super.key,
  });

  final PlaybackDescriptor playback;
  final List<MediaEpisode> episodes;
  final Future<PlaybackDescriptor> Function(MediaEpisode episode) resolveEpisode;
  final String profileId;
  final Set<SourceCapability> sourceCapabilities;
  final int? childDailyLimitMinutes;
  final WindowControls windowControls;
  final PlaybackTelemetry? telemetry;

  @override
  State<NativePlayerPage> createState() => _NativePlayerPageState();
}

class _NativePlayerPageState extends State<NativePlayerPage> {
  late final Player _player = createNativePlayer();
  late final VideoController _videoController = VideoController(_player);
  final PlaybackPreferenceStore _preferenceStore = PlaybackPreferenceStore();
  final PlaybackHistoryStore _historyStore = PlaybackHistoryStore();
  final ChildUsageStore _childUsageStore = ChildUsageStore();
  late final PlaybackTelemetry _telemetry =
      widget.telemetry ?? PlaybackTelemetry.shared;

  late final PlayerFullscreenSession _fullscreenSession =
      PlayerFullscreenSession(widget.windowControls);

  late PlaybackDescriptor _playback = widget.playback;
  late final List<MediaEpisode> _episodes = widget.episodes;
  MediaEpisode? _currentEpisode;

  final List<StreamSubscription> _subscriptions = [];
  Timer? _controlsTimer;
  Timer? _osdTimer;
  Timer? _numberInputTimer;

  bool _controlsVisible = true;
  bool _channelDrawerOpen = false;
  bool _osdVisible = true;
  bool _isFullscreen = false;
  bool _isPlaying = false;
  bool _isBuffering = true;
  bool _timeLimitReached = false;
  Object? _error;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastUsagePosition = Duration.zero;
  double _volume = 1.0;
  double _playbackRate = 1.0;
  PlayerAspectRatio _aspectRatio = PlayerAspectRatio.auto;
  String _numberInputBuffer = '';
  String _drawerSearchFilter = '';
  int _currentLineIndex = 0;

  bool get _canChangeSpeed =>
      widget.sourceCapabilities.contains(SourceCapability.playbackSpeed) &&
      !_isLive;

  bool get _canChangeVolume =>
      widget.sourceCapabilities.contains(SourceCapability.volumeControl);

  bool get _canFullscreen =>
      widget.sourceCapabilities.contains(SourceCapability.fullscreen);

  bool get _canChooseEpisode => _episodes.length > 1;

  bool get _isLive {
    if (widget.sourceCapabilities.contains(SourceCapability.liveCatalog)) {
      return true;
    }
    if (_playback.duration != null && _playback.duration! > Duration.zero) {
      return false;
    }
    return _duration == Duration.zero;
  }

  int get _currentEpisodeIndex {
    if (_currentEpisode == null) {
      final idx = _episodes.indexWhere(
        (ep) => ep.sourceEpisodeId == _playback.sourceEpisodeId,
      );
      return idx >= 0 ? idx : 0;
    }
    return _episodes.indexOf(_currentEpisode!);
  }

  @override
  void initState() {
    super.initState();
    _initCurrentEpisode();
    _setupPlayerListeners();
    _initializePlayback();
  }

  void _initCurrentEpisode() {
    if (_episodes.isNotEmpty) {
      _currentEpisode = _episodes.firstWhere(
        (ep) => ep.sourceEpisodeId == _playback.sourceEpisodeId,
        orElse: () => _episodes.first,
      );
    }
  }

  void _setupPlayerListeners() {
    _subscriptions.add(_player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    }));

    _subscriptions.add(_player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    }));

    _subscriptions.add(_player.stream.position.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
      _handleProgress(pos);
    }));

    _subscriptions.add(_player.stream.duration.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
    }));

    _subscriptions.add(_player.stream.completed.listen((completed) {
      if (completed && mounted && !_timeLimitReached) {
        _telemetry.recordEvent(
          event: PlaybackTelemetryEvent.ended,
          mode: PlaybackTelemetryMode.native,
          sourceId: _playback.sourceId,
          sourceEpisodeId: _playback.sourceEpisodeId,
          platform: defaultTargetPlatform.name,
        );
        _playNextEpisode();
      }
    }));

    _subscriptions.add(_player.stream.error.listen((err) {
      if (mounted && err.isNotEmpty) {
        _autoFailoverNextLine(err);
      }
    }));
  }

  Future<void> _initializePlayback() async {
    try {
      _telemetry.recordEvent(
        event: PlaybackTelemetryEvent.opening,
        mode: PlaybackTelemetryMode.native,
        sourceId: _playback.sourceId,
        sourceEpisodeId: _playback.sourceEpisodeId,
        platform: defaultTargetPlatform.name,
      );

      if (await _hasReachedChildLimit()) {
        if (mounted) setState(() => _timeLimitReached = true);
        return;
      }

      final preferences = await _preferenceStore.load(
        profileId: widget.profileId,
        sourceId: _playback.sourceId,
      );
      _playbackRate = preferences.speed;
      _volume = preferences.volume;
      await _player.setVolume(_volume * 100);
      if (_canChangeSpeed) {
        await _player.setRate(_playbackRate);
      }

      await _openCurrentStream();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _openCurrentStream() async {
    final uri = _playback.nativeStreamUri;
    if (uri == null) {
      setState(() => _error = StateError('未提供可用的原生流媒体地址'));
      return;
    }

    setState(() {
      _error = null;
      _isBuffering = true;
      _osdVisible = true;
    });
    _scheduleOsdHide();
    _scheduleControlsHide();

    // 如果是直播，记录用户最后播放的频道
    if (_isLive && _currentEpisode != null) {
      unawaited(_preferenceStore.saveLastLiveChannel(
        profileId: widget.profileId,
        sourceId: _playback.sourceId,
        channelId: _currentEpisode!.sourceEpisodeId,
      ));
    }

    // 非直播恢复历史进度
    Duration startPosition = Duration.zero;
    if (!_isLive) {
      startPosition = await _loadResumePosition();
    }

    await _player.open(
      Media(
        uri.toString(),
        httpHeaders: _playback.httpHeaders,
        start: startPosition > Duration.zero ? startPosition : null,
      ),
      play: true,
    );

    _telemetry.recordEvent(
      event: PlaybackTelemetryEvent.ready,
      mode: PlaybackTelemetryMode.native,
      sourceId: _playback.sourceId,
      sourceEpisodeId: _playback.sourceEpisodeId,
      platform: defaultTargetPlatform.name,
    );
  }

  Future<void> _selectLine(int index) async {
    final options = _playback.qualityOptions;
    if (index < 0 || index >= options.length) return;
    setState(() {
      _currentLineIndex = index;
      _isBuffering = true;
      _error = null;
    });
    final selectedOption = options[index];
    _playback = PlaybackDescriptor(
      sourceId: _playback.sourceId,
      sourceEpisodeId: _playback.sourceEpisodeId,
      title: _playback.title,
      officialPageUri: _playback.officialPageUri,
      nativeStreamUri: selectedOption.streamUri,
      qualityOptions: _playback.qualityOptions,
      httpHeaders: _playback.httpHeaders,
      posterUri: _playback.posterUri,
      duration: _playback.duration,
    );
    await _openCurrentStream();
  }

  Future<void> _autoFailoverNextLine([Object? error]) async {
    final options = _playback.qualityOptions;
    if (options.length > 1 && _currentLineIndex + 1 < options.length) {
      final nextIdx = _currentLineIndex + 1;
      final nextOption = options[nextIdx];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('当前流连接失败，正在自动切换至 ${nextOption.label}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await _selectLine(nextIdx);
    } else {
      if (mounted) setState(() => _error = error ?? '播放失败');
    }
  }

  void _onDigitPressed(int digit) {
    if (!_isLive || _episodes.isEmpty) return;
    _numberInputTimer?.cancel();
    setState(() {
      _numberInputBuffer = '$_numberInputBuffer$digit';
    });
    _numberInputTimer =
        Timer(const Duration(milliseconds: 1200), _confirmNumberJump);
  }

  void _confirmNumberJump() {
    _numberInputTimer?.cancel();
    if (_numberInputBuffer.isEmpty) return;
    final parsed = int.tryParse(_numberInputBuffer);
    final buffer = _numberInputBuffer;
    setState(() => _numberInputBuffer = '');
    if (parsed == null || parsed <= 0) return;

    if (parsed <= _episodes.length) {
      _switchEpisode(_episodes[parsed - 1]);
      return;
    }

    final matched = _episodes.where((ep) {
      final id = ep.sourceEpisodeId.toLowerCase();
      final title = ep.title.toLowerCase();
      return id.contains(buffer) || title.contains(buffer);
    }).firstOrNull;

    if (matched != null) {
      _switchEpisode(matched);
    }
  }

  void _cycleAspectRatio() {
    final next = switch (_aspectRatio) {
      PlayerAspectRatio.auto => PlayerAspectRatio.ratio16_9,
      PlayerAspectRatio.ratio16_9 => PlayerAspectRatio.ratio4_3,
      PlayerAspectRatio.ratio4_3 => PlayerAspectRatio.fill,
      PlayerAspectRatio.fill => PlayerAspectRatio.auto,
    };
    setState(() => _aspectRatio = next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('画面比例：${next.label}'),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<Duration> _loadResumePosition() async {
    final history = await _historyStore.load(profileId: widget.profileId);
    for (final entry in history) {
      if (entry.sourceId == _playback.sourceId &&
          entry.sourceEpisodeId == _playback.sourceEpisodeId &&
          entry.position > const Duration(seconds: 5)) {
        return entry.position;
      }
    }
    return Duration.zero;
  }

  Future<bool> _hasReachedChildLimit() async {
    final limit = widget.childDailyLimitMinutes;
    if (limit == null) return false;
    final used = await _childUsageStore.consumedToday(widget.profileId);
    return used >= Duration(minutes: limit);
  }

  Future<void> _handleProgress(Duration position) async {
    if (!_isLive && position > const Duration(seconds: 2)) {
      unawaited(_historyStore.record(
        playback: _playback,
        position: position,
        duration: _duration > Duration.zero ? _duration : null,
        profileId: widget.profileId,
      ));
    }

    final limit = widget.childDailyLimitMinutes;
    if (limit == null || _timeLimitReached) {
      _lastUsagePosition = position;
      return;
    }
    final delta = position - _lastUsagePosition;
    _lastUsagePosition = position;
    if (delta <= Duration.zero || delta > const Duration(seconds: 15)) return;
    final used = await _childUsageStore.addWatchTime(widget.profileId, delta);
    if (used >= Duration(minutes: limit) && mounted) {
      _timeLimitReached = true;
      await _player.pause();
      setState(() {});
    }
  }

  Future<void> _switchEpisode(MediaEpisode targetEpisode) async {
    if (_currentEpisode?.sourceEpisodeId == targetEpisode.sourceEpisodeId) {
      return;
    }
    setState(() {
      _currentEpisode = targetEpisode;
      _error = null;
      _isBuffering = true;
      _osdVisible = true;
    });
    _scheduleOsdHide();

    try {
      final descriptor = await widget.resolveEpisode(targetEpisode);
      if (!mounted) return;
      _playback = descriptor;
      await _openCurrentStream();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _nextChannel() {
    if (_episodes.isEmpty) return;
    final nextIndex = (_currentEpisodeIndex + 1) % _episodes.length;
    _switchEpisode(_episodes[nextIndex]);
  }

  void _prevChannel() {
    if (_episodes.isEmpty) return;
    final prevIndex =
        (_currentEpisodeIndex - 1 + _episodes.length) % _episodes.length;
    _switchEpisode(_episodes[prevIndex]);
  }

  void _playNextEpisode() {
    if (_episodes.isEmpty) return;
    final nextIndex = _currentEpisodeIndex + 1;
    if (nextIndex < _episodes.length) {
      _switchEpisode(_episodes[nextIndex]);
    }
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    if (_controlsVisible && !_channelDrawerOpen) {
      _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && !_channelDrawerOpen) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  void _scheduleOsdHide() {
    _osdTimer?.cancel();
    _osdTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _osdVisible = false);
    });
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (_controlsVisible) {
        _scheduleControlsHide();
      }
    });
  }

  void _showControls() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _scheduleControlsHide();
  }

  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    setState(() => _isFullscreen = next);
    try {
      if (next) {
        await _fullscreenSession.enter();
      } else {
        await _fullscreenSession.exit();
      }
    } catch (_) {}
  }

  Future<void> _exitPlayer() async {
    if (_isFullscreen) {
      await _toggleFullscreen();
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _playbackRate = speed);
    await _player.setRate(speed);
    await _preferenceStore.update(
      profileId: widget.profileId,
      sourceId: _playback.sourceId,
      speed: speed,
    );
  }

  Future<void> _setVolume(double volume) async {
    setState(() => _volume = volume);
    await _player.setVolume(volume * 100);
    await _preferenceStore.update(
      profileId: widget.profileId,
      sourceId: _playback.sourceId,
      volume: volume,
    );
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _osdTimer?.cancel();
    _numberInputTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _fullscreenSession.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_timeLimitReached) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_off_rounded,
                  color: Colors.amber, size: 64),
              const SizedBox(height: 16),
              Text(
                '已达到今日观看时长上限',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                '请明天再继续收看，或由家长调整使用时长限制。',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('退出播放'),
              ),
            ],
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _exitPlayer,
        const SingleActivator(LogicalKeyboardKey.space): () {
          _player.playOrPause();
          _showControls();
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): _prevChannel,
        const SingleActivator(LogicalKeyboardKey.arrowDown): _nextChannel,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (_isLive) {
            _prevChannel();
          } else {
            final target = _position - const Duration(seconds: 10);
            _player.seek(target < Duration.zero ? Duration.zero : target);
            _showControls();
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (_isLive) {
            _nextChannel();
          } else {
            final target = _position + const Duration(seconds: 10);
            _player.seek(target > _duration ? _duration : target);
            _showControls();
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_numberInputBuffer.isNotEmpty) {
            _confirmNumberJump();
          } else {
            setState(() => _channelDrawerOpen = !_channelDrawerOpen);
          }
        },
        const SingleActivator(LogicalKeyboardKey.select): () {
          if (_numberInputBuffer.isNotEmpty) {
            _confirmNumberJump();
          } else {
            setState(() => _channelDrawerOpen = !_channelDrawerOpen);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyA): _cycleAspectRatio,
        const SingleActivator(LogicalKeyboardKey.keyH): () =>
            _showShortcutHelpDialog(context),
        const SingleActivator(LogicalKeyboardKey.keyM): () {
          _setVolume(_volume > 0 ? 0.0 : 1.0);
        },
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
        // 数字键选台
        const SingleActivator(LogicalKeyboardKey.digit0): () =>
            _onDigitPressed(0),
        const SingleActivator(LogicalKeyboardKey.digit1): () =>
            _onDigitPressed(1),
        const SingleActivator(LogicalKeyboardKey.digit2): () =>
            _onDigitPressed(2),
        const SingleActivator(LogicalKeyboardKey.digit3): () =>
            _onDigitPressed(3),
        const SingleActivator(LogicalKeyboardKey.digit4): () =>
            _onDigitPressed(4),
        const SingleActivator(LogicalKeyboardKey.digit5): () =>
            _onDigitPressed(5),
        const SingleActivator(LogicalKeyboardKey.digit6): () =>
            _onDigitPressed(6),
        const SingleActivator(LogicalKeyboardKey.digit7): () =>
            _onDigitPressed(7),
        const SingleActivator(LogicalKeyboardKey.digit8): () =>
            _onDigitPressed(8),
        const SingleActivator(LogicalKeyboardKey.digit9): () =>
            _onDigitPressed(9),
        const SingleActivator(LogicalKeyboardKey.numpad0): () =>
            _onDigitPressed(0),
        const SingleActivator(LogicalKeyboardKey.numpad1): () =>
            _onDigitPressed(1),
        const SingleActivator(LogicalKeyboardKey.numpad2): () =>
            _onDigitPressed(2),
        const SingleActivator(LogicalKeyboardKey.numpad3): () =>
            _onDigitPressed(3),
        const SingleActivator(LogicalKeyboardKey.numpad4): () =>
            _onDigitPressed(4),
        const SingleActivator(LogicalKeyboardKey.numpad5): () =>
            _onDigitPressed(5),
        const SingleActivator(LogicalKeyboardKey.numpad6): () =>
            _onDigitPressed(6),
        const SingleActivator(LogicalKeyboardKey.numpad7): () =>
            _onDigitPressed(7),
        const SingleActivator(LogicalKeyboardKey.numpad8): () =>
            _onDigitPressed(8),
        const SingleActivator(LogicalKeyboardKey.numpad9): () =>
            _onDigitPressed(9),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: MouseRegion(
            onHover: (_) => _showControls(),
            child: GestureDetector(
              onTap: _toggleControls,
              onDoubleTap: _canFullscreen ? _toggleFullscreen : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Video surface with aspect ratio
                  _buildVideoSurface(),

                  // Buffering spinner
                  if (_isBuffering && _error == null)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),

                  // Error Overlay
                  if (_error != null) _buildErrorOverlay(),

                  // Live Channel OSD Banner
                  if (_isLive && _osdVisible && _error == null)
                    _buildChannelOsd(),

                  // Floating Number Input Overlay
                  _buildNumberInputOverlay(),

                  // Top & Bottom Control Overlays
                  if (_controlsVisible) _buildControlsOverlay(),

                  // Native Live Channel Switching Sidebar / Drawer
                  if (_channelDrawerOpen && _canChooseEpisode)
                    _buildChannelDrawer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    Widget videoWidget = Video(
      controller: _videoController,
      controls: NoVideoControls,
      fit: _aspectRatio == PlayerAspectRatio.fill
          ? BoxFit.fill
          : BoxFit.contain,
    );

    if (_aspectRatio == PlayerAspectRatio.ratio16_9) {
      videoWidget = AspectRatio(
        aspectRatio: 16 / 9,
        child: videoWidget,
      );
    } else if (_aspectRatio == PlayerAspectRatio.ratio4_3) {
      videoWidget = AspectRatio(
        aspectRatio: 4 / 3,
        child: videoWidget,
      );
    }

    return Center(child: videoWidget);
  }

  Widget _buildNumberInputOverlay() {
    if (_numberInputBuffer.isEmpty) return const SizedBox.shrink();
    final parsed = int.tryParse(_numberInputBuffer);
    String? matchedTitle;
    if (parsed != null && parsed > 0 && parsed <= _episodes.length) {
      matchedTitle = _episodes[parsed - 1].title;
    }
    return Positioned(
      top: 36,
      right: 36,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 16),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.dialpad_rounded,
                    color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text(
                  _numberInputBuffer,
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (matchedTitle != null) ...[
              const SizedBox(height: 4),
              Text(
                matchedTitle,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChannelOsd() {
    final title = _currentEpisode?.title ?? _playback.title;
    final indexStr = (_currentEpisodeIndex + 1).toString().padLeft(2, '0');
    return Positioned(
      top: 36,
      left: 36,
      child: AnimatedOpacity(
        opacity: _osdVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  indexStr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Row(
                    children: [
                      Icon(Icons.fiber_manual_record,
                          color: Colors.redAccent, size: 10),
                      SizedBox(width: 4),
                      Text(
                        '正在直播',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    final title = _currentEpisode?.title ?? _playback.title;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Top App Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  tooltip: '返回',
                  onPressed: _exitPlayer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_canChooseEpisode)
                  IconButton(
                    icon: const Icon(Icons.format_list_bulleted_rounded,
                        color: Colors.white),
                    tooltip: _isLive ? '频道列表' : '选集',
                    onPressed: () {
                      setState(
                          () => _channelDrawerOpen = !_channelDrawerOpen);
                    },
                  ),
                if (_canChangeSpeed)
                  PopupMenuButton<double>(
                    tooltip: '倍速',
                    initialValue: _playbackRate,
                    onSelected: _setSpeed,
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 0.75, child: Text('0.75×')),
                      PopupMenuItem(value: 1.0, child: Text('1.0×')),
                      PopupMenuItem(value: 1.25, child: Text('1.25×')),
                      PopupMenuItem(value: 1.5, child: Text('1.5×')),
                      PopupMenuItem(value: 2.0, child: Text('2.0×')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Center(
                        child: Text(
                          '$_playbackRate×',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                if (_canChangeVolume)
                  IconButton(
                    icon: Icon(
                      _volume == 0
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white,
                    ),
                    tooltip: '音量',
                    onPressed: _showVolumeSlider,
                  ),
                IconButton(
                  icon: const Icon(Icons.aspect_ratio_rounded,
                      color: Colors.white),
                  tooltip: '画面比例 (${_aspectRatio.label})',
                  onPressed: _cycleAspectRatio,
                ),
                if (_playback.qualityOptions.length > 1)
                  PopupMenuButton<int>(
                    tooltip: '切换线路',
                    initialValue: _currentLineIndex,
                    onSelected: _selectLine,
                    itemBuilder: (context) => List.generate(
                      _playback.qualityOptions.length,
                      (i) => PopupMenuItem(
                        value: i,
                        child: Text(_playback.qualityOptions[i].label),
                      ),
                    ),
                    icon: const Icon(Icons.alt_route_rounded,
                        color: Colors.white),
                  ),
                IconButton(
                  icon: const Icon(Icons.help_outline_rounded,
                      color: Colors.white70),
                  tooltip: '快捷键与遥控指南 (H / ?)',
                  onPressed: () => _showShortcutHelpDialog(context),
                ),
                if (_canFullscreen)
                  IconButton(
                    icon: Icon(
                      _isFullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: Colors.white,
                    ),
                    tooltip: _isFullscreen ? '退出全屏' : '全屏',
                    onPressed: _toggleFullscreen,
                  ),
              ],
            ),
          ),
        ),

        // Bottom Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isLive && _duration > Duration.zero) ...[
                  Row(
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      Expanded(
                        child: Slider(
                          value: _position.inMilliseconds
                              .clamp(0, _duration.inMilliseconds)
                              .toDouble(),
                          max: _duration.inMilliseconds.toDouble(),
                          onChanged: (val) {
                            _player.seek(Duration(milliseconds: val.toInt()));
                          },
                        ),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: () => _player.playOrPause(),
                    ),
                    if (_canChooseEpisode) ...[
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded,
                            color: Colors.white),
                        tooltip: _isLive ? '上一频道 (↑)' : '上一集',
                        onPressed: _prevChannel,
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded,
                            color: Colors.white),
                        tooltip: _isLive ? '下一频道 (↓)' : '下一集',
                        onPressed: _nextChannel,
                      ),
                    ],
                    if (_isLive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fiber_manual_record,
                                color: Colors.white, size: 8),
                            SizedBox(width: 4),
                            Text(
                              '直播中',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (_canChooseEpisode)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          setState(() =>
                              _channelDrawerOpen = !_channelDrawerOpen);
                        },
                        icon: const Icon(Icons.tv_rounded, size: 18),
                        label: Text(_isLive ? '切台 / 频道列表' : '选集列表'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showShortcutHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.keyboard_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('键盘与遥控操作指南'),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _ShortcutRow('↑ / ↓', '切换上一频道 / 下一频道（或选集）'),
              _ShortcutRow('← / →', '快退 / 快进 10 秒（直播为切台）'),
              _ShortcutRow('空格 (Space)', '播放 / 暂停'),
              _ShortcutRow('回车 / Select', '呼出 / 关闭频道列表抽屉'),
              _ShortcutRow('数字键 0-9', '输入台号直跳频道（如 13 直达 CCTV-13）'),
              _ShortcutRow('A 键', '循环切换画幅比例 (自适应 / 16:9 / 4:3 / 铺满)'),
              _ShortcutRow('M 键', '一键静音 / 恢复音量'),
              _ShortcutRow('F 键', '切换全屏 / 退出全屏'),
              _ShortcutRow('H / ? 键', '查看本快捷键指南'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelDrawer() {
    final filteredEpisodes = _episodes.where((ep) {
      if (_drawerSearchFilter.isEmpty) return true;
      final q = _drawerSearchFilter.toLowerCase();
      return ep.title.toLowerCase().contains(q) ||
          ep.sourceEpisodeId.toLowerCase().contains(q);
    }).toList(growable: false);

    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      width: 320,
      child: GestureDetector(
        onTap: () {}, // Prevent taps inside drawer from closing it
        child: Container(
          color: const Color(0xF212151A),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        _isLive
                            ? Icons.live_tv_rounded
                            : Icons.video_library_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isLive
                            ? '频道列表 (${filteredEpisodes.length}/${_episodes.length})'
                            : '选集列表 (${_episodes.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white70),
                        onPressed: () =>
                            setState(() => _channelDrawerOpen = false),
                      ),
                    ],
                  ),
                ),
                if (_isLive && _episodes.length > 8)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        hintText: '搜索频道（如 1 或 CCTV）',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: _drawerSearchFilter.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () =>
                                    setState(() => _drawerSearchFilter = ''),
                              )
                            : null,
                      ),
                      onChanged: (val) =>
                          setState(() => _drawerSearchFilter = val.trim()),
                    ),
                  ),
                if (_playback.qualityOptions.length > 1) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    color: Colors.white10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('当前线路',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: List.generate(
                            _playback.qualityOptions.length,
                            (idx) {
                              final isSelected = idx == _currentLineIndex;
                              return ChoiceChip(
                                label: Text(
                                    _playback.qualityOptions[idx].label),
                                selected: isSelected,
                                onSelected: (_) => _selectLine(idx),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: filteredEpisodes.isEmpty
                      ? const Center(
                          child: Text(
                            '未找到匹配频道',
                            style: TextStyle(color: Colors.white60),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: filteredEpisodes.length,
                          itemBuilder: (context, index) {
                            final episode = filteredEpisodes[index];
                            final isSelected = episode.sourceEpisodeId ==
                                _currentEpisode?.sourceEpisodeId;
                            final originalIndex =
                                _episodes.indexOf(episode) + 1;
                            final numStr =
                                originalIndex.toString().padLeft(2, '0');
                            return ListTile(
                              selected: isSelected,
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.25),
                              leading: Container(
                                width: 32,
                                alignment: Alignment.center,
                                child: Text(
                                  numStr,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                        : Colors.white38,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              title: Text(
                                episode.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.volume_up_rounded,
                                      color: Colors.greenAccent, size: 20)
                                  : null,
                              onTap: () {
                                setState(() => _channelDrawerOpen = false);
                                _switchEpisode(episode);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        margin: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 52),
            const SizedBox(height: 16),
            const Text(
              '播放失败',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '$_error',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: _openCurrentStream,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
                if (_canChooseEpisode) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _nextChannel,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('切换下一频道'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showVolumeSlider() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '音量 ${(_volume * 100).round()}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: _volume,
                  onChanged: (val) {
                    setModalState(() => _volume = val);
                    _setVolume(val);
                  },
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.keyLabel, this.description);
  final String keyLabel;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              keyLabel,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.amberAccent,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}