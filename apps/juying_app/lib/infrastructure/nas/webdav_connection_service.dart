import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/nas/nas_credential_store.dart';
import '../../domain/models/nas_connection.dart';

enum NasConnectionCheck { available, unauthorized, unsupported, unreachable }

/// 单次 WebDAV 根目录浏览结果；不会写入索引或持久化任何私有路径。
class WebDavMediaFile {
  const WebDavMediaFile({
    required this.uri,
    required this.name,
  });

  final Uri uri;
  final String name;
}

class WebDavConnectionService {
  WebDavConnectionService({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  Future<NasConnectionCheck> verify({
    required NasConnection connection,
    required NasCredentials credentials,
  }) async {
    if (connection.protocol != NasProtocol.webDav ||
        !_isSafeEndpoint(connection.endpoint)) {
      return NasConnectionCheck.unsupported;
    }
    try {
      final response = await _client
          .send(http.Request('OPTIONS', connection.endpoint)
            ..headers['Authorization'] =
                'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}'
            ..headers['Depth'] = '0')
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 401 || response.statusCode == 403) {
        return NasConnectionCheck.unauthorized;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return NasConnectionCheck.available;
      }
      return NasConnectionCheck.unsupported;
    } on TimeoutException {
      return NasConnectionCheck.unreachable;
    } catch (_) {
      return NasConnectionCheck.unreachable;
    }
  }

  /// 只读取连接根目录的第一层视频文件。递归扫描、索引与离线缓存需另行实施。
  Future<List<WebDavMediaFile>> listRootMedia({
    required NasConnection connection,
    required NasCredentials credentials,
  }) async {
    if (connection.protocol != NasProtocol.webDav ||
        !_isSafeEndpoint(connection.endpoint)) {
      throw StateError('当前 NAS 连接不支持安全 WebDAV 浏览');
    }
    try {
      final request = http.Request('PROPFIND', connection.endpoint)
        ..headers.addAll({
          'Authorization': _authorization(credentials),
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        })
        ..body =
            '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><resourcetype/><getcontentlength/></prop></propfind>';
      final response =
          await _client.send(request).timeout(const Duration(seconds: 12));
      final body = await response.stream.bytesToString();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw StateError('NAS 认证失败');
      }
      if (response.statusCode != 207 &&
          (response.statusCode < 200 || response.statusCode >= 300)) {
        throw StateError('NAS 未返回可浏览的媒体目录');
      }
      return _parseRootMedia(connection.endpoint, body);
    } on TimeoutException {
      throw StateError('NAS 浏览超时');
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('无法读取 NAS 媒体目录');
    }
  }

  List<WebDavMediaFile> _parseRootMedia(Uri endpoint, String xml) {
    final results = <WebDavMediaFile>[];
    final responsePattern = RegExp(
      r'<(?:\w+:)?response\b[^>]*>([\s\S]*?)</(?:\w+:)?response>',
      caseSensitive: false,
    );
    final hrefPattern = RegExp(
      r'<(?:\w+:)?href\b[^>]*>\s*([^<]+?)\s*</(?:\w+:)?href>',
      caseSensitive: false,
    );
    final collectionPattern = RegExp(
      r'<(?:\w+:)?collection\b[^>]*/?>',
      caseSensitive: false,
    );
    for (final response in responsePattern.allMatches(xml)) {
      final fragment = response.group(1)!;
      if (collectionPattern.hasMatch(fragment)) continue;
      final href = hrefPattern.firstMatch(fragment)?.group(1)?.trim();
      if (href == null || href.isEmpty) continue;
      final uri = _resolveMember(endpoint, href);
      if (uri == null || !_isSupportedMediaPath(uri.path)) continue;
      final name = uri.pathSegments.last;
      results.add(WebDavMediaFile(uri: uri, name: name));
    }
    results.sort((left, right) => left.name.compareTo(right.name));
    return results;
  }

  Uri? _resolveMember(Uri endpoint, String href) {
    final root =
        endpoint.path.endsWith('/') ? endpoint.path : '${endpoint.path}/';
    final candidate = endpoint.replace(path: root).resolve(href);
    if (candidate.scheme != endpoint.scheme ||
        candidate.host != endpoint.host ||
        candidate.port != endpoint.port ||
        candidate.userInfo.isNotEmpty) {
      return null;
    }
    if (!candidate.path.startsWith(root) && candidate.path != endpoint.path) {
      return null;
    }
    return candidate;
  }

  bool _isSupportedMediaPath(String path) {
    final lower = path.toLowerCase();
    return const ['.mp4', '.mkv', '.mov', '.avi', '.webm', '.m4v', '.ts']
        .any(lower.endsWith);
  }

  String _authorization(NasCredentials credentials) =>
      'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}';

  static bool _isSafeEndpoint(Uri uri) =>
      uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;
}
