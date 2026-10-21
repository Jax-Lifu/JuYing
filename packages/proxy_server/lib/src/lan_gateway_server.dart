import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

/// 可显式按需开启的局域网配置门户与投屏网关 (ADR-015)。
///
/// 所有写操作均要求短期 6 位配对会话 (Pairing PIN)，杜绝内网未授权推送。
class LanGatewayServer {
  LanGatewayServer({
    Uuid? uuid,
    Random? secureRandom,
    DateTime Function()? now,
  })  : _uuid = uuid ?? const Uuid(),
        _random = secureRandom ?? Random.secure(),
        _now = now ?? DateTime.now;

  final Uuid _uuid;
  final Random _random;
  final DateTime Function() _now;
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, DateTime> _sessions = <String, DateTime>{};
  HttpServer? _server;
  String? _pairingCode;
  int _port = 9979;

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get isRunning => _server != null;
  int get port => _port;
  String? get pairingCode => _pairingCode;

  Future<bool> start({int port = 9979}) async {
    if (isRunning) return true;
    _pairingCode = (100000 + _random.nextInt(900000)).toString();
    final router = Router()
      ..get('/api/status', _status)
      ..post('/api/pair', _pair)
      ..post('/api/push_config', _authorizedPush('config'))
      ..post('/api/push_stream', _authorizedPush('stream'))
      ..get('/', _portal);
    try {
      _server = await shelf_io.serve(
        const Pipeline().addHandler(router.call),
        InternetAddress.anyIPv4,
        port,
      );
      _port = _server!.port;
      return true;
    } on SocketException catch (_) {
      _pairingCode = null;
      return false;
    }
  }

  Response _status(Request request) => _jsonResponse(<String, Object>{
        'app': 'JuYing',
        'status': 'online',
        'pairingRequired': true,
      });

  Future<Response> _pair(Request request) async {
    final payload = await _readJson(request);
    if (payload == null || payload['code']?.toString() != _pairingCode) {
      return _jsonResponse(
        <String, Object>{'success': false, 'message': '配对码无效'},
        statusCode: HttpStatus.unauthorized,
      );
    }
    final token = _uuid.v4();
    _sessions[token] = _now().add(const Duration(minutes: 30));
    return _jsonResponse(<String, Object>{
      'success': true,
      'token': token,
      'expiresInSeconds': 1800,
    });
  }

  Handler _authorizedPush(String type) {
    return (Request request) async {
      if (!_isAuthorized(request)) {
        return _jsonResponse(
          <String, Object>{'success': false, 'message': '请先完成配对'},
          statusCode: HttpStatus.unauthorized,
        );
      }
      final payload = await _readJson(request);
      if (payload == null) {
        return _jsonResponse(
          <String, Object>{'success': false, 'message': 'JSON 格式无效'},
          statusCode: HttpStatus.badRequest,
        );
      }
      if (!_events.isClosed) {
        _events.add(<String, dynamic>{'type': type, 'payload': payload});
      }
      return _jsonResponse(<String, Object>{
        'success': true,
        'message': type == 'config' ? '配置已推送到聚映' : '视频已推送到播放器',
      });
    };
  }

  bool _isAuthorized(Request request) {
    final authorization = request.headers[HttpHeaders.authorizationHeader];
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return false;
    }
    final token = authorization.substring('Bearer '.length).trim();
    final expiresAt = _sessions[token];
    if (expiresAt == null || !expiresAt.isAfter(_now())) {
      _sessions.remove(token);
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>?> _readJson(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Response _portal(Request request) => Response.ok(
        _portalHtml,
        headers: const <String, String>{
          HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
        },
      );

  Response _jsonResponse(
    Map<String, Object> body, {
    int statusCode = HttpStatus.ok,
  }) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      },
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _pairingCode = null;
    _sessions.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}

const String _portalHtml = r'''
<!doctype html>
<html lang="zh-CN">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>聚映配对</title></head>
<body>
  <main>
    <h1>聚映局域网门户</h1>
    <p>请输入电视端显示的 6 位配对码。配对会话有效期为 30 分钟。</p>
    <input id="code" inputmode="numeric" maxlength="6" aria-label="配对码">
    <button onclick="pair()">配对</button>
    <p id="result"></p>
    <section id="push" hidden>
      <h2>推送内容</h2>
      <input id="configUrl" type="url" placeholder="TVBox 配置地址">
      <button onclick="push('/api/push_config', 'configUrl')">推送配置</button>
      <input id="streamUrl" type="url" placeholder="视频或直播地址">
      <button onclick="push('/api/push_stream', 'streamUrl')">推送视频</button>
    </section>
  </main>
  <script>
    const pairingCode = new URLSearchParams(window.location.search).get('code');
    if (pairingCode?.length === 6 && !Number.isNaN(Number(pairingCode))) {
      document.getElementById('code').value = pairingCode;
    }
    async function pair() {
      const response = await fetch('/api/pair', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({code: document.getElementById('code').value})
      });
      const data = await response.json();
      if (data.token) sessionStorage.setItem('juyingToken', data.token);
      document.getElementById('result').textContent = data.success ? '配对成功' : data.message;
      document.getElementById('push').hidden = !data.success;
    }
    async function push(path, inputId) {
      const token = sessionStorage.getItem('juyingToken');
      const url = document.getElementById(inputId).value.trim();
      const response = await fetch(path, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + token
        },
        body: JSON.stringify({url: url})
      });
      const data = await response.json();
      document.getElementById('result').textContent = data.message;
    }
  </script>
</body>
</html>
''';
