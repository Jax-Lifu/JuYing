import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

typedef StreamSourceResolver = Future<Stream<List<int>>> Function(
  int start,
  int? end,
);

/// 仅向本机播放器暴露可随机访问的 HTTP Range 流 (ADR-015 / ADR-006)。
///
/// 独立绑定回环地址 (127.0.0.1) 可以保证 NAS 凭据与媒体字节不会因远程配置门户开启而
/// 暴露到局域网；随机 UUID 令已注册流无法通过文件名或自增编号枚举。
class LoopbackStreamProxy {
  LoopbackStreamProxy({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  final Map<String, _RegisteredStream> _streams = <String, _RegisteredStream>{};
  HttpServer? _server;
  int _port = 9978;

  bool get isRunning => _server != null;
  int get port => _port;

  String register({
    required StreamSourceResolver resolver,
    required int contentLength,
    required String ownerId,
    String contentType = 'video/mp4',
  }) {
    if (contentLength <= 0) {
      throw ArgumentError.value(
        contentLength,
        'contentLength',
        '必须为正整数，以便校验 Range 边界',
      );
    }
    final token = _uuid.v4();
    _streams[token] = _RegisteredStream(
      resolver: resolver,
      contentLength: contentLength,
      contentType: contentType,
      ownerId: ownerId,
    );
    return 'http://127.0.0.1:$_port/proxy/$token';
  }

  void unregisterOwner(String ownerId) {
    _streams.removeWhere((_, stream) => stream.ownerId == ownerId);
  }

  void unregisterOwnersWithPrefix(String prefix) {
    _streams.removeWhere((_, stream) => stream.ownerId.startsWith(prefix));
  }

  @visibleForTesting
  bool containsToken(String token) => _streams.containsKey(token);

  Future<bool> start({int port = 9978}) async {
    if (isRunning) return true;
    final router = Router()
      ..head('/proxy/<token>', _handleProxyStream)
      ..get('/proxy/<token>', _handleProxyStream);
    try {
      _server = await shelf_io.serve(
        const Pipeline().addHandler(router.call),
        InternetAddress.loopbackIPv4,
        port,
      );
      _port = _server!.port;
      return true;
    } on SocketException catch (_) {
      return false;
    }
  }

  Future<Response> _handleProxyStream(Request request, String token) async {
    final source = _streams[token];
    if (source == null) return Response.notFound('Stream token not registered');

    final isHead = request.method == 'HEAD';
    final rangeHeader = isHead ? null : request.headers['range'];
    final range = _parseRange(rangeHeader, source.contentLength);
    if (range == null && rangeHeader != null) {
      return Response(
        HttpStatus.requestedRangeNotSatisfiable,
        headers: <String, String>{
          'Content-Range': 'bytes */${source.contentLength}',
        },
      );
    }

    final start = range?.start ?? 0;
    final end = range?.end ?? source.contentLength - 1;
    final body = isHead ? null : await source.resolver(start, range?.end);
    return Response(
      range == null ? HttpStatus.ok : HttpStatus.partialContent,
      body: body,
      headers: <String, String>{
        'Content-Type': source.contentType,
        'Accept-Ranges': 'bytes',
        'Content-Length': (end - start + 1).toString(),
        if (range != null)
          'Content-Range': 'bytes $start-$end/${source.contentLength}',
      },
    );
  }

  _ByteRange? _parseRange(String? value, int totalLength) {
    if (value == null) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value);
    if (match == null) return null;
    if (match.group(1)!.isEmpty) {
      final suffixLength = int.tryParse(match.group(2)!);
      if (suffixLength == null || suffixLength <= 0) return null;
      return _ByteRange(max(0, totalLength - suffixLength), totalLength - 1);
    }
    final start = int.tryParse(match.group(1)!);
    final requestedEnd = match.group(2)!.isEmpty
        ? totalLength - 1
        : int.tryParse(match.group(2)!);
    if (start == null ||
        requestedEnd == null ||
        start < 0 ||
        start >= totalLength ||
        requestedEnd < start) {
      return null;
    }
    return _ByteRange(start, min(requestedEnd, totalLength - 1));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _streams.clear();
  }
}

class _RegisteredStream {
  const _RegisteredStream({
    required this.resolver,
    required this.contentLength,
    required this.contentType,
    required this.ownerId,
  });

  final StreamSourceResolver resolver;
  final int contentLength;
  final String contentType;
  final String ownerId;
}

class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;
}
