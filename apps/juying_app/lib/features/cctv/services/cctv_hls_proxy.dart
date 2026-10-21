import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'package:juying/features/cctv/services/cctv_h5e_decoder.dart';

/// Serves a complete VOD timeline to libmpv while converting H5E segments on
/// demand. Random session URLs are reachable only from this computer.
class CctvHlsProxy {
  CctvHlsProxy({
    this.onError,
    Future<Uint8List> Function(Uint8List)? decodeSegment,
  }) : _decode = decodeSegment ?? decodeCctvH5eSegment;

  /// Reports the first upstream/decoder failure in the current session only.
  void Function(Object error)? onError;
  final Future<Uint8List> Function(Uint8List) _decode;
  Future<HttpServer>? _binding;
  _HlsSession? _session;
  bool _disposed = false;

  /// Replaces the previous episode/quality atomically, cancelling its network
  /// work. The manifest must describe complete TS segments and an ended VOD.
  Future<String> open(String mediaPlaylistUrl,
      {Map<String, String>? headers}) async {
    if (_disposed) throw StateError('CCTV proxy is disposed');
    _session?.close();
    final session = _HlsSession(headers ?? const <String, String>{});
    _session = session;
    try {
      final server = await (_binding ??= _bind());
      _requireCurrent(session);
      final uri = _httpUri(mediaPlaylistUrl);
      final manifest = await _fetch(session, uri, 1024 * 1024);
      _requireCurrent(session);
      final lines = const LineSplitter().convert(utf8.decode(manifest.bytes));
      if (lines.isEmpty ||
          lines.first.replaceFirst('\uFEFF', '').trim() != '#EXTM3U' ||
          !lines.any((line) => line.trim() == '#EXT-X-ENDLIST')) {
        throw const FormatException('Expected complete CCTV VOD playlist');
      }
      final output = <String>[];
      var expectsSegment = false;
      for (final raw in lines) {
        final line = raw.trim();
        if (line.startsWith('#EXT-X-KEY:') ||
            line.startsWith('#EXT-X-MAP:') ||
            line.startsWith('#EXT-X-BYTERANGE:') ||
            line.startsWith('#EXT-X-STREAM-INF:') ||
            line.contains('URI=')) {
          throw const FormatException('Unsupported CCTV segment format');
        }
        if (line.isEmpty || line.startsWith('#')) {
          output.add(line);
          if (line.startsWith('#EXTINF:')) expectsSegment = true;
          continue;
        }
        if (!expectsSegment || session.segments.length >= 10000) {
          throw const FormatException('Invalid CCTV segment list');
        }
        final index = session.segments.length;
        session.segments.add(_httpUri(manifest.uri.resolve(line).toString()));
        output
            .add('http://127.0.0.1:${server.port}/${session.token}/$index.ts');
        expectsSegment = false;
      }
      if (session.segments.isEmpty || expectsSegment) {
        throw const FormatException('Empty or incomplete CCTV segment list');
      }
      session.playlist =
          Uint8List.fromList(utf8.encode('${output.join('\n')}\n'));
      return 'http://127.0.0.1:${server.port}/${session.token}/index.m3u8';
    } catch (_) {
      session.close();
      rethrow;
    }
  }

  Future<HttpServer> _bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => unawaited(_serve(request)));
    return server;
  }

  Future<void> _serve(HttpRequest request) async {
    final session = _session;
    try {
      final path = request.uri.pathSegments;
      if (_disposed ||
          session == null ||
          session.closed ||
          path.length != 2 ||
          path.first != session.token) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final isPlaylist = path.last == 'index.m3u8';
      final index = int.tryParse(path.last.replaceFirst(RegExp(r'\.ts$'), ''));
      if (!isPlaylist &&
          (index == null || index < 0 || index >= session.segments.length)) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      Uint8List data;
      try {
        data = isPlaylist ? session.playlist : await _segment(session, index!);
        _requireCurrent(session);
      } catch (error) {
        request.response.statusCode = HttpStatus.badGateway;
        if (_session == session && !session.closed && !session.failed) {
          session.failed = true;
          onError?.call(error);
        }
        return;
      }
      final response = request.response;
      response.headers.set(HttpHeaders.contentTypeHeader,
          isPlaylist ? 'application/vnd.apple.mpegurl' : 'video/mp2t');
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      var start = 0;
      var end = data.length - 1;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        final first = int.tryParse(match?.group(1) ?? '');
        final last = int.tryParse(match?.group(2) ?? '');
        if (match == null ||
            (match.group(1)!.isNotEmpty && first == null) ||
            (match.group(2)!.isNotEmpty && last == null) ||
            (first == null && (last == null || last <= 0)) ||
            (first != null &&
                (first >= data.length || (last != null && last < first)))) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers
              .set(HttpHeaders.contentRangeHeader, 'bytes */${data.length}');
          return;
        }
        start = first ?? max(0, data.length - last!);
        end = first == null ? end : min(last ?? end, end);
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
            HttpHeaders.contentRangeHeader, 'bytes $start-$end/${data.length}');
      }
      response.contentLength = end - start + 1;
      if (request.method != 'HEAD') {
        response.add(Uint8List.sublistView(data, start, end + 1));
      }
    } on Object {
      // A seek/episode change can close the player's socket before our reply.
    } finally {
      try {
        await request.response.close();
      } on Object {
        // The player already cancelled this response.
      }
    }
  }

  Future<Uint8List> _segment(_HlsSession session, int index) {
    final cached = session.cache[index];
    if (cached != null) return Future.value(cached);
    return session.pending.putIfAbsent(index, () {
      // Serial conversion bounds peak memory and avoids simultaneous decoders.
      final work = session.tail.then((_) async {
        _requireCurrent(session);
        final input =
            await _fetch(session, session.segments[index], 32 * 1024 * 1024);
        _requireCurrent(session);
        final data = await _decode(input.bytes);
        _requireCurrent(session);
        session.cache[index] = data;
        while (session.cache.length > 3) {
          session.cache.remove(session.cache.keys.first);
        }
        return data;
      }).whenComplete(() {
        session.pending.remove(index);
      });
      session.tail =
          work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      return work;
    });
  }

  Future<({Uint8List bytes, Uri uri})> _fetch(
      _HlsSession session, Uri uri, int limit) async {
    final request =
        await session.client.getUrl(uri).timeout(const Duration(seconds: 15));
    session.headers.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > limit) {
      request.abort();
      throw const HttpException('CCTV upstream rejected the media request');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      _requireCurrent(session);
      if (bytes.length + chunk.length > limit) {
        request.abort();
        throw const FormatException('CCTV media exceeds buffer limit');
      }
      bytes.add(chunk);
    }
    if (bytes.isEmpty) throw const FormatException('Empty CCTV media response');
    var resolved = uri;
    for (final redirect in response.redirects) {
      resolved = resolved.resolveUri(redirect.location);
    }
    return (bytes: bytes.takeBytes(), uri: resolved);
  }

  Uri _httpUri(String value) {
    final uri = Uri.parse(value);
    if (!const <String>['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Expected HTTP CCTV media URL');
    }
    return uri;
  }

  void _requireCurrent(_HlsSession session) {
    if (_disposed || session.closed || session != _session) {
      throw StateError('CCTV playback session replaced');
    }
  }

  /// Cancels upstream reads and releases the listening socket and cached media.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _session?.close();
    _session = null;
    if (_binding != null) await (await _binding!).close(force: true);
  }
}

class _HlsSession {
  _HlsSession(Map<String, String> headers)
      : headers = Map<String, String>.unmodifiable(headers);

  final String token = const Uuid().v4();
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  final Map<String, String> headers;
  final List<Uri> segments = <Uri>[];
  final Map<int, Uint8List> cache = <int, Uint8List>{};
  final Map<int, Future<Uint8List>> pending = <int, Future<Uint8List>>{};
  Future<void> tail = Future<void>.value();
  Uint8List playlist = Uint8List(0);
  bool closed = false;
  bool failed = false;

  void close() {
    closed = true;
    client.close(force: true);
    cache.clear();
  }
}
