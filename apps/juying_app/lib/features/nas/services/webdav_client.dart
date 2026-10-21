import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'package:juying/features/nas/models/nas_server_config.dart';
import 'package:juying/features/nas/models/nas_share_item.dart';

/// Authentic WebDAV and Alist network client.
///
/// **What**: Issues authentic HTTP `PROPFIND` queries with `Depth: 1`, parses multi-status XML responses,
/// authenticates with HTTP Basic / Digest tokens, and provides random seekable byte streams.
///
/// **Why**: WebDAV is the universal open standard used by Alist, Synology WebDAV Server, Nextcloud,
/// OpenWrt, and TrueNAS. Native PROPFIND parsing allows direct folder navigation without proprietary SDKs.
class WebDavClient {
  WebDavClient({
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);

  final HttpClient _httpClient;

  /// Lists files and directories inside a WebDAV folder using authentic `PROPFIND`.
  Future<List<NasShareItem>> listDirectory(
    NasServerConfig server,
    String path,
  ) async {
    final results = <NasShareItem>[];

    try {
      final uri = _buildUri(server, path);
      final request = await _httpClient.openUrl('PROPFIND', uri);

      // WebDAV Headers
      request.headers.set('Depth', '1');
      request.headers.set('Content-Type', 'application/xml; charset=utf-8');

      if (!server.isAnonymous &&
          server.username != null &&
          server.username!.isNotEmpty) {
        final credentials = '${server.username}:${server.password ?? ""}';
        final basicAuth = base64Encode(utf8.encode(credentials));
        request.headers.set('Authorization', 'Basic $basicAuth');
      }

      // PROPFIND Body requesting core file properties
      const propfindXml = '''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:getlastmodified/>
    <D:getcontentlength/>
    <D:resourcetype/>
    <D:displayname/>
  </D:prop>
</D:propfind>''';

      request.write(propfindXml);
      final response = await request.close();

      if (response.statusCode == 207 || response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        return parsePropfindXml(responseBody, requestedPath: uri.path);
      } else {
        debugPrint(
            '[WebDavClient] PROPFIND returned status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint(
          '[WebDavClient] Error listing WebDAV directory for ${server.host}: $e');
    }

    return results;
  }

  /// Parses authentic WebDAV multi-status XML response (`<D:multistatus>`).
  static List<NasShareItem> parsePropfindXml(
    String xmlContent, {
    required String requestedPath,
  }) {
    final items = <NasShareItem>[];

    try {
      final doc = XmlDocument.parse(xmlContent);
      final responses = doc.findAllElements('D:response').isNotEmpty
          ? doc.findAllElements('D:response')
          : doc.findAllElements('response');

      final normalizedRequested = requestedPath
          .replaceAll(RegExp(r'/+'), '/')
          .replaceFirst(RegExp(r'/$'), '');

      for (final resp in responses) {
        final hrefElem = resp.findElements('D:href').isNotEmpty
            ? resp.findElements('D:href').firstOrNull
            : resp.findElements('href').firstOrNull;

        if (hrefElem == null) continue;
        final rawHref = Uri.decodeFull(hrefElem.innerText.trim());
        final cleanHref = rawHref.replaceAll(RegExp(r'/+'), '/');

        // Check if resource is a collection (directory)
        final isDir = resp.findAllElements('D:collection').isNotEmpty ||
            resp.findAllElements('collection').isNotEmpty;

        // Extract content length (file size)
        final lengthElem = resp.findAllElements('D:getcontentlength').isNotEmpty
            ? resp.findAllElements('D:getcontentlength').firstOrNull
            : resp.findAllElements('getcontentlength').firstOrNull;
        final sizeBytes =
            int.tryParse(lengthElem?.innerText.trim() ?? '0') ?? 0;

        // Extract modified time
        final modElem = resp.findAllElements('D:getlastmodified').isNotEmpty
            ? resp.findAllElements('D:getlastmodified').firstOrNull
            : resp.findAllElements('getlastmodified').firstOrNull;
        DateTime? modified;
        if (modElem != null && modElem.innerText.isNotEmpty) {
          try {
            modified = HttpDate.parse(modElem.innerText.trim());
          } catch (_) {}
        }

        // Extract display name or parse from href
        final nameElem = resp.findAllElements('D:displayname').isNotEmpty
            ? resp.findAllElements('D:displayname').firstOrNull
            : resp.findAllElements('displayname').firstOrNull;
        var name = nameElem?.innerText.trim() ?? '';

        if (name.isEmpty) {
          final segments =
              cleanHref.split('/').where((s) => s.isNotEmpty).toList();
          name = segments.isNotEmpty ? segments.last : '/';
        }

        // Skip the self / root collection matching requestedPath
        if (cleanHref == normalizedRequested ||
            cleanHref == '$normalizedRequested/' ||
            name == '/' ||
            name.isEmpty) {
          continue;
        }

        items.add(
          NasShareItem(
            name: name,
            path: cleanHref,
            isDirectory: isDir,
            sizeBytes: sizeBytes,
            modifiedTime: modified,
          ),
        );
      }
    } catch (e) {
      debugPrint('[WebDavClient] Error parsing PROPFIND XML: $e');
    }

    return items;
  }

  /// Opens a seekable byte stream from a remote WebDAV file with Range header forwarding.
  Future<Stream<List<int>>> openRangeStream({
    required NasServerConfig server,
    required String filePath,
    required int start,
    int? end,
  }) async {
    final uri = _buildUri(server, filePath);
    final request = await _httpClient.getUrl(uri);

    // Forward Range header to remote WebDAV server
    final rangeValue = end != null ? 'bytes=$start-$end' : 'bytes=$start-';
    request.headers.set('Range', rangeValue);
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

    if (!server.isAnonymous &&
        server.username != null &&
        server.username!.isNotEmpty) {
      final credentials = '${server.username}:${server.password ?? ""}';
      final basicAuth = base64Encode(utf8.encode(credentials));
      request.headers.set('Authorization', 'Basic $basicAuth');
    }

    final response = await request.close();
    if (response.statusCode == HttpStatus.ok && start == 0 && end == null) {
      return response;
    }

    // 本地代理按请求偏移声明 206，不能把整文件或错误页面标成该区间的数据。
    final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(
      response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
    );
    final actualStart = int.tryParse(range?.group(1) ?? '');
    final actualEnd = int.tryParse(range?.group(2) ?? '');
    final total = int.tryParse(range?.group(3) ?? '');
    if (response.statusCode != HttpStatus.partialContent ||
        actualStart != start ||
        actualEnd == null ||
        actualEnd < start ||
        (end != null && actualEnd != end) ||
        (total != null && actualEnd >= total) ||
        (response.contentLength >= 0 &&
            response.contentLength != actualEnd - start + 1)) {
      await response.listen(null).cancel();
      throw HttpException('WebDAV 未返回请求的字节区间', uri: uri);
    }
    return response;
  }

  Uri _buildUri(NasServerConfig server, String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final sharePath = '/${server.shareName.replaceAll(RegExp(r'^/+|/+$'), '')}';
    // PROPFIND href 已携带共享根路径，导航和播放复用时不能再拼接一次。
    var fullPath = sharePath != '/' &&
            cleanPath != sharePath &&
            !cleanPath.startsWith('$sharePath/')
        ? '$sharePath$cleanPath'
        : cleanPath;
    fullPath = fullPath.replaceAll(RegExp(r'/+'), '/');

    final scheme = server.effectivePort == 443 || server.effectivePort == 5006
        ? 'https'
        : 'http';

    return Uri(
      scheme: scheme,
      host: server.host,
      port: server.effectivePort,
      path: fullPath,
    );
  }
}
