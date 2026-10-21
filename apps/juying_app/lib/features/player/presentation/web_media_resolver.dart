import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_windows/webview_windows.dart' as windows;

import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/models/playback_candidate.dart';

/// A user cancellation must not trigger automatic source failover or downloads.
class WebMediaResolutionCancelled implements Exception {
  const WebMediaResolutionCancelled();

  @override
  String toString() => 'Web media resolution cancelled';
}

/// Opens an ordinary player page for at most 12 seconds and returns its media URL.
/// The caller owns subsequent playback; closing the dialog releases the browser.
Future<PlaybackEpisode> resolveWebMedia(
  BuildContext context,
  PlaybackEpisode episode,
) async {
  // Playback can request resolution from initState; dialogs require the first
  // frame's Navigator and inherited widgets to have finished mounting.
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) throw const WebMediaResolutionCancelled();
  final page = Uri.tryParse(episode.url);
  if (page == null || !_isHttp(page)) {
    throw StateError(context.tr('player_web_unavailable'));
  }
  final result = await showDialog<Object>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WebMediaDialog(episode: episode),
  );
  if (result is PlaybackEpisode) return result;
  throw result ?? const WebMediaResolutionCancelled();
}

bool _isHttp(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;

class _WebMediaDialog extends StatefulWidget {
  const _WebMediaDialog({required this.episode});

  final PlaybackEpisode episode;

  @override
  State<_WebMediaDialog> createState() => _WebMediaDialogState();
}

class _WebMediaDialogState extends State<_WebMediaDialog> {
  windows.WebviewController? _windows;
  mobile.WebViewController? _mobile;
  StreamSubscription<dynamic>? _messages;
  Timer? _timeout;
  bool _ready = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 12), () {
      _finish(TimeoutException(context.tr('player_web_timeout')));
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final navigationHeaders =
          widget.episode.webHeaders ?? widget.episode.headers;
      final userAgent = _header('user-agent', navigationHeaders);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        final controller = windows.WebviewController();
        _windows = controller;
        await controller.initialize();
        // Cancellation can win while native WebView2 creation is still pending.
        // Only its completed controller may be disposed, and it must never load.
        if (_closed) {
          await controller.dispose();
          return;
        }
        _ready = true;
        await controller.setPopupWindowPolicy(
          windows.WebviewPopupWindowPolicy.deny,
        );
        if (userAgent != null) await controller.setUserAgent(userAgent);
        if (_closed) return;
        _messages = controller.webMessage.listen(_onMessage);
        await controller.addScriptToExecuteOnDocumentCreated(_snifferScript);
        if (_closed) return;
        setState(() {});
        // This plugin has no navigation-headers API. Source headers are retained
        // for mpv, while only User-Agent can be applied to the initial web page.
        await controller.loadUrl(widget.episode.url);
      } else if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        final controller = mobile.WebViewController();
        _mobile = controller;
        await controller.setJavaScriptMode(mobile.JavaScriptMode.unrestricted);
        if (userAgent != null) await controller.setUserAgent(userAgent);
        await controller.addJavaScriptChannel(
          'JuyingMedia',
          onMessageReceived: (message) => _onMessage(message.message),
        );
        await controller.setNavigationDelegate(mobile.NavigationDelegate(
          onPageStarted: (_) => unawaited(_injectMobile()),
          onPageFinished: (_) => unawaited(_injectMobile()),
        ));
        if (_closed) return;
        setState(() => _ready = true);
        await controller.loadRequest(
          Uri.parse(widget.episode.url),
          headers: navigationHeaders ?? const {},
        );
      } else {
        // Schedule after initState so translated labels can read Localizations.
        await Future<void>.value();
        if (!_closed && mounted) {
          _finish(StateError(context.tr('player_web_unsupported')));
        }
      }
    } catch (_) {
      if (!_closed && mounted) {
        _finish(StateError(context.tr('player_web_unavailable')));
      }
    }
  }

  String? _header(String name, Map<String, String>? headers) {
    for (final entry
        in headers?.entries ?? const <MapEntry<String, String>>[]) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  Future<void> _injectMobile() async {
    if (_closed) return;
    try {
      await _mobile?.runJavaScript(_snifferScript);
    } catch (_) {
      // A redirect may remove the document between page callbacks; the next
      // document receives the hook again and the session deadline still applies.
    }
  }

  void _onMessage(dynamic message) {
    if (_closed) return;
    try {
      final data = message is String ? jsonDecode(message) : message;
      if (data is! Map || data['type'] != 'juying:media') return;
      final url = Uri.tryParse(data['url'] as String);
      if (url == null ||
          !_isHttp(url) ||
          !RegExp(r'\.(m3u8|mp4|mpd|flv)$', caseSensitive: false)
              .hasMatch(url.path)) {
        return;
      }
      final page = Uri.tryParse(data['page'] as String? ?? '');
      final headers = <String, String>{...?widget.episode.headers};
      final agent = data['userAgent'] as String?;
      if (_header('user-agent', headers) == null &&
          agent != null &&
          agent.isNotEmpty) {
        headers['User-Agent'] = agent;
      }
      if (_header('referer', headers) == null) {
        headers['Referer'] = page != null && _isHttp(page)
            ? page.removeFragment().toString()
            : widget.episode.url;
      }
      final episode = widget.episode;
      _finish(PlaybackEpisode(
        name: episode.name,
        url: url.toString(),
        sortIndex: episode.sortIndex,
        duration: episode.duration,
        badge: episode.badge,
        headers: headers,
        officialPageUrl: episode.officialPageUrl,
        thumbnailUrl: episode.thumbnailUrl,
      ));
    } catch (_) {
      // A page may send unrelated messages through the shared browser bridge.
    }
  }

  void _finish(Object? result) {
    if (_closed || !mounted) return;
    _closed = true;
    _timeout?.cancel();
    // Back navigation may already be reversing this route while a late browser
    // message arrives. Never let it pop the underlying player page as well.
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _release() async {
    await _messages?.cancel();
    if (_windows != null && _ready) {
      await _windows!.dispose();
    }
    final controller = _mobile;
    if (controller != null) {
      // webview_flutter releases its native view on widget removal. Blank the
      // document too so script timers and media cannot continue in its controller.
      await controller.loadRequest(Uri.parse('about:blank'));
    }
  }

  @override
  void dispose() {
    _closed = true;
    _timeout?.cancel();
    unawaited(_release().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('player_web_resolving')),
        content: SizedBox(
          width: 720,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('player_web_hint')),
              const SizedBox(height: 12),
              Expanded(
                child: !_ready
                    ? const Center(child: CircularProgressIndicator())
                    : _windows != null
                        ? windows.Webview(_windows!)
                        : mobile.WebViewWidget(controller: _mobile!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('web-media-cancel'),
            onPressed: () => _finish(null),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
      );
}

// One bridge works with WebView2's document-start injection and mobile page
// callbacks. Successful browser media entries recover loads before injection;
// fetch/XHR responses are checked directly so challenge pages cannot win.
const _snifferScript = r'''
(() => {
  if (window.__juyingMediaSniffer) return;
  window.__juyingMediaSniffer = true;
  let found = false;
  function report(value) {
    if (found || !value) return;
    try {
      const url = new URL(String(value), document.baseURI);
      if (!/^https?:$/.test(url.protocol) ||
          !/\.(m3u8|mp4|mpd|flv)$/i.test(url.pathname)) return;
      const message = {type: 'juying:media', url: url.href,
        page: location.href, userAgent: navigator.userAgent};
      if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage(message);
      } else if (window.JuyingMedia) {
        window.JuyingMedia.postMessage(JSON.stringify(message));
      } else return;
      found = true;
    } catch (_) {}
  }
  function scan() {
    document.querySelectorAll('video').forEach(video => {
      if (video.readyState > 0 && !video.error) report(video.currentSrc || video.src);
    });
    performance.getEntriesByType('resource').forEach(resource);
  }
  function resource(entry) {
    // A completed request alone is not evidence of success: the player may be
    // retrying a 403 or an HTML challenge before it obtains the actual stream.
    if (entry.initiatorType !== 'fetch' && entry.initiatorType !== 'xmlhttprequest' &&
        entry.responseStatus >= 200 && entry.responseStatus < 300) report(entry.name);
  }
  function mediaResponse(status, type) {
    return status >= 200 && status < 300 &&
      !/text\/html|application\/(json|xhtml)/i.test(type || '');
  }
  const fetch = window.fetch;
  window.fetch = function(input) {
    const url = typeof input === 'string' || input instanceof URL ? input : input.url;
    return fetch.apply(this, arguments).then(response => {
      if (mediaResponse(response.status, response.headers.get('content-type'))) {
        report(response.url || url);
      }
      return response;
    });
  };
  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    this.addEventListener('load', () => {
      if (mediaResponse(this.status, this.getResponseHeader('content-type'))) {
        report(this.responseURL || url);
      }
    }, {once: true});
    return open.apply(this, arguments);
  };
  if (window.PerformanceObserver) {
    new PerformanceObserver(list => list.getEntries().forEach(resource))
      .observe({entryTypes: ['resource']});
  }
  document.addEventListener('DOMContentLoaded', scan);
  setInterval(scan, 300);
  scan();
})();
''';
