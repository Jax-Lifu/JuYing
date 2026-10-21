import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart' as flt_wv;
import 'package:webview_flutter_android/webview_flutter_android.dart'
    as flt_android;
import 'package:webview_windows/webview_windows.dart' as win_wv;

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/core/platform/window_controls.dart';

/// 使用央视官网 WebView（Windows Edge / Android WebKit）播放受保护的高清/超清/4K 点播或直播。
///
/// Flutter 只保留标题与返回入口；清晰度和选集/选台统一由底部控制栏承担，
/// 避免同一操作在画面上下重复出现。央视的 CDRM、Service Worker 与清晰度
/// 授权仍运行在官网上下文中。
class CctvOfficialWebPlayerPage extends StatefulWidget {
  const CctvOfficialWebPlayerPage({
    required this.title,
    required this.currentEpisode,
    this.episodes = const <PlaybackEpisode>[],
    this.initialQuality = '高清',
    this.initialPosition = Duration.zero,
    this.isLive = false,
    this.onEpisodeChanged,
    super.key,
  });

  final String title;
  final PlaybackEpisode currentEpisode;
  final List<PlaybackEpisode> episodes;
  final String initialQuality;

  /// 首次进入点播时恢复的位置；切换剧集后不再沿用，直播忽略此值。
  final Duration initialPosition;
  final bool isLive;
  final ValueChanged<PlaybackEpisode>? onEpisodeChanged;

  @override
  State<CctvOfficialWebPlayerPage> createState() =>
      _CctvOfficialWebPlayerPageState();
}

class _CctvOfficialWebPlayerPageState extends State<CctvOfficialWebPlayerPage> {
  static const Set<String> _supportedQualities = <String>{
    '超清',
    '高清',
    '标清',
    '流畅',
  };
  static const List<double> _playbackRates = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    3.0,
  ];

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  win_wv.WebviewController? _windowsController;
  flt_wv.WebViewController? _flutterController;
  final PlayerFullscreenSession _fullscreenSession = PlayerFullscreenSession(
    const DesktopWindowControls(),
  );
  StreamSubscription<dynamic>? _messageSubscription;
  win_wv.ScriptID? _documentScriptId;
  Timer? _readyTimer;
  Timer? _volumePersistenceTimer;
  int _loadGeneration = 0;
  late PlaybackEpisode _activeEpisode = widget.currentEpisode;
  late Duration _pendingInitialPosition =
      widget.isLive || widget.initialPosition.isNegative
          ? Duration.zero
          : widget.initialPosition;
  late String _preferredQuality = widget.initialQuality;
  double _playbackRate = 1.0;
  double _volume = 1.0;
  bool _muted = false;
  bool _controllerReady = false;
  bool _playerReady = false;
  bool _showWebview = false;
  bool _isClosing = false;
  bool _allowPop = false;
  bool _controllerDisposed = false;
  bool _isFullscreen = false;
  bool _showChrome = true;
  bool _contentUnavailable = false;
  Object? _error;

  String get _qualityPreferenceKey => widget.isLive
      ? 'cctv_web_player_quality_live'
      : 'cctv_web_player_quality_vod';

  List<PlaybackEpisode> get _episodes => widget.episodes.isEmpty
      ? <PlaybackEpisode>[widget.currentEpisode]
      : widget.episodes;

  int get _activeEpisodeIndex => _episodes.indexWhere(
        (episode) => episode.officialPageUrl == _activeEpisode.officialPageUrl,
      );

  bool get _canPlayPreviousEpisode => !widget.isLive && _activeEpisodeIndex > 0;

  bool get _canPlayNextEpisode =>
      !widget.isLive &&
      _activeEpisodeIndex >= 0 &&
      _activeEpisodeIndex + 1 < _episodes.length;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedQuality = preferences.getString(_qualityPreferenceKey);
      if (savedQuality != null && _supportedQualities.contains(savedQuality)) {
        _preferredQuality = savedQuality;
      }
      final savedRate = preferences.getDouble('cctv_web_playback_rate');
      if (savedRate != null && _playbackRates.contains(savedRate)) {
        _playbackRate = savedRate;
      }
      _volume =
          (preferences.getDouble('web_player_volume') ?? 1.0).clamp(0.0, 1.0);
      // 旧版本会把官网为满足自动播放策略而设置的临时静音误存为用户偏好。
      // 静音仅保留在当前播放会话，重新进入时始终恢复实际音量。
      if (preferences.containsKey('web_player_muted') && _volume == 0) {
        _volume = 1.0;
      }
      _muted = false;
      await preferences.remove('web_player_muted');

      if (_isClosing) return;

      if (_isWindows) {
        final version = await win_wv.WebviewController.getWebViewVersion();
        if (version == null) {
          throw StateError('未安装 Microsoft Edge WebView2 Runtime');
        }
        if (_isClosing) return;

        final controller = win_wv.WebviewController();
        _windowsController = controller;
        await controller.initialize();
        await controller
            .setPopupWindowPolicy(win_wv.WebviewPopupWindowPolicy.deny);
        await controller.setBackgroundColor(Colors.black);
        _messageSubscription = controller.webMessage.listen(_handleWebMessage);
      } else {
        final controller = flt_wv.WebViewController();
        await controller.setJavaScriptMode(flt_wv.JavaScriptMode.unrestricted);
        await controller.setBackgroundColor(Colors.black);
        await controller.setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        );
        await controller.addJavaScriptChannel(
          'JuyingBridge',
          onMessageReceived: (flt_wv.JavaScriptMessage message) {
            try {
              final decoded = jsonDecode(message.message);
              if (decoded is Map<String, dynamic>) {
                _handleWebMessage(decoded);
              }
            } catch (e) {
              debugPrint('[CCTV WebView Bridge] Parse error: $e');
            }
          },
        );
        await controller.setNavigationDelegate(
          flt_wv.NavigationDelegate(
            onPageStarted: (String url) {
              _injectScriptToFlutterWebview();
            },
            onPageFinished: (String url) {
              _injectScriptToFlutterWebview();
            },
            onWebResourceError: (flt_wv.WebResourceError error) {
              debugPrint('[CCTV WebResourceError] ${error.description}');
            },
          ),
        );

        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            controller.platform is flt_android.AndroidWebViewController) {
          await flt_android.AndroidWebViewController.enableDebugging(
              kDebugMode);
          await (controller.platform as flt_android.AndroidWebViewController)
              .setMediaPlaybackRequiresUserGesture(false);
        }

        _flutterController = controller;
      }

      if (!mounted || _isClosing) return;
      setState(() {
        _controllerReady = true;
        _showWebview = true;
      });
      await _loadEpisode(_activeEpisode);
    } catch (error) {
      if (mounted && !_isClosing) setState(() => _error = error);
    }
  }

  void _injectScriptToFlutterWebview() {
    if (_isClosing || _flutterController == null) return;
    final scriptContent = _playerOnlyScript(
      _preferredQuality,
      widget.isLive,
      _playbackRate,
      _canPlayPreviousEpisode,
      _canPlayNextEpisode,
      _episodes.length > 1,
      _volume,
      _muted,
      _loadGeneration,
      _pendingInitialPosition,
    );
    _flutterController!.runJavaScript(scriptContent);
  }

  Future<void> _loadEpisode(PlaybackEpisode episode) async {
    final pageUrl = episode.officialPageUrl;
    if (pageUrl == null || pageUrl.isEmpty) {
      throw StateError('该节目没有央视官网播放页');
    }
    // WebView 的上一页可能在新导航开始后继续发送事件。每次加载使用独立代次，
    // 防止旧频道的就绪状态和清晰度结果覆盖当前频道。
    final generation = ++_loadGeneration;
    _readyTimer?.cancel();
    if (mounted) {
      setState(() {
        _activeEpisode = episode;
        _playerReady = false;
        _contentUnavailable = false;
        _error = null;
      });
    }
    if (!widget.isLive) widget.onEpisodeChanged?.call(episode);

    if (_isWindows) {
      // WebView2 的 loadUrl 可能在站点握手阶段长时间不返回。新一次选台必须主动
      // 中止旧导航，让遥控器连按与频道面板选择都遵循“最后一次选择优先”。
      try {
        await _windowsController?.stop();
      } catch (_) {
        // 首次导航或已自然结束时 stop 可能失败，不影响后续页面加载。
      }
      if (_isClosing || generation != _loadGeneration) return;
      final previousScript = _documentScriptId;
      _documentScriptId = null;
      if (previousScript != null) {
        await _windowsController
            ?.removeScriptToExecuteOnDocumentCreated(previousScript);
      }
      if (_isClosing || generation != _loadGeneration) return;
      final nextScript =
          await _windowsController?.addScriptToExecuteOnDocumentCreated(
        _playerOnlyScript(
          _preferredQuality,
          widget.isLive,
          _playbackRate,
          _canPlayPreviousEpisode,
          _canPlayNextEpisode,
          _episodes.length > 1,
          _volume,
          _muted,
          generation,
          _pendingInitialPosition,
        ),
      );
      if (_isClosing || generation != _loadGeneration) {
        if (nextScript != null) {
          await _windowsController
              ?.removeScriptToExecuteOnDocumentCreated(nextScript);
        }
        return;
      }
      _documentScriptId = nextScript;
      _armReadyTimer();
      await _windowsController?.loadUrl(pageUrl);
    } else {
      _armReadyTimer();
      await _flutterController?.loadRequest(Uri.parse(pageUrl));
    }
    if (_isClosing || generation != _loadGeneration) return;
  }

  /// 初始化完成前只更新待播频道；控制器就绪后会读取最新选择发起导航。
  Future<void> _selectEpisode(PlaybackEpisode episode) async {
    if (_isClosing ||
        episode.officialPageUrl == _activeEpisode.officialPageUrl) {
      return;
    }
    _pendingInitialPosition = Duration.zero;
    if (!_controllerReady) {
      _loadGeneration++;
      if (mounted) {
        setState(() {
          _activeEpisode = episode;
          _playerReady = false;
          _contentUnavailable = false;
          _error = null;
        });
      }
      return;
    }
    await _loadEpisode(episode);
  }

  void _armReadyTimer() {
    _readyTimer?.cancel();
    _readyTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted || _isClosing || _playerReady) return;
      _showContentUnavailable();
    });
  }

  void _showContentUnavailable() {
    _readyTimer?.cancel();
    if (!mounted || _isClosing) return;
    setState(() {
      _playerReady = false;
      _contentUnavailable = true;
      _error = null;
    });
  }

  void _handleWebMessage(dynamic message) {
    if (_isClosing || !mounted) return;
    if (message is! Map) return;
    final messageGeneration = message['generation'];
    if (messageGeneration is! num ||
        messageGeneration.toInt() != _loadGeneration) {
      return;
    }
    if (message['type'] == 'juying:resume-applied' ||
        message['type'] == 'juying:resume-cancelled') {
      _pendingInitialPosition = Duration.zero;
      return;
    }
    if (message['type'] == 'juying:ready') {
      _readyTimer?.cancel();
      setState(() {
        _playerReady = true;
        _contentUnavailable = false;
        _error = null;
      });
      return;
    }
    if (message['type'] == 'juying:ended' && !widget.isLive) {
      unawaited(_playNextEpisode());
      return;
    }
    if (message['type'] == 'juying:quality') {
      // 官网可能在授权清晰度准备完成前短暂回报“标清”。用户偏好与当前
      // 自适应结果分离，避免这个瞬态值覆盖下次进入时的超清选择。
      return;
    }
    if (message['type'] == 'juying:fullscreen') {
      unawaited(_setFullscreen(message['value'] == true));
      return;
    }
    if (message['type'] == 'juying:controls') {
      final visible = message['value'] == true;
      if (visible != _showChrome) setState(() => _showChrome = visible);
      return;
    }
    if (message['type'] == 'juying:fullscreen-request') {
      unawaited(_setFullscreen(message['value'] == true));
      return;
    }
    if (message['type'] == 'juying:quality-selected') {
      final quality = message['value'];
      if (quality is String) unawaited(_setQuality(quality));
      return;
    }
    if (message['type'] == 'juying:quality-applied') {
      // 页面只用实际结果刷新控件文案；偏好仍保留用户选择，避免某个频道
      // 缺少对应档位时把全局偏好永久降级，切到下个频道后无法继承。
      return;
    }
    if (message['type'] == 'juying:rate-selected') {
      final rate = message['value'];
      if (rate is num) unawaited(_setPlaybackRate(rate.toDouble()));
      return;
    }
    if (message['type'] == 'juying:volume') {
      if (message['userInitiated'] != true) return;
      final volume = message['volume'];
      if (volume is num) {
        _volume = volume.toDouble().clamp(0.0, 1.0);
        _muted = message['muted'] == true;
        _scheduleVolumePersistence();
      }
      return;
    }
    if (message['type'] == 'juying:previous') {
      unawaited(
        widget.isLive ? _playRelativeLiveChannel(-1) : _playPreviousEpisode(),
      );
      return;
    }
    if (message['type'] == 'juying:next') {
      unawaited(
        widget.isLive ? _playRelativeLiveChannel(1) : _playNextEpisode(),
      );
      return;
    }
    if (message['type'] == 'juying:episodes') {
      unawaited(_showEpisodePicker());
      return;
    }
    if (message['type'] == 'juying:error' ||
        message['type'] == 'juying:unavailable') {
      _showContentUnavailable();
    }
  }

  /// 先卸载 Texture，等待 Flutter 提交空白帧，再释放原生 WebView。
  ///
  /// `webview_windows` 的 TextureRegistrar 回调若与路由销毁同帧发生，会在
  /// `flutter_windows.dll` 内触发 0xc0000005；两阶段退出可切断该竞态。
  Future<void> _close() async {
    if (_isClosing || !mounted) return;
    _isClosing = true;
    _readyTimer?.cancel();
    if (_isWindows) {
      await _fullscreenSession.dispose();
    } else {
      if (!kIsWeb) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    }
    _isFullscreen = false;
    setState(() => _showWebview = false);
    await WidgetsBinding.instance.endOfFrame;

    await _messageSubscription?.cancel();
    _messageSubscription = null;
    if (_isWindows) {
      try {
        await _windowsController?.stop();
      } catch (_) {
        // 页面可能已自行结束导航；退出流程仍必须继续释放原生纹理。
      }
    }
    await _disposeController();
    if (!mounted) return;

    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disposeController() async {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    if (_isWindows) {
      await _windowsController?.dispose();
      _windowsController = null;
    }
  }

  Future<void> _executeScript(String script) async {
    if (_isClosing || !_controllerReady) return;
    if (_isWindows) {
      await _windowsController?.executeScript(script);
    } else {
      await _flutterController?.runJavaScript(script);
    }
  }

  Future<void> _retry() async {
    try {
      await _loadEpisode(_activeEpisode);
    } catch (error) {
      if (mounted && !_isClosing) setState(() => _error = error);
    }
  }

  Future<void> _setQuality(String quality) async {
    if (!_supportedQualities.contains(quality)) return;
    if (mounted && !_isClosing && _preferredQuality != quality) {
      setState(() => _preferredQuality = quality);
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_qualityPreferenceKey, quality);
    await _executeScript(
      'window.__juyingSetQuality?.(${jsonEncode(quality)});',
    );
  }

  Future<void> _setPlaybackRate(double rate) async {
    if (!_playbackRates.contains(rate) || widget.isLive) return;
    setState(() => _playbackRate = rate);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble('cctv_web_playback_rate', rate);
    await _executeScript(
      'window.__juyingSetPlaybackRate?.($rate);',
    );
  }

  void _scheduleVolumePersistence() {
    _volumePersistenceTimer?.cancel();
    _volumePersistenceTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_persistVolume()),
    );
  }

  Future<void> _persistVolume() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble('web_player_volume', _volume);
  }

  Future<void> _setFullscreen(bool fullscreen) async {
    if (_isClosing || fullscreen == _isFullscreen) return;
    if (_isWindows) {
      if (fullscreen) {
        await _fullscreenSession.enter();
      } else {
        await _fullscreenSession.exit();
        if (_controllerReady) {
          await _executeScript(
            'if (document.fullscreenElement) document.exitFullscreen?.();',
          );
        }
      }
    } else {
      if (fullscreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    }
    if (mounted && !_isClosing) setState(() => _isFullscreen = fullscreen);
    if (_controllerReady && !_isClosing) {
      await _executeScript(
        'window.__juyingSetFullscreenState?.($fullscreen);',
      );
    }
  }

  void _handleBack() {
    if (_isFullscreen) {
      unawaited(_setFullscreen(false));
    } else {
      unawaited(_close());
    }
  }

  Future<void> _showEpisodePicker() async {
    final selected = await showModalBottomSheet<PlaybackEpisode>(
      context: context,
      backgroundColor: context.colors.surfaceCard,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Text(
                  widget.isLive ? '选择频道' : '选择剧集',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: widget.isLive ? 260 : 280,
                    mainAxisExtent: widget.isLive ? 118 : 180,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                  ),
                  itemCount: _episodes.length,
                  itemBuilder: (context, index) {
                    final episode = _episodes[index];
                    final isSelected = episode.officialPageUrl ==
                        _activeEpisode.officialPageUrl;
                    return _EpisodeCard(
                      episode: episode,
                      isSelected: isSelected,
                      isLive: widget.isLive,
                      onTap: () => Navigator.pop(context, episode),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null ||
        selected.officialPageUrl == _activeEpisode.officialPageUrl ||
        !mounted ||
        _isClosing) {
      return;
    }
    try {
      await _selectEpisode(selected);
    } catch (error) {
      if (mounted &&
          !_isClosing &&
          selected.officialPageUrl == _activeEpisode.officialPageUrl) {
        setState(() => _error = error);
      }
    }
  }

  /// 相邻剧集切换统一走加载契约，保证标题、播放记录和 WebView 页面同步更新。
  Future<void> _playRelativeEpisode(int offset) async {
    final targetIndex = _activeEpisodeIndex + offset;
    if (widget.isLive ||
        targetIndex < 0 ||
        targetIndex >= _episodes.length ||
        _isClosing) {
      return;
    }
    try {
      final target = _episodes[targetIndex];
      await _selectEpisode(target);
    } catch (error) {
      if (mounted &&
          !_isClosing &&
          _episodes[targetIndex].officialPageUrl ==
              _activeEpisode.officialPageUrl) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _playNextEpisode() => _playRelativeEpisode(1);

  Future<void> _playPreviousEpisode() => _playRelativeEpisode(-1);

  /// 直播遥控器上下键循环换台；连续操作由加载代次收敛到最后选择的频道。
  Future<void> _playRelativeLiveChannel(int offset) async {
    if (!widget.isLive || _episodes.length < 2 || _isClosing) return;
    final currentIndex = _activeEpisodeIndex < 0 ? 0 : _activeEpisodeIndex;
    final targetIndex = (currentIndex + offset) % _episodes.length;
    final target = _episodes[targetIndex];
    try {
      await _selectEpisode(target);
    } catch (error) {
      // stop() 会让旧 loadUrl 以异常结束；只有当前仍指向该目标时才展示错误。
      if (mounted &&
          !_isClosing &&
          target.officialPageUrl == _activeEpisode.officialPageUrl) {
        setState(() => _error = error);
      }
    }
  }

  /// WebView 尚未出画时由 Flutter 接管上下键；出画后交回网页控制层处理。
  KeyEventResult _handleLoadingKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        !widget.isLive ||
        _playerReady ||
        _isClosing) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.pageUp ||
        event.logicalKey == LogicalKeyboardKey.channelDown) {
      unawaited(_playRelativeLiveChannel(-1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.pageDown ||
        event.logicalKey == LogicalKeyboardKey.channelUp) {
      unawaited(_playRelativeLiveChannel(1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _isClosing = true;
    _readyTimer?.cancel();
    _volumePersistenceTimer?.cancel();
    unawaited(_persistVolume());
    unawaited(_messageSubscription?.cancel());
    if (!_controllerDisposed) unawaited(_disposeController());
    if (_isWindows) {
      unawaited(_fullscreenSession.dispose());
    } else {
      if (!kIsWeb) {
        unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
        unawaited(
          SystemChrome.setPreferredOrientations(DeviceOrientation.values),
        );
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _handleBack();
          },
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: _handleLoadingKeyEvent,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (_controllerReady && _showWebview)
                  IgnorePointer(
                    ignoring: !_playerReady,
                    child: Opacity(
                      opacity: _playerReady ? 1 : 0,
                      child: _isWindows
                          ? win_wv.Webview(_windowsController!)
                          : flt_wv.WebViewWidget(
                              controller: _flutterController!,
                            ),
                    ),
                  ),
                if (!_playerReady && !_isClosing)
                  ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: _error == null && !_contentUnavailable
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  '正在连接 ${_activeEpisode.name}…',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                if (widget.isLive &&
                                    _episodes.length > 1) ...<Widget>[
                                  const SizedBox(height: 8),
                                  Text(
                                    '无需等待，可直接切换频道',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  _buildLoadingChannelControls(colors),
                                ],
                              ],
                            )
                          : _contentUnavailable
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Container(
                                      width: 104,
                                      height: 82,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF112746),
                                        borderRadius: BorderRadius.circular(22),
                                        boxShadow: const <BoxShadow>[
                                          BoxShadow(
                                            color: Color(0x663A8DFF),
                                            blurRadius: 32,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.live_tv_rounded,
                                        color: Color(0xFF77AFFF),
                                        size: 52,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      '由于播出安排变更，暂不支持播放该时段内容',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    FilledButton.icon(
                                      onPressed: _retry,
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('刷新'),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () => unawaited(_close()),
                                      child: const Text('返回上一页'),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.error_outline,
                                      color: colors.textSecondary,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '播放器初始化失败，请重试',
                                      style:
                                          TextStyle(color: colors.textPrimary),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                      onPressed: _retry,
                                      child: const Text('重试'),
                                    ),
                                  ],
                                ),
                    ),
                  ),
                if (!_isClosing)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: !_showChrome,
                      child: AnimatedSlide(
                        offset:
                            _showChrome ? Offset.zero : const Offset(0, -0.16),
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        child: _buildTopChrome(colors),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopChrome(AppThemeColors colors) {
    final pageTitle = widget.title.trim();
    final episodeName = _activeEpisode.name.trim();
    final title =
        widget.isLive || pageTitle == episodeName || episodeName.isEmpty
            ? pageTitle
            : '$pageTitle - $episodeName';
    final subtitle = widget.isLive
        ? _playerReady
            ? '当前源: 央视官网 · $_preferredQuality'
            : '正在连接 · 可继续切台'
        : '央视官方 · $_preferredQuality';

    return AnimatedOpacity(
      opacity: _showChrome ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: <Widget>[
              _PlayerChromeButton(
                tooltip: '返回',
                onTap: () => unawaited(_close()),
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.brandAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isLive && _episodes.length > 1) ...<Widget>[
                _PlayerChromeButton(
                  tooltip: '上一个频道',
                  onTap: () => unawaited(_playRelativeLiveChannel(-1)),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.skip_previous_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 8),
                _PlayerChromeButton(
                  tooltip: '选择频道',
                  onTap: () => unawaited(_showEpisodePicker()),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.live_tv_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text('选台', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _PlayerChromeButton(
                  tooltip: '下一个频道',
                  onTap: () => unawaited(_playRelativeLiveChannel(1)),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.skip_next_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingChannelControls(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceCard.withAlpha(220),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceElevation),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _PlayerChromeButton(
            tooltip: '上一个频道',
            onTap: () => unawaited(_playRelativeLiveChannel(-1)),
            padding: const EdgeInsets.all(8),
            child: const Icon(
              Icons.skip_previous_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          _PlayerChromeButton(
            tooltip: '选择频道',
            onTap: () => unawaited(_showEpisodePicker()),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: const Text('选择频道', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 8),
          _PlayerChromeButton(
            tooltip: '下一个频道',
            onTap: () => unawaited(_playRelativeLiveChannel(1)),
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.skip_next_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _PlayerChromeButton extends StatelessWidget {
  const _PlayerChromeButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
    required this.padding,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.isSelected,
    required this.isLive,
    required this.onTap,
  });

  final PlaybackEpisode episode;
  final bool isSelected;
  final bool isLive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final thumbnailUrl = episode.thumbnailUrl;
    return Material(
      color:
          isSelected ? colors.brandPrimary.withAlpha(35) : colors.surfaceCard,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? colors.brandPrimary : colors.surfaceElevation,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                      Image.network(
                        thumbnailUrl,
                        fit: isLive ? BoxFit.contain : BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _thumbnailFallback(colors),
                      )
                    else
                      _thumbnailFallback(colors),
                    Center(
                      child: Icon(
                        isSelected
                            ? Icons.play_circle_fill_rounded
                            : isLive
                                ? Icons.live_tv_rounded
                                : Icons.play_circle_outline_rounded,
                        color: Colors.white,
                        size: 34,
                        shadows: const <Shadow>[
                          Shadow(color: Colors.black87, blurRadius: 8),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Text(
                  episode.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnailFallback(AppThemeColors colors) {
    return ColoredBox(
      color: colors.surfaceElevation,
      child: Icon(
        isLive ? Icons.live_tv_rounded : Icons.movie_outlined,
        color: colors.textTertiary,
        size: 38,
      ),
    );
  }
}

String _playerOnlyScript(
  String quality,
  bool isLive,
  double playbackRate,
  bool canPlayPrevious,
  bool canPlayNext,
  bool hasEpisodes,
  double volume,
  bool muted,
  int generation,
  Duration initialPosition,
) =>
    _playerOnlyDocumentScript
        .replaceFirst('__JUYING_QUALITY__', jsonEncode(quality))
        .replaceFirst('__JUYING_IS_LIVE__', isLive.toString())
        .replaceFirst('__JUYING_PLAYBACK_RATE__', playbackRate.toString())
        .replaceFirst('__JUYING_CAN_PREVIOUS__', canPlayPrevious.toString())
        .replaceFirst('__JUYING_CAN_NEXT__', canPlayNext.toString())
        .replaceFirst('__JUYING_HAS_EPISODES__', hasEpisodes.toString())
        .replaceFirst('__JUYING_VOLUME__', volume.toString())
        .replaceFirst('__JUYING_MUTED__', muted.toString())
        .replaceFirst('__JUYING_GENERATION__', generation.toString())
        .replaceFirst('__JUYING_INITIAL_POSITION__',
            (initialPosition.inMilliseconds / 1000).toString());

// 页面只保留官网播放器容器，不读取、导出或重写任何媒体地址。
const String _playerOnlyDocumentScript = r'''
(() => {
  if (window.top !== window.self) return;
  const generation = __JUYING_GENERATION__;
  // Flutter may inject at both navigation start and completion. One document
  // generation owns its timers and its single resume operation.
  if (window.__juyingPlayerGeneration >= generation) return;
  window.__juyingPlayerGeneration = generation;
  const isCurrent = () => window.__juyingPlayerGeneration === generation;
  const postPayload = (payload) => {
    if (!isCurrent()) return;
    const data = {
      ...payload,
      generation
    };
    try {
      if (window.chrome?.webview?.postMessage) {
        window.chrome.webview.postMessage(data);
      }
    } catch (_) {}
    try {
      if (window.JuyingBridge?.postMessage) {
        window.JuyingBridge.postMessage(JSON.stringify(data));
      }
    } catch (_) {}
  };
  const post = (type, value) => postPayload(
    value === undefined ? {type} : {type, value}
  );
  window.__juyingPreferredQuality = __JUYING_QUALITY__;
  const isLive = __JUYING_IS_LIVE__;
  const initialPosition = __JUYING_INITIAL_POSITION__;
  let resumePending = !isLive && Number.isFinite(initialPosition) && initialPosition > 0;
  let initialQualityReady = false;
  let resumeVideo = null;
  let resumeTimer = null;
  const resumeDeadline = Date.now() + 60000;
  const canPlayPrevious = __JUYING_CAN_PREVIOUS__;
  const canPlayNext = __JUYING_CAN_NEXT__;
  const hasEpisodes = __JUYING_HAS_EPISODES__;
  window.__juyingPlaybackRate = __JUYING_PLAYBACK_RATE__;
  window.__juyingVolume = __JUYING_VOLUME__;
  window.__juyingMuted = __JUYING_MUTED__;
  let ready = false;
  let unavailable = false;
  let qualityTimer = null;
  let qualityRequestId = 0;
  const trackedVideos = new WeakSet();
  const autoplayStates = new WeakMap();
  const hideDocument = () => {
    if (!document.documentElement) { setTimeout(hideDocument, 0); return; }
    document.documentElement.style.setProperty('visibility', 'hidden', 'important');
    document.documentElement.style.setProperty('background', '#000', 'important');
  };
  hideDocument();
  const installControlsStyle = () => {
      if (!document.head || document.getElementById('juying-controls-style')) return;
      const style = document.createElement('style');
      style.id = 'juying-controls-style';
      style.textContent = `
        #juying-controls {
          position: fixed !important; inset: auto 0 0 0 !important;
          z-index: 2147483647 !important; display: block !important;
          padding: 32px 20px 20px !important;
          box-sizing: border-box !important;
          background: linear-gradient(to bottom, transparent, rgba(0,0,0,.88)) !important;
          color: #fff !important; font: 13px/1.2 "Segoe UI", sans-serif !important;
          opacity: 0; transform: translateY(6px);
          transition: opacity 160ms ease, transform 160ms ease;
          pointer-events: none;
        }
        #juying-controls.visible { opacity: 1; transform: none; pointer-events: auto; }
        #juying-controls .jy-timeline { display: flex; align-items: center; gap: 12px;
          width: 100%; margin-bottom: 8px; }
        #juying-controls .jy-current-time, #juying-controls .jy-duration {
          min-width: 40px; color: rgba(255,255,255,.92); font-size: 13px; }
        #juying-controls .jy-duration { text-align: right; color: rgba(255,255,255,.72); }
        #juying-controls .jy-progress { flex: 1; width: auto; height: 4px; margin: 0;
          padding: 0; cursor: pointer; appearance: none; border-radius: 4px;
          background: rgba(255,255,255,.34); }
        #juying-controls .jy-progress::-webkit-slider-thumb,
        #juying-controls .jy-volume::-webkit-slider-thumb {
          appearance: none; width: 13px; height: 13px; border-radius: 50%;
          border: 2px solid #fff; background: #29c76f; box-shadow: 0 1px 5px rgba(0,0,0,.65);
        }
        #juying-controls .jy-row { height: 36px; display: flex; align-items: center; gap: 8px; }
        #juying-controls button, #juying-controls select {
          height: 32px; border: 0; border-radius: 6px; background: transparent;
          color: #fff; font: inherit; cursor: pointer; outline: none;
        }
        #juying-controls button { min-width: 32px; padding: 0 8px; font-size: 15px; }
        #juying-controls button:hover, #juying-controls select:hover {
          background: rgba(255,255,255,.14);
        }
        #juying-controls button:disabled { opacity: .34; cursor: default; background: transparent; }
        #juying-controls .jy-spacer { flex: 1; }
        #juying-controls .jy-volume { width: 72px; height: 4px; appearance: none;
          border-radius: 4px; background: rgba(255,255,255,.35); cursor: pointer; }
        #juying-controls .jy-text-button { padding: 0 10px; font-size: 12px;
          background: rgba(255,255,255,.12); }
        #juying-controls .jy-icon-text-button { display: inline-flex; align-items: center;
          justify-content: center; gap: 5px; }
        #juying-controls .jy-icon-text-button svg { width: 15px; height: 15px; }
        #juying-controls #juying-quality { background: rgba(30,142,62,.48); }
        #juying-controls .jy-divider { width: 1px; height: 18px; margin: 0 3px;
          background: rgba(255,255,255,.18); }
        #juying-controls svg { width: 19px; height: 19px; fill: currentColor; vertical-align: middle; }
        #juying-controls .jy-menu-wrap { position: relative; }
        #juying-controls .jy-menu {
          position: absolute; right: 0; bottom: 38px; min-width: 92px; padding: 6px;
          border: 1px solid rgba(255,255,255,.12); border-radius: 8px;
          background: rgba(18,22,29,.98); box-shadow: 0 8px 24px rgba(0,0,0,.45);
          opacity: 0; transform: translateY(5px); pointer-events: none;
          transition: opacity 120ms ease, transform 120ms ease;
        }
        #juying-controls .jy-menu-wrap.open .jy-menu {
          opacity: 1; transform: none; pointer-events: auto;
        }
        #juying-controls .jy-menu button { width: 100%; height: 30px; text-align: left; font-size: 12px; }
        #juying-controls .jy-menu button.active { color: #50e47a; background: rgba(80,228,122,.12); }
      `;
      document.head.appendChild(style);
  };
  installControlsStyle();
  document.addEventListener('DOMContentLoaded', installControlsStyle, {once: true});
  const findVideo = () => Array.from(document.querySelectorAll(
    '#h5player_player, #_video_player_html5_api, video.vjs-tech, video'
  )).find((candidate) => {
    const rect = candidate.getBoundingClientRect();
    return rect.width > 100 && rect.height > 100;
  });
  const cancelInitialResume = () => {
    if (!resumePending || !isCurrent()) return;
    resumePending = false;
    clearTimeout(resumeTimer);
    post('juying:resume-cancelled');
  };
  // Initial quality selection may replace the video or reset its source. Wait
  // for that selection and an actual seekable range; short pre-roll/unknown
  // duration must not clamp a content position to the end of the wrong stream.
  const restoreInitialPosition = () => {
    if (!resumePending || !isCurrent()) return;
    if (Date.now() >= resumeDeadline) { resumePending = false; return; }
    const video = findVideo();
    if (initialQualityReady && video instanceof HTMLMediaElement &&
        video.readyState >= 1 && Number.isFinite(video.duration) &&
        video.duration > initialPosition) {
      if (resumeVideo === video && !video.seeking &&
          Math.abs(video.currentTime - initialPosition) < 2) {
        resumePending = false;
        post('juying:resume-applied', video.currentTime);
        return;
      } else if (!video.seeking) {
        // The official player can reset the source on the same video element.
        // Only an unacknowledged restore retries; user seeking cancels it.
        for (let index = 0; index < video.seekable.length; index++) {
          if (video.seekable.start(index) <= initialPosition &&
              video.seekable.end(index) >= initialPosition) {
            try {
              video.currentTime = initialPosition;
              resumeVideo = video;
            } catch (_) {} // A source replacement may invalidate this range.
            break;
          }
        }
      }
    }
    resumeTimer = setTimeout(restoreInitialPosition, 250);
  };
  const detectUnavailable = () => {
    if (ready || unavailable || !document.body) return false;
    const text = document.body.innerText || '';
    const patterns = [
      '暂不支持播放该时段内容',
      '由于播出安排变更',
      '当前暂无节目',
      '暂无可播放内容'
    ];
    if (!patterns.some((pattern) => text.includes(pattern))) return false;
    unavailable = true;
    post('juying:unavailable');
    return true;
  };
  const normalizeQuality = (value) => {
    const text = String(value || '').replace(/,\s*选择$/, '').replace(/\s+/g, '');
    return ['超清', '高清', '标清', '流畅'].find((quality) => text.includes(quality)) || '';
  };
  const videoJsQualityItems = () => Array.from(new Set(document.querySelectorAll([
    '.vjs-playback-quality .vjs-menu-item',
    '.vjs-resolution-button .vjs-menu-item',
    '.vjs-quality-selector .vjs-menu-item',
    '[class*="quality"] .vjs-menu-item'
  ].join(','))));
  const currentOfficialQuality = () => {
    if (isLive) {
      return normalizeQuality(document.querySelector('[id^="player_resolution_show_"]')?.textContent);
    }
    const active = videoJsQualityItems().find((item) =>
      item.getAttribute('aria-checked') === 'true' || item.classList.contains('vjs-selected'));
    return normalizeQuality(active?.textContent);
  };
  const announceQuality = () => {
    const value = currentOfficialQuality();
    if (!value) return '';
    const trigger = document.querySelector('#juying-quality');
    if (trigger) trigger.textContent = value;
    document.querySelectorAll('#juying-quality-wrap .jy-menu button').forEach((option) =>
      option.classList.toggle('active', option.dataset.value === value));
    post('juying:quality-applied', value);
    return value;
  };
  window.__juyingSetQuality = (quality) => {
    if (!isCurrent()) return;
    initialQualityReady = false;
    window.__juyingPreferredQuality = quality;
    const trigger = document.querySelector('#juying-quality');
    if (trigger) trigger.textContent = `${quality}…`;
    let attempts = 0;
    let stableMatches = 0;
    const requestId = ++qualityRequestId;
    clearTimeout(qualityTimer);
    const apply = () => {
      if (!isCurrent() || requestId !== qualityRequestId) return;
      attempts += 1;
      const liveResolution = {'超清': '720', '高清': '540', '标清': '480', '流畅': '360'}[quality];
      const item = isLive
        ? document.querySelector(`[id^="resolution_item_${liveResolution}_"]`)
        : videoJsQualityItems().find((candidate) =>
            normalizeQuality(candidate.textContent) === quality &&
            candidate.getAttribute('aria-disabled') !== 'true');
      if (currentOfficialQuality() !== quality && item) item.click();
      stableMatches = currentOfficialQuality() === quality
        ? stableMatches + 1
        : 0;
      // 官网点击后会重建一次清晰度控件。连续确认一秒后再回报成功，
      // 避免只改中了菜单选中态、实际直播流随后又回退。
      if (stableMatches >= 4) {
        initialQualityReady = true;
        announceQuality();
      } else if (attempts < 80) {
        qualityTimer = setTimeout(apply, 250);
      } else {
        // Some channels expose fewer tiers; keep our label on the real stream.
        initialQualityReady = true;
        announceQuality();
      }
    };
    apply();
  };
  window.__juyingSetPlaybackRate = (rate) => {
    const value = Number(rate);
    if (!Number.isFinite(value) || value <= 0 || isLive) return;
    window.__juyingPlaybackRate = value;
    const video = findVideo();
    if (video instanceof HTMLMediaElement) video.playbackRate = value;
  };
  const observeVideo = () => {
    const video = document.querySelector('#_video_player_html5_api, video.vjs-tech, video');
    if (!(video instanceof HTMLMediaElement) || trackedVideos.has(video)) return;
    trackedVideos.add(video);
    video.addEventListener('ended', () => post('juying:ended'));
  };
  // WebView2 会拒绝首次有声 play()，央视播放器初始化时也可能替换 video 或
  // 再次 pause。每个 video 独立追踪自动播放状态，静音解锁成功后立即恢复
  // 用户音量；一旦用户主动暂停，就永久停止本元素的自动重试。
  const preferredAudio = (video) => {
    video.volume = Math.max(0, Math.min(1, Number(window.__juyingVolume)));
    video.muted = Boolean(window.__juyingMuted);
  };
  const markUserPaused = (video) => {
    const state = autoplayStates.get(video);
    if (state) {
      state.userPaused = true;
      clearTimeout(state.timer);
    }
  };
  const ensureAutoplay = (video) => {
    let state = autoplayStates.get(video);
    if (!state) {
      state = {
        attempts: 0,
        started: false,
        inFlight: false,
        userPaused: false,
        temporaryMuted: false,
        timer: null,
        stableTimer: null,
        deadline: Date.now() + 8000
      };
      autoplayStates.set(video, state);
      video.autoplay = true;
      video.setAttribute('autoplay', '');
      const retry = () => {
        if (!state.started && !state.userPaused) attempt();
      };
      video.addEventListener('loadedmetadata', retry);
      video.addEventListener('canplay', retry);
      video.addEventListener('pause', () => {
        if (!state.userPaused && Date.now() < state.deadline) {
          state.started = false;
          state.inFlight = false;
          clearTimeout(state.timer);
          clearTimeout(state.stableTimer);
          state.timer = setTimeout(retry, 120);
        }
      });
    }
    const scheduleRetry = () => {
      if (state.userPaused || state.started || Date.now() >= state.deadline) return;
      clearTimeout(state.timer);
      state.timer = setTimeout(attempt, Math.min(800, 120 + state.attempts * 80));
    };
    const complete = () => {
      state.inFlight = false;
      clearTimeout(state.timer);
      clearTimeout(state.stableTimer);
      // muted autoplay 获得媒体管线后再恢复音量，避免同一个任务内立刻取消静音
      // 被 Chromium 重新判定为有声自动播放而拒绝。
      setTimeout(() => {
        state.temporaryMuted = false;
        preferredAudio(video);
      }, 180);
      // 官网脚本可能在 play() Promise 成功后再次 pause；稳定播放一小段时间后
      // 才结束守护窗口，避免把这种二次暂停误判成自动播放成功。
      state.stableTimer = setTimeout(() => {
        if (video.paused) {
          scheduleRetry();
        } else {
          state.started = true;
        }
      }, 900);
    };
    const attempt = () => {
      if (state.userPaused || state.started || state.inFlight || Date.now() >= state.deadline) return;
      state.attempts += 1;
      state.inFlight = true;
      const playback = video.play();
      if (!playback?.then) {
        if (!video.paused) {
          complete();
        } else {
          state.inFlight = false;
          scheduleRetry();
        }
        return;
      }
      playback.then(complete).catch(() => {
        if (state.userPaused || state.started) return;
        state.temporaryMuted = true;
        video.muted = true;
        const mutedPlayback = video.play();
        if (mutedPlayback?.then) {
          mutedPlayback.then(complete).catch(() => {
            state.inFlight = false;
            scheduleRetry();
          });
        } else if (!video.paused) {
          complete();
        } else {
          state.inFlight = false;
          scheduleRetry();
        }
      });
    };
    attempt();
  };
  const formatTime = (seconds) => {
    if (!Number.isFinite(seconds) || seconds < 0) return '00:00';
    const value = Math.floor(seconds);
    const hours = Math.floor(value / 3600);
    const minutes = Math.floor((value % 3600) / 60);
    const secs = String(value % 60).padStart(2, '0');
    return hours > 0
      ? `${hours}:${String(minutes).padStart(2, '0')}:${secs}`
      : `${String(minutes).padStart(2, '0')}:${secs}`;
  };
  let controlsVideo = null;
  let hideControlsTimer = null;
  let fullscreenState = false;
  window.__juyingSetFullscreenState = (value) => {
    fullscreenState = Boolean(value);
    const button = document.querySelector('#juying-fullscreen');
    if (button) {
      button.textContent = fullscreenState ? '⛶' : '⛶';
      button.title = fullscreenState ? '退出全屏' : '全屏';
    }
  };
  const ensureControls = (video) => {
    if (controlsVideo === video && document.getElementById('juying-controls')) return;
    document.getElementById('juying-controls')?.remove();
    controlsVideo = video;
    const controls = document.createElement('div');
    controls.id = 'juying-controls';
    controls.className = 'visible';
    controls.innerHTML = `
      <div class="jy-timeline">
        <span class="jy-current-time">00:00</span>
        <input class="jy-progress" type="range" min="0" max="1000" value="0" aria-label="播放进度">
        <span class="jy-duration">00:00</span>
      </div>
      <div class="jy-row">
        <button id="juying-play" title="播放/暂停">▶</button>
        <button id="juying-previous" title="${isLive ? '上一个频道' : '上一集'}" ${isLive || canPlayPrevious ? '' : 'disabled'}>
          <svg viewBox="0 0 24 24"><path d="M6 6h2v12H6V6zm3.5 6 8.5 6V6l-8.5 6z"/></svg>
        </button>
        <button id="juying-next" title="${isLive ? '下一个频道' : '下一集'}" ${isLive || canPlayNext ? '' : 'disabled'}>
          <svg viewBox="0 0 24 24"><path d="M16 6h2v12h-2V6zM6 18l8.5-6L6 6v12z"/></svg>
        </button>
        <span class="jy-divider"></span>
        <div id="juying-quality-wrap" class="jy-menu-wrap">
          <button id="juying-quality" class="jy-text-button" title="清晰度">${window.__juyingPreferredQuality}</button>
          <div class="jy-menu">
            <button data-value="超清">超清</button><button data-value="高清">高清</button>
            <button data-value="标清">标清</button><button data-value="流畅">流畅</button>
          </div>
        </div>
        <div id="juying-rate-wrap" class="jy-menu-wrap">
          <button id="juying-rate" class="jy-text-button" title="倍速">${window.__juyingPlaybackRate}x</button>
          <div class="jy-menu">
            <button data-value="0.5">0.5x</button><button data-value="0.75">0.75x</button>
            <button data-value="1">1.0x</button><button data-value="1.25">1.25x</button>
            <button data-value="1.5">1.5x</button><button data-value="2">2.0x</button>
            <button data-value="3">3.0x</button>
          </div>
        </div>
        <button id="juying-episodes" class="jy-text-button jy-icon-text-button"
          title="${isLive ? '选择频道' : '选择剧集'}">
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M4 6h10v2H4V6zm0 5h7v2H4v-2zm0 5h7v2H4v-2zm10-5 6 4-6 4v-8z"/>
          </svg>
          <span>${isLive ? '选台' : '选集'}</span>
        </button>
        <span class="jy-spacer"></span>
        <span class="jy-divider"></span>
        <button id="juying-mute" title="静音">🔊</button>
        <input class="jy-volume" type="range" min="0" max="1" step="0.01" value="1" aria-label="音量">
        <button id="juying-fullscreen" title="全屏">⛶</button>
      </div>`;
    document.body.appendChild(controls);

    const progress = controls.querySelector('.jy-progress');
    const timeline = controls.querySelector('.jy-timeline');
    const currentTime = controls.querySelector('.jy-current-time');
    const durationTime = controls.querySelector('.jy-duration');
    const playButton = controls.querySelector('#juying-play');
    const muteButton = controls.querySelector('#juying-mute');
    const volume = controls.querySelector('.jy-volume');
    const quality = controls.querySelector('#juying-quality');
    const rate = controls.querySelector('#juying-rate');
    const qualityWrap = controls.querySelector('#juying-quality-wrap');
    const rateWrap = controls.querySelector('#juying-rate-wrap');
    const previous = controls.querySelector('#juying-previous');
    const next = controls.querySelector('#juying-next');
    const episodes = controls.querySelector('#juying-episodes');
    const fullscreen = controls.querySelector('#juying-fullscreen');

    const applyPreferredVolume = () => {
      if (autoplayStates.get(video)?.temporaryMuted) return;
      const preferredVolume = Math.max(0, Math.min(1, Number(window.__juyingVolume)));
      const preferredMuted = Boolean(window.__juyingMuted);
      if (Math.abs(video.volume - preferredVolume) > 0.001) video.volume = preferredVolume;
      if (video.muted !== preferredMuted) video.muted = preferredMuted;
    };
    const reportVolumePreference = () => postPayload({
      type: 'juying:volume',
      volume: window.__juyingVolume,
      muted: window.__juyingMuted,
      userInitiated: true
    });
    applyPreferredVolume();
    volume.value = String(video.muted ? 0 : video.volume);
    if (isLive) {
      timeline.style.display = 'none';
      rateWrap.style.display = 'none';
    }
    if (!hasEpisodes) episodes.style.display = 'none';

    const showControls = (keepVisible = false) => {
      controls.classList.add('visible');
      post('juying:controls', true);
      clearTimeout(hideControlsTimer);
      if (!keepVisible && !video.paused) {
        hideControlsTimer = setTimeout(() => {
          controls.classList.remove('visible');
          post('juying:controls', false);
        }, 4000);
      }
    };
    const updateTimeline = () => {
      const duration = video.duration;
      const ratio = Number.isFinite(duration) && duration > 0 ? video.currentTime / duration : 0;
      progress.value = String(Math.round(ratio * 1000));
      const played = Math.max(0, Math.min(100, ratio * 100));
      progress.style.background = `linear-gradient(to right, #29c76f 0%, #29c76f ${played}%, rgba(255,255,255,.34) ${played}%, rgba(255,255,255,.34) 100%)`;
      currentTime.textContent = formatTime(video.currentTime);
      durationTime.textContent = formatTime(duration);
      playButton.textContent = video.paused ? '▶' : '❚❚';
    };
    const updateVolume = () => {
      volume.value = String(video.muted ? 0 : video.volume);
      const level = Number(volume.value) * 100;
      volume.style.background = `linear-gradient(to right, #fff 0%, #fff ${level}%, rgba(255,255,255,.35) ${level}%, rgba(255,255,255,.35) 100%)`;
      muteButton.textContent = video.muted || video.volume === 0 ? '🔇' : '🔊';
    };

    playButton.addEventListener('click', () => {
      if (video.paused) video.play(); else { markUserPaused(video); video.pause(); }
    });
    video.addEventListener('click', () => {
      if (video.paused) video.play(); else { markUserPaused(video); video.pause(); }
    });
    video.addEventListener('timeupdate', updateTimeline);
    video.addEventListener('durationchange', updateTimeline);
    video.addEventListener('play', () => { updateTimeline(); showControls(); });
    video.addEventListener('pause', () => { updateTimeline(); showControls(true); });
    video.addEventListener('volumechange', () => {
      // 官网会为自动播放短暂静音，这不是用户偏好，必须恢复而不是回写。
      applyPreferredVolume();
      updateVolume();
    });
    progress.addEventListener('input', () => {
      cancelInitialResume();
      if (Number.isFinite(video.duration) && video.duration > 0) {
        video.currentTime = Number(progress.value) / 1000 * video.duration;
      }
    });
    muteButton.addEventListener('click', () => {
      window.__juyingMuted = !video.muted;
      applyPreferredVolume();
      updateVolume();
      reportVolumePreference();
    });
    volume.addEventListener('input', () => {
      window.__juyingMuted = false;
      window.__juyingVolume = Number(volume.value);
      applyPreferredVolume();
      updateVolume();
      reportVolumePreference();
    });
    const closeMenus = () => {
      qualityWrap.classList.remove('open');
      rateWrap.classList.remove('open');
    };
    const setupMenu = (
      wrap,
      trigger,
      initialValue,
      onSelected,
      markSelectionImmediately = true
    ) => {
      const options = Array.from(wrap.querySelectorAll('.jy-menu button'));
      const markActive = (value) => options.forEach((option) =>
        option.classList.toggle('active', option.dataset.value === String(value))
      );
      markActive(initialValue);
      trigger.addEventListener('click', (event) => {
        event.stopPropagation();
        const opening = !wrap.classList.contains('open');
        closeMenus();
        if (opening) wrap.classList.add('open');
        showControls(true);
      });
      options.forEach((option) => option.addEventListener('click', (event) => {
        event.stopPropagation();
        const value = option.dataset.value;
        if (markSelectionImmediately) markActive(value);
        onSelected(value);
        closeMenus();
        showControls();
      }));
    };
    setupMenu(qualityWrap, quality, window.__juyingPreferredQuality, (value) => {
      post('juying:quality-selected', value);
    }, false);
    setupMenu(rateWrap, rate, String(window.__juyingPlaybackRate), (raw) => {
      const value = Number(raw);
      rate.textContent = `${value}x`;
      window.__juyingSetPlaybackRate(value);
      post('juying:rate-selected', value);
    });
    document.addEventListener('click', closeMenus);
    previous.addEventListener('click', () => post('juying:previous'));
    next.addEventListener('click', () => post('juying:next'));
    episodes.addEventListener('click', () => post('juying:episodes'));
    fullscreen.addEventListener('click', () => post('juying:fullscreen-request', !fullscreenState));
    controls.addEventListener('mouseenter', () => showControls(true));
    controls.addEventListener('mouseleave', () => showControls());
    document.addEventListener('mousemove', () => showControls(), {passive: true});
    document.addEventListener('keydown', (event) => {
      if (!isCurrent()) return;
      showControls();
      if (event.code === 'Space') {
        event.preventDefault();
        if (video.paused) video.play(); else { markUserPaused(video); video.pause(); }
      }
      if (isLive && (event.code === 'ArrowUp' || event.code === 'PageUp' || event.code === 'ChannelDown')) {
        event.preventDefault(); post('juying:previous');
      }
      if (isLive && (event.code === 'ArrowDown' || event.code === 'PageDown' || event.code === 'ChannelUp')) {
        event.preventDefault(); post('juying:next');
      }
      if (!isLive && event.code === 'ArrowLeft') {
        cancelInitialResume();
        video.currentTime = Math.max(0, video.currentTime - 10);
      }
      if (!isLive && event.code === 'ArrowRight') {
        cancelInitialResume();
        video.currentTime = Math.min(video.duration || 0, video.currentTime + 15);
      }
    });
    updateTimeline(); updateVolume(); showControls();
  };
  const prepare = () => {
    if (!isCurrent()) return;
    const video = findVideo();
    if (!(video instanceof HTMLMediaElement)) {
      detectUnavailable();
      return;
    }
    // 保留央视页面的执行上下文，但从 video 向上逐层隐藏所有兄弟节点。
    // 相比保留宽泛的 player 容器，这会移除分享栏、节目单、广告和官网控件。
    for (let node = video; node && node !== document.body; node = node.parentElement) {
      const parent = node.parentElement;
      if (parent) for (const sibling of parent.children) {
        if (sibling !== node && sibling.id !== 'juying-controls') {
          sibling.style.setProperty('display', 'none', 'important');
        }
      }
      node.style.setProperty('display', 'block', 'important');
      node.style.setProperty('visibility', 'visible', 'important');
      if (node !== video) {
        node.style.setProperty('position', 'static', 'important');
        node.style.setProperty('transform', 'none', 'important');
        node.style.setProperty('width', '100%', 'important');
        node.style.setProperty('height', '100%', 'important');
      }
    }
    Object.assign(document.documentElement.style, {
      width: '100%', height: '100%', overflow: 'hidden', background: '#000'
    });
    Object.assign(document.body.style, {
      margin: '0', width: '100%', height: '100%', overflow: 'hidden', background: '#000'
    });
    video.controls = false;
    video.removeAttribute('controls');
    if (isLive) video.setAttribute('data-juying-live', 'true');
    video.setAttribute('playsinline', '');
    video.setAttribute('webkit-playsinline', 'webkit-playsinline');
    Object.assign(video.style, {
      position: 'fixed', inset: '0', width: '100vw', height: '100vh',
      maxWidth: 'none', maxHeight: 'none', objectFit: 'contain',
      zIndex: '2147483646', background: '#000', visibility: 'visible', display: 'block'
    });
    const controlsNeedInitialization =
      controlsVideo !== video || !document.getElementById('juying-controls');
    observeVideo();
    ensureControls(video);
    ensureAutoplay(video);
    // MutationObserver 会被官网播放器的进度和菜单更新频繁触发。只在播放器
    // 实例变化时启动切换，避免每次 DOM 变化都取消并重置正在进行的重试。
    if (controlsNeedInitialization) {
      window.__juyingSetQuality(window.__juyingPreferredQuality);
    }
    window.__juyingSetPlaybackRate(window.__juyingPlaybackRate);
    if (!ready) {
      ready = true;
      setTimeout(() => {
        document.documentElement.style.setProperty('visibility', 'visible', 'important');
        post('juying:ready');
      }, 200);
    }
  };
  new MutationObserver(prepare).observe(document, {childList: true, subtree: true});
  const announceFullscreen = () => post(
    'juying:fullscreen',
    Boolean(document.fullscreenElement || document.webkitFullscreenElement)
  );
  document.addEventListener('fullscreenchange', announceFullscreen);
  document.addEventListener('webkitfullscreenchange', announceFullscreen);
  window.addEventListener('load', () => {
    prepare(); setTimeout(prepare, 500); setTimeout(prepare, 1500);
  }, {once: true});
  setTimeout(() => {
    if (!ready && !unavailable) {
      post('juying:unavailable');
    }
  }, 12000);
  prepare();
  if (resumePending) resumeTimer = setTimeout(restoreInitialPosition, 250);
})();
''';
