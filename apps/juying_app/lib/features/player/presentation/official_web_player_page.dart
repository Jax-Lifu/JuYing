import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../application/playback/playback_history_store.dart';
import '../../../application/playback/playback_preference_store.dart';
import '../../../application/playback/playback_telemetry.dart';
import '../../../application/profiles/child_usage_store.dart';
import '../../../core/platform/window_controls.dart';
import '../../../domain/models/media_source.dart';
import '../../../domain/models/unified_media.dart';

/// Windows 平台的官方播放回退页。
///
/// 该页面只接收已由来源适配器校验过的官网详情页，不提取、拼接或改写
/// 播放地址；官网负责选择它允许在当前终端使用的清晰度和播放链路。
class OfficialWebPlayerPage extends StatefulWidget {
  const OfficialWebPlayerPage({
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
  final Future<PlaybackDescriptor> Function(MediaEpisode episode)
      resolveEpisode;
  final String profileId;
  final Set<SourceCapability> sourceCapabilities;
  final int? childDailyLimitMinutes;
  final WindowControls windowControls;
  final PlaybackTelemetry? telemetry;

  @override
  State<OfficialWebPlayerPage> createState() => _OfficialWebPlayerPageState();
}

class _OfficialWebPlayerPageState extends State<OfficialWebPlayerPage> {
  final WebviewController _controller = WebviewController();
  final PlaybackPreferenceStore _preferenceStore = PlaybackPreferenceStore();
  final PlaybackHistoryStore _historyStore = PlaybackHistoryStore();
  final ChildUsageStore _childUsageStore = ChildUsageStore();
  late final PlaybackTelemetry _telemetry =
      widget.telemetry ?? PlaybackTelemetry.shared;
  StreamSubscription<dynamic>? _webMessageSubscription;
  ScriptID? _documentScriptId;
  Timer? _playerReadyTimeout;
  var _isWebviewLoaded = false;
  var _isPlayerReady = false;
  Object? _error;
  late PlaybackDescriptor _playback = widget.playback;
  String? _preferredQuality;
  String? _lastAppliedQuality;
  var _preferredSpeed = 1.0;
  var _preferredVolume = 1.0;
  var _isFullscreen = false;
  late final PlayerFullscreenSession _fullscreenSession =
      PlayerFullscreenSession(widget.windowControls);
  var _lastPosition = Duration.zero;
  Duration? _lastDuration;
  var _lastUsagePosition = Duration.zero;
  var _timeLimitReached = false;

  bool get _canChooseQuality =>
      widget.sourceCapabilities.contains(SourceCapability.qualitySelection);
  bool get _canChangeSpeed =>
      widget.sourceCapabilities.contains(SourceCapability.playbackSpeed);
  bool get _canChangeVolume =>
      widget.sourceCapabilities.contains(SourceCapability.volumeControl);
  bool get _canFullscreen =>
      widget.sourceCapabilities.contains(SourceCapability.fullscreen);
  bool get _canChooseEpisode =>
      widget.sourceCapabilities.contains(SourceCapability.episodes);
  bool get _canContinueWatching =>
      widget.sourceCapabilities.contains(SourceCapability.continueWatching);
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _recordTelemetry(PlaybackTelemetryEvent.opening);
      if (await _hasReachedChildLimit()) {
        if (mounted) setState(() => _timeLimitReached = true);
        return;
      }
      final preferences = await _preferenceStore.load(
        profileId: widget.profileId,
        sourceId: _playback.sourceId,
      );
      _preferredQuality = _canChooseQuality ? preferences.qualityId : null;
      _preferredSpeed = preferences.speed;
      _preferredVolume = preferences.volume;
      if (widget.sourceCapabilities.contains(SourceCapability.liveCatalog)) {
        unawaited(_preferenceStore.saveLastLiveChannel(
          profileId: widget.profileId,
          sourceId: _playback.sourceId,
          channelId: _playback.sourceEpisodeId,
        ));
      }
      final resumePosition = await _loadResumePosition();
      _lastPosition = resumePosition;
      _lastUsagePosition = resumePosition;
      final version = await WebviewController.getWebViewVersion();
      if (version == null) {
        throw StateError('此电脑未安装 Microsoft Edge WebView2 Runtime');
      }
      await _controller.initialize();
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _setDocumentScript(resumePosition);
      _webMessageSubscription = _controller.webMessage.listen((message) {
        if (message == 'juying:exit-official-player' && mounted) {
          Navigator.of(context).maybePop();
        }
        if (message == 'juying:official-player-ready' && mounted) {
          _playerReadyTimeout?.cancel();
          setState(() => _isPlayerReady = true);
          _recordTelemetry(PlaybackTelemetryEvent.ready);
        }
        if (message is Map &&
            message['type'] == 'juying:official-player-unavailable' &&
            mounted &&
            !_isPlayerReady) {
          _playerReadyTimeout?.cancel();
          final reason = message['reason'] is String
              ? message['reason'] as String
              : 'unknown';
          _recordTelemetry(PlaybackTelemetryEvent.failed,
              errorCode: 'official_dom_$reason');
          setState(
            () => _error = StateError('官网播放器未就绪，请重试或在浏览器中打开'),
          );
        }
        if (message == 'juying:episode-ended' &&
            mounted &&
            !_timeLimitReached) {
          _recordTelemetry(PlaybackTelemetryEvent.ended);
          unawaited(_playNextEpisode());
        }
        if (message is Map &&
            message['type'] == 'juying:quality-applied' &&
            message['value'] is String) {
          if (_canChooseQuality) {
            final quality = message['value'] as String;
            if (_lastAppliedQuality != quality) {
              _lastAppliedQuality = quality;
              _recordTelemetry(PlaybackTelemetryEvent.qualityChanged);
            }
            _savePreferredQuality(quality);
          }
        }
        if (message is Map && message['type'] == 'juying:progress') {
          final positionMs = (message['positionMs'] as num?)?.toInt();
          final durationMs = (message['durationMs'] as num?)?.toInt();
          if (positionMs != null && positionMs >= 0) {
            unawaited(_handleProgress(
              Duration(milliseconds: positionMs),
              duration: durationMs == null || durationMs <= 0
                  ? null
                  : Duration(milliseconds: durationMs),
            ));
          }
        }
      });
      await _controller.loadUrl(_playback.officialPageUri.toString());
      if (mounted) {
        setState(() {
          _isWebviewLoaded = true;
          _isPlayerReady = false;
        });
        _armPlayerReadyTimeout();
      }
    } catch (error) {
      _playerReadyTimeout?.cancel();
      _recordTelemetry(PlaybackTelemetryEvent.failed,
          errorCode: 'official_initialize');
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _playerReadyTimeout?.cancel();
    if (_canContinueWatching) {
      unawaited(_recordProgress(_lastPosition, duration: _lastDuration));
    }
    unawaited(_fullscreenSession.dispose());
    unawaited(_webMessageSubscription?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _openInBrowser() async {
    final opened = await launchUrl(
      _playback.officialPageUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开 CCTV 官网')),
      );
    }
  }

  Future<void> _savePreferredQuality(String label) async {
    final qualityId = _qualityIdForLabel(label);
    if (qualityId == null) return;
    _preferredQuality = qualityId;
    await _preferenceStore.update(
      profileId: widget.profileId,
      sourceId: _playback.sourceId,
      qualityId: qualityId,
    );
  }

  String? _qualityLabelForPreference() {
    const labels = {
      'official.uhd': '超清',
      'official.hd': '高清',
      'official.sd': '标清',
      'official.smooth': '流畅',
    };
    // 兼容旧版本按中文文案保存的偏好，成功切换后会迁移为稳定 ID。
    return labels[_preferredQuality] ?? _preferredQuality;
  }

  String? _qualityIdForLabel(String label) => switch (label) {
        '超清' => 'official.uhd',
        '高清' => 'official.hd',
        '标清' => 'official.sd',
        '流畅' => 'official.smooth',
        _ => null,
      };

  Future<void> _setSpeed(double speed) async {
    setState(() => _preferredSpeed = speed);
    await _preferenceStore.update(
      profileId: widget.profileId,
      sourceId: _playback.sourceId,
      speed: speed,
    );
    await _controller.executeScript(_videoCommand('playbackRate = $speed'));
  }

  Future<void> _setVolume(double volume) async {
    setState(() => _preferredVolume = volume);
    await _preferenceStore.update(
      profileId: widget.profileId,
      sourceId: _playback.sourceId,
      volume: volume,
    );
    await _controller.executeScript(_videoCommand('volume = $volume'));
  }

  String _videoCommand(String command) =>
      "document.querySelector('#_video_player_html5_api, video.vjs-tech, video')?.$command;";

  Future<void> _showVolumePicker() async {
    var candidate = _preferredVolume;
    final selected = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('音量 ${((candidate * 100).round())}%',
                  style: Theme.of(context).textTheme.titleMedium),
              Slider(
                value: candidate,
                onChanged: (value) => setModalState(() => candidate = value),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, candidate),
                child: const Text('确定'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (selected != null) await _setVolume(selected);
  }

  Future<void> _recordProgress(
    Duration position, {
    Duration? duration,
  }) async {
    if (!_canContinueWatching) return;
    _lastPosition = position;
    _lastDuration = duration ?? _lastDuration;
    await _historyStore.record(
      playback: _playback,
      position: _lastPosition,
      duration: _lastDuration,
      profileId: widget.profileId,
    );
  }

  Future<Duration> _loadResumePosition() async {
    if (!_canContinueWatching) return Duration.zero;
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

  Future<void> _setDocumentScript(Duration resumePosition) async {
    final previous = _documentScriptId;
    if (previous != null) {
      await _controller.removeScriptToExecuteOnDocumentCreated(previous);
    }
    _documentScriptId = await _controller.addScriptToExecuteOnDocumentCreated(
      _documentScriptFor(
        _qualityLabelForPreference(),
        resumePosition,
        speed: _preferredSpeed,
        volume: _preferredVolume,
      ),
    );
  }

  Future<bool> _hasReachedChildLimit() async {
    final limit = widget.childDailyLimitMinutes;
    if (limit == null) return false;
    final used = await _childUsageStore.consumedToday(widget.profileId);
    return used >= Duration(minutes: limit);
  }

  Future<void> _handleProgress(
    Duration position, {
    Duration? duration,
  }) async {
    await _recordProgress(position, duration: duration);
    final limit = widget.childDailyLimitMinutes;
    if (limit == null || _timeLimitReached) {
      _lastUsagePosition = position;
      return;
    }
    final delta = position - _lastUsagePosition;
    _lastUsagePosition = position;
    // 每 5 秒上报一次。超过 15 秒的跳跃视为拖动进度，不计入儿童时长。
    if (delta <= Duration.zero || delta > const Duration(seconds: 15)) return;
    final used = await _childUsageStore.addWatchTime(widget.profileId, delta);
    if (used < Duration(minutes: limit) || !mounted) return;
    _timeLimitReached = true;
    await _controller.executeScript(
      "document.querySelector('#_video_player_html5_api, video.vjs-tech, video')?.pause();",
    );
    if (mounted) setState(() {});
  }

  Future<void> _chooseEpisode() async {
    final selected = await showModalBottomSheet<MediaEpisode>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: widget.episodes
              .map((episode) => ListTile(
                    selected: episode.id == _playbackEpisodeId,
                    leading: const Icon(Icons.play_arrow_rounded),
                    title: Text(episode.title),
                    onTap: () => Navigator.pop(context, episode),
                  ))
              .toList(),
        ),
      ),
    );
    if (selected == null || selected.id == _playbackEpisodeId || !mounted) {
      return;
    }
    await _switchEpisode(selected);
  }

  Future<void> _playNextEpisode() async {
    if (!_canChooseEpisode || widget.episodes.length < 2) return;
    if (await _hasReachedChildLimit()) {
      if (mounted) setState(() => _timeLimitReached = true);
      return;
    }
    final currentIndex = widget.episodes.indexWhere(
      (episode) => episode.id == _playbackEpisodeId,
    );
    if (currentIndex < 0 || currentIndex + 1 >= widget.episodes.length) return;
    await _switchEpisode(widget.episodes[currentIndex + 1]);
  }

  Future<void> _switchEpisode(MediaEpisode selected) async {
    setState(() {
      _isWebviewLoaded = false;
      _isPlayerReady = false;
      _error = null;
    });
    _playerReadyTimeout?.cancel();
    try {
      _playback = await widget.resolveEpisode(selected);
      if (widget.sourceCapabilities.contains(SourceCapability.liveCatalog)) {
        unawaited(_preferenceStore.saveLastLiveChannel(
          profileId: widget.profileId,
          sourceId: _playback.sourceId,
          channelId: _playback.sourceEpisodeId,
        ));
      }
      _lastAppliedQuality = null;
      final resumePosition = await _loadResumePosition();
      _lastPosition = resumePosition;
      _lastUsagePosition = resumePosition;
      await _setDocumentScript(resumePosition);
      await _controller.loadUrl(_playback.officialPageUri.toString());
      if (mounted) {
        setState(() {
          _isWebviewLoaded = true;
          _isPlayerReady = false;
        });
        _armPlayerReadyTimeout();
      }
    } catch (error) {
      _playerReadyTimeout?.cancel();
      _recordTelemetry(PlaybackTelemetryEvent.failed,
          errorCode: 'official_episode');
      if (mounted) setState(() => _error = error);
    }
  }

  String get _playbackEpisodeId =>
      '${_playback.sourceId}:${_playback.sourceEpisodeId}';

  void _recordTelemetry(
    PlaybackTelemetryEvent event, {
    String? errorCode,
  }) =>
      _telemetry.recordEvent(
        event: event,
        mode: PlaybackTelemetryMode.officialPage,
        sourceId: _playback.sourceId,
        sourceEpisodeId: _playback.sourceEpisodeId,
        platform: defaultTargetPlatform.name,
        errorCode: errorCode,
      );

  void _armPlayerReadyTimeout() {
    _playerReadyTimeout?.cancel();
    _playerReadyTimeout = Timer(const Duration(seconds: 15), () {
      if (!mounted || _isPlayerReady) return;
      _recordTelemetry(PlaybackTelemetryEvent.failed,
          errorCode: 'official_ready_timeout');
      setState(() => _error = StateError('官网播放器准备超时'));
    });
  }

  Future<void> _retryPlayer() async {
    _playerReadyTimeout?.cancel();
    setState(() {
      _error = null;
      _isPlayerReady = false;
      _isWebviewLoaded = false;
    });
    try {
      await _controller.loadUrl(_playback.officialPageUri.toString());
      if (!mounted) return;
      setState(() {
        _isWebviewLoaded = true;
        _isPlayerReady = false;
      });
      _armPlayerReadyTimeout();
    } catch (error) {
      _recordTelemetry(PlaybackTelemetryEvent.failed,
          errorCode: 'official_retry');
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _toggleFullscreen() async {
    await _setFullscreen(!_isFullscreen);
  }

  Future<void> _exitFullscreen() async {
    if (!_isFullscreen) {
      await Navigator.of(context).maybePop();
      return;
    }
    await _setFullscreen(false);
  }

  Future<void> _setFullscreen(bool enabled) async {
    // 先让 Flutter 视图去掉工具栏，避免平台窗口切换较慢时用户感觉按钮无响应。
    if (mounted) setState(() => _isFullscreen = enabled);
    try {
      if (enabled) {
        await _fullscreenSession.enter();
      } else {
        await _fullscreenSession.exit();
      }
    } catch (_) {
      // 平台窗口调用失败时仍保留 Flutter 内的沉浸式布局，避免全屏按钮失效。
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _exitFullscreen();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: _isFullscreen
                ? null
                : AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    title: Text(_playback.title),
                    actions: [
                      if (_canChangeSpeed)
                        PopupMenuButton<double>(
                          tooltip: '倍速',
                          initialValue: _preferredSpeed,
                          onSelected: (speed) => unawaited(_setSpeed(speed)),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 0.75, child: Text('0.75×')),
                            PopupMenuItem(value: 1.0, child: Text('1.0×')),
                            PopupMenuItem(value: 1.25, child: Text('1.25×')),
                            PopupMenuItem(value: 1.5, child: Text('1.5×')),
                            PopupMenuItem(value: 2.0, child: Text('2.0×')),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Center(child: Text('$_preferredSpeed×')),
                          ),
                        ),
                      if (_canChangeVolume)
                        IconButton(
                          tooltip: '音量',
                          onPressed: _showVolumePicker,
                          icon: Icon(_preferredVolume == 0
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded),
                        ),
                      if (_canChooseEpisode && widget.episodes.length > 1)
                        IconButton(
                          tooltip: '选集',
                          onPressed: _chooseEpisode,
                          icon: const Icon(Icons.playlist_play_rounded),
                        ),
                      if (_canFullscreen)
                        IconButton(
                          tooltip: '全屏',
                          onPressed: _toggleFullscreen,
                          icon: const Icon(Icons.fullscreen_rounded),
                        ),
                    ],
                  ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (_isWebviewLoaded)
                  IgnorePointer(
                    ignoring: !_isPlayerReady,
                    child: Opacity(
                      opacity: _isPlayerReady ? 1 : 0,
                      child: Webview(_controller),
                    ),
                  ),
                if (!_isPlayerReady) _buildLoadingOverlay(),
              ],
            ),
          ),
        ),
      );

  Widget _buildLoadingOverlay() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _timeLimitReached
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_off_rounded, size: 52),
                    SizedBox(height: 16),
                    Text('今日观看时长已到上限'),
                    SizedBox(height: 8),
                    Text('请明天再继续观看，或由家长调整儿童档案设置。', textAlign: TextAlign.center),
                  ],
                )
              : _error == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在准备高清播放…'),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 52),
                        const SizedBox(height: 16),
                        const Text('无法启动高清播放'),
                        const SizedBox(height: 8),
                        Text('$_error', textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _retryPlayer,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重新尝试'),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _openInBrowser,
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('在浏览器中打开'),
                        ),
                      ],
                    ),
        ),
      );
}

// 运行在播放页自身的上下文中：不读取、导出或重写媒体地址，只调整
// 已存在播放器容器的展示范围。没有匹配到预期播放器时保持加载遮罩，
// 不暴露官网或第三方解析页的其他 DOM。
String _documentScriptFor(
  String? preferredQuality,
  Duration resumePosition, {
  required double speed,
  required double volume,
}) =>
    _playerOnlyDocumentScript
        .replaceFirst(
          '__JUYING_PREFERRED_QUALITY__',
          jsonEncode(preferredQuality),
        )
        .replaceFirst(
          '__JUYING_RESUME_POSITION_MS__',
          resumePosition.inMilliseconds.toString(),
        )
        .replaceFirst(
          '__JUYING_PLAYBACK_RATE__',
          speed.toString(),
        )
        .replaceFirst(
          '__JUYING_VOLUME__',
          volume.toString(),
        );

const _playerOnlyDocumentScript = r'''
(() => {
  // 每次顶层页面跳转都会重新执行；iframe 保持由页面自身管理。
  if (window.top !== window.self) return;

  // webview_windows 的原生纹理层可能覆盖 Flutter 的加载遮罩，因此先在
  // 文档创建阶段隐藏官网页面；仅在播放器和精简布局都就绪后再揭示它。
  const hideDocument = () => {
    const root = document.documentElement;
    if (!root) {
      setTimeout(hideDocument, 0);
      return;
    }
    root.style.setProperty('visibility', 'hidden', 'important');
    root.style.setProperty('background', '#000', 'important');
  };
  hideDocument();

  const selectors = [
    '#_video_player',
    '#_video',
    '#video',
    '#vodh5player',
    '#video_player',
    '#player',
    '#myFlash',
    '.playingVideo',
    '.video_flash',
    '.video-player',
    '.player_box',
    '.playbox'
  ];
  window.__juyingPreferredQuality = __JUYING_PREFERRED_QUALITY__;
  window.__juyingResumePositionMs = __JUYING_RESUME_POSITION_MS__;
  window.__juyingPlaybackRate = __JUYING_PLAYBACK_RATE__;
  window.__juyingVolume = __JUYING_VOLUME__;
  let hasAnnouncedPlayerReady = false;
  let playerRevealScheduled = false;
  let qualityRestoreAttempts = 0;
  let qualityRestoreTimer = null;
  let resumeApplied = false;
  const trackedVideos = new WeakSet();

  const playerElement = () => selectors
    .map((selector) => document.querySelector(selector))
    .find((element) => element && element.getBoundingClientRect().width > 1);

  const disablePictureInPicture = () => {
    for (const video of document.querySelectorAll('video')) {
      video.disablePictureInPicture = true;
      video.setAttribute('disablePictureInPicture', '');
    }
    if (document.getElementById('juying-disable-pip')) return;
    const style = document.createElement('style');
    style.id = 'juying-disable-pip';
    style.textContent = `
      video::-webkit-media-controls-picture-in-picture-button,
      .vjs-picture-in-picture-control,
      .vjs-pip-button { display: none !important; }
    `;
    document.head?.appendChild(style);
  };

  const observeProgress = () => {
    const video = document.querySelector('#_video_player_html5_api, video.vjs-tech, video');
    if (!(video instanceof HTMLMediaElement) || trackedVideos.has(video)) return;
    trackedVideos.add(video);
    let lastReportedSecond = -5;
    const report = (force = false) => {
      if (!window.chrome?.webview || !Number.isFinite(video.currentTime)) return;
      const currentSecond = Math.floor(video.currentTime);
      if (!force && currentSecond - lastReportedSecond < 5) return;
      lastReportedSecond = currentSecond;
      window.chrome.webview.postMessage({
        type: 'juying:progress',
        positionMs: Math.round(video.currentTime * 1000),
        durationMs: Number.isFinite(video.duration) ? Math.round(video.duration * 1000) : null
      });
    };
    video.addEventListener('timeupdate', () => report());
    video.addEventListener('pause', () => report(true));
    video.addEventListener('ended', () => {
      report(true);
      window.chrome?.webview?.postMessage('juying:episode-ended');
    });
  };

  const restoreResumePosition = () => {
    if (resumeApplied) return;
    const positionMs = Number(window.__juyingResumePositionMs);
    if (!Number.isFinite(positionMs) || positionMs <= 5000) return;
    const video = document.querySelector('#_video_player_html5_api, video.vjs-tech, video');
    if (!(video instanceof HTMLMediaElement)) return;
    const apply = () => {
      if (resumeApplied || !Number.isFinite(video.duration) || video.duration <= 10) return;
      const target = Math.min(positionMs / 1000, Math.max(0, video.duration - 5));
      if (target <= 5) return;
      video.currentTime = target;
      resumeApplied = true;
    };
    video.addEventListener('loadedmetadata', apply, {once: true});
    apply();
  };

  const applyPlaybackPreferences = () => {
    const video = document.querySelector('#_video_player_html5_api, video.vjs-tech, video');
    if (!(video instanceof HTMLMediaElement)) return;
    const speed = Number(window.__juyingPlaybackRate);
    const volume = Number(window.__juyingVolume);
    if (Number.isFinite(speed) && speed >= 0.5 && speed <= 3) {
      video.playbackRate = speed;
    }
    if (Number.isFinite(volume) && volume >= 0 && volume <= 1) {
      video.volume = volume;
    }
  };

  const applyPlayerOnlyLayout = () => {
    const player = playerElement();
    if (!player) return;

    player.dataset.juyingPlayerOnly = 'true';
    // 从播放器向 body 逐层保留唯一祖先分支，同时隐藏每层的其他兄弟节点。
    // 因而评论、推荐、顶部导航等即使和播放器处于同一个页面根节点内，
    // 也不会保留下来。
    for (let node = player; node && node !== document.body; node = node.parentElement) {
      const parent = node.parentElement;
      if (parent) {
        for (const sibling of parent.children) {
          if (sibling !== node) {
            sibling.style.setProperty('display', 'none', 'important');
          }
        }
      }
      node.style.setProperty('display', 'block', 'important');
      node.style.setProperty('visibility', 'visible', 'important');
    }
    Object.assign(document.documentElement.style, {
      width: '100%', height: '100%', overflow: 'hidden', background: '#000'
    });
    Object.assign(document.body.style, {
      margin: '0', width: '100%', height: '100%', overflow: 'hidden', background: '#000'
    });
    Object.assign(player.style, {
      position: 'fixed', inset: '0', width: '100vw', height: '100vh',
      maxWidth: 'none', maxHeight: 'none', zIndex: '2147483647', background: '#000'
    });
    disablePictureInPicture();
    observeProgress();
    restoreResumePosition();
    applyPlaybackPreferences();
    const video = document.querySelector('#_video_player_html5_api, video.vjs-tech, video');
    if (!video) return;
    if (playerRevealScheduled) return;
    playerRevealScheduled = true;
    // 官网播放器会在 video 元素创建后继续补充控件和布局。多保留 200ms
    // 遮罩可避免这段过程短暂露出网页元素。
    setTimeout(() => {
      document.documentElement.style.setProperty('visibility', 'visible', 'important');
      document.body.style.setProperty('visibility', 'visible', 'important');
      if (!hasAnnouncedPlayerReady && window.chrome && window.chrome.webview) {
        hasAnnouncedPlayerReady = true;
        window.chrome.webview.postMessage('juying:official-player-ready');
      }
    }, 200);
  };

  const startPlayback = () => {
    const video = document.querySelector('#_video_player_html5_api, video.vjs-tech, video');
    if (!(video instanceof HTMLMediaElement) || !video.paused) return;
    restoreResumePosition();
    applyPlaybackPreferences();
    const playAttempt = video.play();
    if (playAttempt && typeof playAttempt.catch === 'function') {
      playAttempt.catch(() => document.querySelector('#_video_player')?.click());
    }
    disablePictureInPicture();
  };

  const restorePreferredQuality = () => {
    const preferredQuality = window.__juyingPreferredQuality;
    if (!preferredQuality || qualityRestoreAttempts >= 30) return;
    const options = Array.from(
      document.querySelectorAll('.vjs-playback-quality .vjs-menu-item')
    );
    const option = options.find((item) =>
      item.textContent.trim().replace(/,\s*选择$/, '') === preferredQuality &&
      item.getAttribute('aria-disabled') !== 'true'
    );
    if (!option) {
      scheduleQualityRestore();
      return;
    }
    if (option.getAttribute('aria-checked') === 'true') return;
    qualityRestoreAttempts += 1;
    option.click();
    // 官网播放器会在创建菜单后异步写回默认“高清”。在可用的短窗口内
    // 再核验并重试，直到实际选中的档位与聚映偏好一致。
    scheduleQualityRestore();
  };

  const announceAppliedQuality = () => {
    if (!window.chrome?.webview) return;
    const active = Array.from(
      document.querySelectorAll('.vjs-playback-quality .vjs-menu-item')
    ).find((item) => item.getAttribute('aria-checked') === 'true');
    const quality = active?.textContent.trim().replace(/,\s*选择$/, '');
    if (quality &&
        (!window.__juyingPreferredQuality || quality === window.__juyingPreferredQuality)) {
      window.chrome.webview.postMessage({
        type: 'juying:quality-applied', value: quality
      });
    }
  };

  const scheduleQualityRestore = () => {
    if (qualityRestoreTimer !== null) return;
    qualityRestoreTimer = setTimeout(() => {
      qualityRestoreTimer = null;
      restorePreferredQuality();
    }, 250);
  };

  new MutationObserver(() => {
    applyPlayerOnlyLayout();
    startPlayback();
    scheduleQualityRestore();
    setTimeout(announceAppliedQuality, 600);
  }).observe(document, {
    childList: true, subtree: true
  });
  window.addEventListener('load', () => {
    applyPlayerOnlyLayout();
    startPlayback();
    scheduleQualityRestore();
    setTimeout(startPlayback, 500);
    setTimeout(startPlayback, 1500);
    setTimeout(scheduleQualityRestore, 500);
  }, {once: true});
  // 官方页面可能因版权、地区提示或 DOM 改版而始终没有可用 video。此时给
  // Flutter 明确失败信号，避免仅显示无意义的长时间加载遮罩。
  setTimeout(() => {
    if (hasAnnouncedPlayerReady || !window.chrome?.webview) return;
    const player = playerElement();
    const video = document.querySelector('#_video_player_html5_api, video.vjs-tech, video');
    window.chrome.webview.postMessage({
      type: 'juying:official-player-unavailable',
      reason: !player ? 'container_missing' : !video ? 'video_missing' : 'not_ready'
    });
  }, 12000);
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage('juying:exit-official-player');
    }
  }, true);
  document.addEventListener('click', (event) => {
    const option = event.target.closest('.vjs-playback-quality .vjs-menu-item');
    const quality = option?.textContent.trim().replace(/,\s*选择$/, '');
    if (quality && window.chrome && window.chrome.webview) {
      window.__juyingPreferredQuality = quality;
      qualityRestoreAttempts = 0;
      setTimeout(announceAppliedQuality, 350);
    }
  }, true);
  applyPlayerOnlyLayout();
  startPlayback();
  scheduleQualityRestore();
})();
''';
