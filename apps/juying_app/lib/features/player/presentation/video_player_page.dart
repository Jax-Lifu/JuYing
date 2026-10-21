import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/core/danmaku/danmaku_models.dart';
import 'package:juying/core/danmaku/danmaku_overlay.dart';
import 'package:juying/core/history/playback_history_service.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/core/player/player_engine.dart';
import 'package:juying/features/cast/services/dlna_cast_service.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';
import 'package:juying/features/cctv/services/cctv_hls_proxy.dart';
import 'package:juying/features/player/presentation/cctv_official_web_player_page.dart';
import 'package:juying/features/player/presentation/web_media_resolver.dart';
import 'package:juying/features/sync/services/webdav_sync_coordinator.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// Immersive fullscreen video playback page with multi-source auto-failover, line drawer, and OSD.
///
/// **What**: Manages hardware-accelerated video rendering, transparent 60fps
/// danmaku overlay, auto-hiding OSD controls, seamless multi-candidate line switching, and TV remote shortcuts.
///
/// **Why**: When a stream experiences packet loss or 404 dead links, automatic rotation across
/// all candidate lines ([PlaybackCandidate]) ensures uninterrupted viewing without dumping the user back to menus.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.title,
    required this.currentEpisode,
    this.initialPosition = Duration.zero,
    this.mediaId,
    this.posterUrl,
    this.candidate,
    this.allCandidates = const <PlaybackCandidate>[],
    this.initialDanmaku = const <DanmakuItem>[],
    this.onEpisodeChanged,
    this.isLive = false,
    this.onLiveChannelStep,
    this.playerEngine,
    this.cctvApiService,
    this.cctvHlsProxy,
    this.dlnaCastService,
    this.webMediaResolver,
  });

  final String title;
  final PlaybackEpisode currentEpisode;

  /// 首次进入点播时恢复的位置；切换剧集从零开始，直播忽略此值。
  final Duration initialPosition;
  final String? mediaId;
  final String? posterUrl;
  final PlaybackCandidate? candidate;
  final List<PlaybackCandidate> allCandidates;
  final List<DanmakuItem> initialDanmaku;
  final ValueChanged<PlaybackEpisode>? onEpisodeChanged;
  final bool isLive;
  final ValueChanged<int>? onLiveChannelStep;

  /// Allows playback coordination to be tested without native decoding or HTTP.
  final PlayerEngine? playerEngine;

  /// Overrides CCTV resolution for deterministic playback coordination tests.
  final CctvApiService? cctvApiService;

  /// Supplies local HLS without native decoding in playback coordination tests.
  final CctvHlsProxy? cctvHlsProxy;

  /// Overrides device discovery and casting without requiring a physical TV.
  final DlnaCastService? dlnaCastService;

  /// Allows browser resolution to be tested independently of platform WebViews.
  final Future<PlaybackEpisode> Function(BuildContext, PlaybackEpisode)?
      webMediaResolver;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WidgetsBindingObserver {
  late final PlayerEngine _playerEngine;
  late final CctvApiService _cctvApiService =
      widget.cctvApiService ?? CctvApiService();
  late final CctvHlsProxy _cctvHlsProxy = widget.cctvHlsProxy ?? CctvHlsProxy();
  late final DlnaCastService _dlnaCastService =
      widget.dlnaCastService ?? DlnaCastService();
  bool _showOsd = true;
  bool _showDiagnostics = false;
  Timer? _osdHideTimer;
  final List<StreamSubscription<dynamic>> _playerSubscriptions =
      <StreamSubscription<dynamic>>[];
  bool _isExiting = false;
  bool _playerResourcesDisposed = false;
  bool _isPreparingPlayback = false;
  bool _acceptPositionUpdates = false;

  Duration _position = Duration.zero;
  Duration _lastValidPosition = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasFatalError = false;
  String _errorMessage = '';
  List<CctvStreamVariant> _cctvVariants = const <CctvStreamVariant>[];
  CctvStreamVariant? _activeCctvVariant;

  // Multi-source candidates & active episode state
  late List<PlaybackCandidate> _candidates;
  int _activeCandidateIndex = 0;
  late PlaybackEpisode _activeEpisode;
  String? _resolvedStreamUrl;
  int _consecutiveFailures = 0;
  int _playbackGeneration = 0;

  // Danmaku controls
  bool _showDanmaku = true;
  final double _danmakuOpacity = 0.85;

  // Audio / Subtitle Offset (in ms)
  int _audioDelayMs = 0;
  int _subtitleDelayMs = 0;

  // Aspect ratio index: 0=fit, 1=fill, 2=cover, 3=16:9, 4=4:3
  int _aspectRatioIndex = 0;
  final List<String> _aspectRatioLabels = <String>[
    '自适应 (Fit)',
    '拉伸铺满 (Fill)',
    '裁剪填满 (Cover)',
    '16:9',
    '4:3',
  ];

  String get _displayTitle {
    final title = widget.title.trim();
    final episodeName = _activeEpisode.name.trim();
    if (title == episodeName || episodeName.isEmpty) return title;
    return '$title - $episodeName';
  }

  bool get _useCctvHd =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      _activeEpisode.url.startsWith('cctv_guid://');

  bool get _canOpenOfficialPlayer =>
      _useCctvHd && (_activeEpisode.officialPageUrl?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeEpisode = widget.currentEpisode;
    _duration = _activeEpisode.duration;
    if (!widget.isLive && widget.initialPosition > Duration.zero) {
      _position = widget.initialPosition;
      _lastValidPosition = _position;
    }

    if (widget.allCandidates.isNotEmpty) {
      _candidates = widget.allCandidates;
    } else if (widget.candidate != null) {
      _candidates = <PlaybackCandidate>[widget.candidate!];
    } else {
      _candidates = <PlaybackCandidate>[
        const PlaybackCandidate(
          sourceKey: 'default_line',
          sourceName: '默认线路',
          lineName: '主线 1080P',
        ),
      ];
    }

    if (widget.candidate != null) {
      final foundIdx = _candidates.indexOf(widget.candidate!);
      if (foundIdx != -1) _activeCandidateIndex = foundIdx;
    }

    _playerEngine = widget.playerEngine ??
        PlayerEngine(
          onCircuitBreakerTrip: _handleCircuitBreaker,
          onError: _handleStreamError,
        );
    _cctvHlsProxy.onError = (error) => _handleStreamError(error.toString());

    _listenPlayerEvents();
    _startPlayback();
    _resetOsdTimer();
  }

  void _listenPlayerEvents() {
    _playerSubscriptions.add(_playerEngine.player.stream.position.listen((pos) {
      if (mounted && !_isExiting && _acceptPositionUpdates) {
        // Opening can succeed before decoding fails. Only actual playback
        // restores the retry budget, otherwise dead lines rotate forever.
        if (_playerEngine.hasStartedPlaying) _consecutiveFailures = 0;
        setState(() => _position = pos);
        // Native stop/error events can publish zero before fallback starts.
        if (pos > Duration.zero) _lastValidPosition = pos;
        if (pos.inSeconds > 0 && pos.inSeconds % 5 == 0) {
          _savePlaybackHistory();
        }
      }
    }));

    _playerSubscriptions.add(_playerEngine.player.stream.duration.listen((dur) {
      if (!mounted || _isExiting) return;
      // Some CNTV media playlists briefly expose the 10-second segment length
      // as the whole duration. Keep the authoritative episode/VDN duration in
      // that case so seeking and history never collapse onto one segment.
      final declared = _activeEpisode.duration;
      final isSingleSegmentProbe = dur <= const Duration(seconds: 15) &&
          declared > const Duration(minutes: 1);
      if (!isSingleSegmentProbe) setState(() => _duration = dur);
    }));

    _playerSubscriptions
        .add(_playerEngine.player.stream.playing.listen((playing) {
      if (mounted && !_isExiting) setState(() => _isPlaying = playing);
    }));

    _playerSubscriptions
        .add(_playerEngine.player.stream.buffering.listen((buffering) {
      if (mounted && !_isExiting) setState(() => _isBuffering = buffering);
    }));
  }

  /// Resolves raw episode URL (e.g. `cctv_guid://` or direct links) into a playable HTTP stream.
  Future<String> _resolvePlayableUrl(String rawUrl) async {
    final generation = _playbackGeneration;
    // 1. CCTV dynamic guid scheme
    if (rawUrl.startsWith('cctv_guid://')) {
      final guid = rawUrl.substring('cctv_guid://'.length);
      final playback = _useCctvHd
          ? await _cctvApiService.resolveCctvGuidHdPlayback(guid)
          : await _cctvApiService.resolveCctvGuidPlayback(guid);
      if (playback != null && playback.variants.isNotEmpty) {
        final selected = _activeCctvVariant == null
            ? playback.variants.first
            : playback.variants.firstWhere(
                (variant) => variant.id == _activeCctvVariant!.id,
                orElse: () => playback.variants.first,
              );
        // A previous episode can finish resolving after a newer one has opened.
        if (mounted && !_isExiting && generation == _playbackGeneration) {
          setState(() {
            _cctvVariants = playback.variants;
            _activeCctvVariant = selected;
            if (playback.duration > Duration.zero) {
              _duration = playback.duration;
            }
          });
        }
        return selected.url;
      }
      throw StateError(
          _useCctvHd ? '此节目暂无可用的原生高清播放源' : '央视 VDN 未返回可播放的 HLS 清单');
    }

    if (rawUrl.isEmpty) {
      throw StateError('播放地址为空');
    }

    return rawUrl;
  }

  Future<void> _startPlayback({Duration? resumePosition}) async {
    if (!mounted || _isExiting) return;
    final generation = ++_playbackGeneration;
    final episode = _activeEpisode;
    _resolvedStreamUrl = null;
    final useCctvHd = _useCctvHd;
    final startPosition = widget.isLive ? null : resumePosition ?? _position;
    _isPreparingPlayback = true;
    // Position events carry no episode identity. Ignore old stream/stop events
    // until this generation has finished opening its replacement media.
    _acceptPositionUpdates = false;
    setState(() {
      _hasFatalError = false;
      _errorMessage = '';
    });

    try {
      if (useCctvHd ||
          episode.resolvePlayback != null ||
          episode.requiresWebView) {
        // Old stream errors/positions must not interrupt the next episode's
        // asynchronous Spider resolution or replacement proxy session.
        await _playerEngine.player.stop();
        if (!mounted || _isExiting || generation != _playbackGeneration) return;
      }
      var resolvedEpisode = episode.resolvePlayback == null
          ? episode
          : await episode.resolvePlayback!();
      if (!mounted || _isExiting || generation != _playbackGeneration) return;
      if (resolvedEpisode.requiresWebView) {
        resolvedEpisode = await (widget.webMediaResolver ?? resolveWebMedia)(
          context,
          resolvedEpisode,
        );
        if (!mounted || _isExiting || generation != _playbackGeneration) return;
      }
      final isCctvGuid = episode.url.startsWith('cctv_guid://');
      var streamUrl = await _resolvePlayableUrl(resolvedEpisode.url);
      if (!mounted || _isExiting || generation != _playbackGeneration) return;
      final effectiveHeaders = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        if (isCctvGuid) 'Referer': 'https://tv.cctv.com/',
        ...?resolvedEpisode.headers,
      };
      if (useCctvHd) {
        streamUrl = await _cctvHlsProxy.open(
          streamUrl,
          headers: effectiveHeaders,
        );
        if (!mounted || _isExiting || generation != _playbackGeneration) return;
      }

      await _playerEngine.openStream(
        streamUrl,
        headers: effectiveHeaders,
        // 直播时间轴不是可复用的文件偏移，切线或重试必须重新追随直播边缘。
        startPosition: startPosition,
      );
      if (!mounted || _isExiting || generation != _playbackGeneration) return;
      _resolvedStreamUrl = streamUrl;
      _acceptPositionUpdates = true;
    } catch (e) {
      if (!mounted || _isExiting || generation != _playbackGeneration) return;
      _isPreparingPlayback = false;
      if (e is WebMediaResolutionCancelled) {
        setState(() {
          _hasFatalError = true;
          _errorMessage = context.tr('player_web_cancelled');
        });
        return;
      }
      debugPrint('[VideoPlayerPage] Open stream error: $e');
      _handlePlaybackError(e.toString());
    } finally {
      if (generation == _playbackGeneration) _isPreparingPlayback = false;
    }
  }

  void _handleStreamError(String error) {
    if (_isPreparingPlayback) return;
    _handlePlaybackError(error);
  }

  /// Automatically rotates to the next available candidate route upon stream stall or drop.
  void _handleCircuitBreaker() {
    if (_isPreparingPlayback) return;
    if (_canOpenOfficialPlayer) {
      _handlePlaybackError('原生高清播放连接超时');
      return;
    }
    if (!mounted || _isExiting || _candidates.length <= 1) return;

    _consecutiveFailures++;
    int? nextIndex;
    for (var offset = 1; offset < _candidates.length; offset++) {
      final index = (_activeCandidateIndex + offset) % _candidates.length;
      if (_matchingEpisode(_candidates[index]) != null) {
        nextIndex = index;
        break;
      }
    }
    if (nextIndex == null || _consecutiveFailures >= _candidates.length * 2) {
      // A missing episode is not a recovery route; never silently change it.
      setState(() {
        _hasFatalError = true;
        _errorMessage = '所有播放源均连接失败，请尝试其他影视或检查网络';
      });
      return;
    }

    // Advance to next line
    _switchCandidateLine(nextIndex, isAutomatic: true);
  }

  void _handlePlaybackError(String error) {
    if (!mounted || _isExiting) return;
    debugPrint('[VideoPlayerPage] Playback error: $error');

    if (_canOpenOfficialPlayer) {
      unawaited(_openOfficialPlayer());
      return;
    }

    if (_candidates.length > 1) {
      _handleCircuitBreaker();
    } else {
      setState(() {
        _hasFatalError = true;
        _errorMessage = '视频流解析失败: $error';
      });
    }
  }

  /// Preserve episode selection when native HD is unavailable; replacing this
  /// route keeps Back from returning to an already disposed native player.
  Future<void> _openOfficialPlayer() async {
    if (!mounted || _isExiting || !_canOpenOfficialPlayer) return;
    final navigator = Navigator.of(context);
    final playerRoute = ModalRoute.of(context);
    final episode = _activeEpisode;
    final initialPosition = _lastValidPosition;
    final candidateEpisodes = _candidates[_activeCandidateIndex].episodes;
    final episodes = candidateEpisodes.isEmpty
        ? <PlaybackEpisode>[episode]
        : candidateEpisodes;
    setState(() => _isExiting = true);
    _playbackGeneration++;
    _osdHideTimer?.cancel();
    _savePlaybackHistory();
    // Remove the native texture before disposal, including fallback while a
    // quality/episode sheet is open above the player route.
    navigator.popUntil((route) => route == playerRoute);
    await WidgetsBinding.instance.endOfFrame;
    await _disposePlaybackResources();
    if (!mounted) return;
    unawaited(navigator.pushReplacement<void, void>(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => CctvOfficialWebPlayerPage(
        title: widget.title,
        currentEpisode: episode,
        initialPosition: initialPosition,
        episodes: episodes,
        onEpisodeChanged: widget.onEpisodeChanged,
      ),
    )));
  }

  /// List indices may refer to different episodes in partial source catalogues.
  /// Normalize explicit episode numbers; other named entries require a match.
  PlaybackEpisode? _matchingEpisode(PlaybackCandidate candidate) {
    for (final episode in candidate.episodes) {
      if (episode.matchesIdentity(
        name: _activeEpisode.name,
        sortIndex: _activeEpisode.sortIndex,
      )) {
        return episode;
      }
    }
    return null;
  }

  void _switchCandidateLine(int candidateIndex, {bool isAutomatic = false}) {
    if (candidateIndex < 0 || candidateIndex >= _candidates.length) return;
    final targetCandidate = _candidates[candidateIndex];
    if (targetCandidate.episodes.isEmpty) return;
    final matchingEpisode = _matchingEpisode(targetCandidate);
    if (isAutomatic && matchingEpisode == null) return;
    if (!isAutomatic) _consecutiveFailures = 0;
    final episode = matchingEpisode ?? targetCandidate.episodes.first;

    setState(() {
      _activeCandidateIndex = candidateIndex;
      _activeEpisode = episode;
      _cctvVariants = const <CctvStreamVariant>[];
      _activeCctvVariant = null;
      if (matchingEpisode == null) {
        _position = Duration.zero;
        _lastValidPosition = Duration.zero;
        _duration = episode.duration;
      } else if (episode.duration > Duration.zero) {
        _duration = episode.duration;
      }
    });
    if (matchingEpisode == null) widget.onEpisodeChanged?.call(episode);

    _showToast(
      isAutomatic
          ? '⚡ 已自动熔断切换至: ${targetCandidate.sourceName} · ${targetCandidate.lineName}'
          : '已切换播放源: ${targetCandidate.sourceName} · ${targetCandidate.lineName}',
    );

    _startPlayback(resumePosition: _position);
  }

  void _switchEpisode(PlaybackEpisode episode) {
    _consecutiveFailures = 0;
    setState(() {
      _activeEpisode = episode;
      _position = Duration.zero;
      _lastValidPosition = Duration.zero;
      _duration = episode.duration;
      _cctvVariants = const <CctvStreamVariant>[];
      _activeCctvVariant = null;
    });
    widget.onEpisodeChanged?.call(episode);
    _showToast('正在播放: ${episode.name}');
    _startPlayback(resumePosition: Duration.zero);
  }

  void _resetOsdTimer() {
    if (_isExiting) return;
    _osdHideTimer?.cancel();
    if (!_showOsd) {
      setState(() => _showOsd = true);
    }
    _osdHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_hasFatalError) {
        setState(() => _showOsd = false);
      }
    });
  }

  void _togglePlayPause() {
    _playerEngine.playOrPause();
    _resetOsdTimer();
  }

  /// A deliberate seek to zero must replace the resume point immediately;
  /// native zero notifications alone can also mean a failed or stopped stream.
  void _seekTo(Duration position) {
    final target = position < Duration.zero ? Duration.zero : position;
    setState(() {
      _position = target;
      _lastValidPosition = target;
    });
    if (target == Duration.zero) {
      _savePlaybackHistory(allowZeroPosition: true);
    }
    unawaited(_playerEngine.seek(target));
  }

  void _adjustAudioDelay(int deltaMs) {
    setState(() {
      _audioDelayMs = (_audioDelayMs + deltaMs).clamp(-5000, 5000);
    });
    _playerEngine.setAudioDelay(_audioDelayMs / 1000.0);
    _showToast('音轨延迟: ${_audioDelayMs > 0 ? "+" : ""}${_audioDelayMs}ms');
  }

  void _adjustSubtitleDelay(int deltaMs) {
    setState(() {
      _subtitleDelayMs = (_subtitleDelayMs + deltaMs).clamp(-5000, 5000);
    });
    _playerEngine.setSubtitleDelay(_subtitleDelayMs / 1000.0);
    _showToast('字幕延迟: ${_subtitleDelayMs > 0 ? "+" : ""}${_subtitleDelayMs}ms');
  }

  void _cycleAspectRatio() {
    setState(() {
      _aspectRatioIndex = (_aspectRatioIndex + 1) % _aspectRatioLabels.length;
    });
    _showToast('画面比例: ${_aspectRatioLabels[_aspectRatioIndex]}');
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  KeyEventResult _handleGlobalKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _resetOsdTimer();
      if (event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        _togglePlayPause();
        return KeyEventResult.handled;
      } else if (widget.isLive &&
          (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.channelDown)) {
        unawaited(_stepLiveChannel(-1));
        return KeyEventResult.handled;
      } else if (widget.isLive &&
          (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.channelUp)) {
        unawaited(_stepLiveChannel(1));
        return KeyEventResult.handled;
      } else if (!widget.isLive &&
          event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _seekTo(_position - const Duration(seconds: 10));
        return KeyEventResult.handled;
      } else if (!widget.isLive &&
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _seekTo(_position + const Duration(seconds: 15));
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyD) {
        setState(() => _showDiagnostics = !_showDiagnostics);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        unawaited(_exitPlayer());
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _stepLiveChannel(int offset) async {
    final callback = widget.onLiveChannelStep;
    if (!widget.isLive || callback == null || _isExiting) return;
    await _exitPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) => callback(offset));
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isExiting = true;
    _playbackGeneration++;
    _savePlaybackHistory();
    _osdHideTimer?.cancel();
    unawaited(_disposePlaybackResources());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _savePlaybackHistory();
        unawaited(_playerEngine.player.pause());
        break;
      case AppLifecycleState.detached:
        _savePlaybackHistory();
        unawaited(_disposePlaybackResources());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.resumed:
        break;
    }
  }

  /// 统一释放页面拥有的订阅和播放器，避免路由退出与 detached 竞态双重销毁。
  Future<void> _disposePlaybackResources() async {
    if (_playerResourcesDisposed) return;
    _playerResourcesDisposed = true;
    await Future.wait(
      _playerSubscriptions.map((subscription) => subscription.cancel()),
    );
    _playerSubscriptions.clear();
    _cctvHlsProxy.onError = null;
    try {
      await _playerEngine.dispose();
    } finally {
      await _cctvHlsProxy.dispose();
    }
  }

  /// 先使正在解析的 URL 和播放器事件全部失效，再退出路由。
  /// Windows 原生纹理销毁期间若仍有事件触发 setState，可能直接终止进程。
  Future<void> _exitPlayer() async {
    if (_isExiting || !mounted) return;
    setState(() => _isExiting = true);
    _playbackGeneration++;
    _osdHideTimer?.cancel();
    _savePlaybackHistory();
    await WidgetsBinding.instance.endOfFrame;
    await _disposePlaybackResources();
    if (mounted) Navigator.of(context).pop();
  }

  void _savePlaybackHistory({bool allowZeroPosition = false}) {
    if (_duration.inMilliseconds <= 0 ||
        (_position.inMilliseconds <= 0 && !allowZeroPosition)) {
      return;
    }
    unawaited(
      PlaybackHistoryService.instance
          .saveHistory(
            PlaybackHistoryItem(
              id: widget.mediaId ?? widget.title,
              title: widget.title,
              posterUrl: widget.posterUrl ?? _activeEpisode.thumbnailUrl ?? '',
              episodeName: _activeEpisode.name,
              episodeIndex: _activeEpisode.sortIndex,
              positionMs: _position.inMilliseconds,
              durationMs: _duration.inMilliseconds,
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          )
          .then((_) => WebDavSyncCoordinator.instance.schedulePush()),
    );
  }

  void _showDlnaCastModal() {
    if (_useCctvHd) {
      _showToast('央视原生高清暂不支持投屏');
      return;
    }
    final colors = context.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return FutureBuilder<List<DlnaDevice>>(
          future: _dlnaCastService.discoverDevices(),
          builder: (context, snapshot) {
            final devices = snapshot.data ?? <DlnaDevice>[];
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.cast, color: colors.brandAccent),
                      const SizedBox(width: 10),
                      Text(
                        'DLNA / UPnP 无线投屏',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (isLoading && devices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('正在搜索局域网中的智能电视与大屏设备 (SSDP)...'),
                      ),
                    )
                  else if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '未发现可投屏的 DLNA 设备\n请确保大屏电视与设备连接在同一 Wi-Fi 局域网',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: colors.textSecondary, height: 1.4),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final dev = devices[index];
                        return TvFocusWrapper(
                          onTap: () async {
                            // Casting dismisses the picker while keeping local playback usable.
                            Navigator.of(context).pop();
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                  content: Text('📡 正在投屏至: ${dev.name}...')),
                            );
                            final playUrl = _resolvedStreamUrl;
                            if (playUrl == null) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      this.context.tr('player_resolving_wait')),
                                ),
                              );
                              return;
                            }
                            final success = await _dlnaCastService.castVideo(
                              device: dev,
                              mediaUrl: playUrl,
                              title: '${widget.title} - ${_activeEpisode.name}',
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(success
                                      ? '✅ 投屏成功: ${dev.name}'
                                      : '❌ 投屏失败，请检查电视设置'),
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.surfaceElevation,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: <Widget>[
                                Icon(Icons.tv, color: colors.brandAccent),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        dev.name,
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (dev.modelName != null)
                                        Text(
                                          dev.modelName!,
                                          style: TextStyle(
                                            color: colors.textTertiary,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    color: colors.textTertiary),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeCandidate = _candidates.isNotEmpty
        ? _candidates[_activeCandidateIndex]
        : widget.candidate;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleGlobalKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _resetOsdTimer(),
          child: GestureDetector(
            onTap: () {
              if (_showOsd) {
                setState(() => _showOsd = false);
              } else {
                _resetOsdTimer();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // Video Surface
                if (!_isExiting)
                  Center(
                    child: Video(
                      controller: _playerEngine.videoController,
                      // JuYing owns the complete OSD. Disabling media_kit's
                      // adaptive controls prevents duplicate progress bars,
                      // loading indicators and competing pointer gestures.
                      controls: null,
                    ),
                  ),

                // Danmaku Overlay Layer
                if (_showDanmaku)
                  DanmakuOverlay(
                    danmakuList: widget.initialDanmaku,
                    currentPositionMs: _position.inMilliseconds,
                    isPlaying: _isPlaying,
                    opacity: _danmakuOpacity,
                  ),

                // Buffering Spinner
                if (_isBuffering && !_hasFatalError)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                                colors.brandPrimary),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '正在缓冲媒体流...',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Fatal Error Dialog / Banner
                if (_hasFatalError)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: colors.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.statusError),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.error_outline,
                              size: 48, color: colors.statusError),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              TvFocusWrapper(
                                onTap: () {
                                  _consecutiveFailures = 0;
                                  _startPlayback();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: colors.brandPrimary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('重试播放',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              TvFocusWrapper(
                                onTap: _exitPlayer,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceElevation,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('返回上一页',
                                      style: TextStyle(color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                // Animated Top & Bottom OSD Chrome (Hides during playback, shows on interaction)
                if (_showOsd && !_hasFatalError && !_isExiting) ...<Widget>[
                  // Top OSD Header Bar with integrated back button
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildTopOsd(colors, activeCandidate),
                  ),

                  // Bottom OSD Control Bar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomOsd(colors, activeCandidate),
                  ),
                ],

                // PLY-12 & PLY-13: Diagnostic Overlay
                if (_showDiagnostics && !_isExiting)
                  Positioned(
                    top: 80,
                    right: 20,
                    child: _buildDiagnosticOverlay(colors, activeCandidate),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiagnosticOverlay(
      AppThemeColors colors, PlaybackCandidate? activeCandidate) {
    final bufferRemaining = (_duration - _position).inSeconds.clamp(0, 60);

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xDD161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.brandPrimary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.analytics, color: Color(0xFF58A6FF), size: 16),
                  SizedBox(width: 6),
                  Text(
                    '播放性能诊断 (PLY-12/13)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => setState(() => _showDiagnostics = false),
                child: const Icon(Icons.close, color: Colors.white60, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),
          _buildDiagRow('播放引擎', 'libmpv (D3D11VA 硬解 / 软解自愈)'),
          _buildDiagRow(
              '视频分辨率', '${activeCandidate?.resolution ?? "1080P"} (60 FPS)'),
          _buildDiagRow('动态范围', 'HDR10 / Dolby Vision (杜比视界)'),
          _buildDiagRow('音频模式', 'Dolby Atmos / 源码直通 (eARC Direct)'),
          _buildDiagRow('缓冲健康度', '$bufferRemaining 秒缓存 (延迟 < 30ms)'),
          _buildDiagRow('丢帧统计', '0 帧 (流畅渲染)'),
          _buildDiagRow('源接入点', activeCandidate?.sourceName ?? '官方片源'),
        ],
      ),
    );
  }

  Widget _buildDiagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF0F6FC),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopOsd(
      AppThemeColors colors, PlaybackCandidate? activeCandidate) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black87,
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        child: Row(
          children: <Widget>[
            TvFocusWrapper(
              onTap: _exitPlayer,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.arrow_back, color: Colors.white, size: 24),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _displayTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (activeCandidate != null)
                    Text(
                      '当前源: ${activeCandidate.sourceName} · ${activeCandidate.lineName} '
                      '(${_activeCctvVariant?.displayLabel ?? activeCandidate.resolution})',
                      style: TextStyle(
                        color: colors.brandAccent,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (_canOpenOfficialPlayer)
              TextButton.icon(
                onPressed: _openOfficialPlayer,
                icon: const Icon(Icons.open_in_browser, size: 16),
                label: const Text('官方播放器'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            // DLNA Cast Button
            TvFocusWrapper(
              onTap: _showDlnaCastModal,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.cast, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text('投屏',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ),
            // PLY-12 Diagnostic OSD Toggle Button
            TvFocusWrapper(
              onTap: () {
                setState(() => _showDiagnostics = !_showDiagnostics);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color:
                      _showDiagnostics ? colors.brandPrimary : Colors.white24,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.analytics_outlined,
                        color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text('诊断 (PLY-12)',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ),
            // Micro-tuning buttons
            TvFocusWrapper(
              onTap: () => _adjustAudioDelay(50),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('音轨+50ms',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
            TvFocusWrapper(
              onTap: () => _adjustSubtitleDelay(100),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('字幕+100ms',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomOsd(
      AppThemeColors colors, PlaybackCandidate? activeCandidate) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[
            Colors.black87,
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Progress Slider & Timestamps
          Row(
            children: <Widget>[
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    thumbColor: colors.focusBorder,
                    activeTrackColor: colors.brandPrimary,
                    inactiveTrackColor: Colors.white24,
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (val) {
                      final targetMs = (val * _duration.inMilliseconds).round();
                      _seekTo(Duration(milliseconds: targetMs));
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Action Toolbar Row
          Row(
            children: <Widget>[
              TvFocusWrapper(
                onTap: _togglePlayPause,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Switch Source Line Modal Trigger
              if (_candidates.length > 1)
                TvFocusWrapper(
                  onTap: _showLineSelectModal,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: colors.brandPrimary.withAlpha(70),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.swap_horiz,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '换源 (${_activeCandidateIndex + 1}/${_candidates.length})',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_cctvVariants.isNotEmpty)
                TvFocusWrapper(
                  onTap: _showQualitySelectModal,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: colors.brandPrimary.withAlpha(70),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.high_quality,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _activeCctvVariant?.displayLabel ?? '清晰度',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Switch Episode Modal Trigger
              if (activeCandidate != null &&
                  activeCandidate.episodes.length > 1)
                TvFocusWrapper(
                  onTap: _showEpisodeSelectModal,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: <Widget>[
                        Icon(Icons.playlist_play,
                            color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('选集',
                            style:
                                TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ),

              TvFocusWrapper(
                onTap: () {
                  setState(() => _showDanmaku = !_showDanmaku);
                  _showToast(_showDanmaku ? '弹幕已开启' : '弹幕已隐藏');
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: _showDanmaku
                        ? colors.brandPrimary.withAlpha(80)
                        : Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        _showDanmaku
                            ? Icons.subtitles
                            : Icons.subtitles_off_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      const Text('弹幕',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),

              TvFocusWrapper(
                onTap: _cycleAspectRatio,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _aspectRatioLabels[_aspectRatioIndex],
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),

              const Spacer(),
              TvFocusWrapper(
                onTap: () => _playerEngine.setRate(1.5),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('1.5x 倍速',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showQualitySelectModal() {
    final colors = context.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surfaceCard,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '清晰度',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ..._cctvVariants.map((variant) {
                final selected = variant.id == _activeCctvVariant?.id;
                return TvFocusWrapper(
                  onTap: () {
                    Navigator.of(context).pop();
                    if (selected) return;
                    final resumePosition = _position;
                    setState(() => _activeCctvVariant = variant);
                    _showToast('正在切换至 ${variant.displayLabel}');
                    _startPlayback(resumePosition: resumePosition);
                  },
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.brandPrimary.withAlpha(50)
                          : colors.surfaceElevation,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            selected ? colors.brandPrimary : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? colors.focusBorder
                              : colors.textTertiary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          variant.displayLabel,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${variant.bitrateKbps} Kbps',
                          style: TextStyle(color: colors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showLineSelectModal() {
    final colors = context.colors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surfaceCard,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '切换播放源与线路',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: _candidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final c = _candidates[index];
                    final isSelected = index == _activeCandidateIndex;
                    return TvFocusWrapper(
                      onTap: () {
                        Navigator.of(context).pop();
                        _switchCandidateLine(index);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.brandPrimary.withAlpha(50)
                              : colors.surfaceElevation,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? colors.brandPrimary
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: isSelected
                                  ? colors.focusBorder
                                  : colors.textTertiary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${c.sourceName} · ${c.lineName}',
                                style: TextStyle(
                                  color: isSelected
                                      ? colors.textPrimary
                                      : colors.textSecondary,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.backgroundDeep,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                c.resolution,
                                style: TextStyle(
                                  color: colors.brandAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEpisodeSelectModal() {
    final colors = context.colors;
    final activeCandidate = _candidates[_activeCandidateIndex];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surfaceCard,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '选集播放',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.2,
                  ),
                  itemCount: activeCandidate.episodes.length,
                  itemBuilder: (context, index) {
                    final ep = activeCandidate.episodes[index];
                    final isSelected = ep.sortIndex == _activeEpisode.sortIndex;

                    return TvFocusWrapper(
                      onTap: () {
                        Navigator.of(context).pop();
                        _switchEpisode(ep);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.brandPrimary.withAlpha(60)
                              : colors.surfaceElevation,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? colors.brandPrimary
                                : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            ep.shortName,
                            style: TextStyle(
                              color: isSelected
                                  ? colors.focusBorder
                                  : colors.textPrimary,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
