import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/proxy/local_proxy_server.dart';
import 'package:juying/features/nas/models/nas_server_config.dart';
import 'package:juying/features/nas/models/nas_remote_share.dart';
import 'package:juying/features/nas/models/nas_share_item.dart';
import 'package:juying/features/nas/services/lan_scanner.dart';
import 'package:juying/features/nas/services/nfs_client.dart';
import 'package:juying/features/nas/services/smb_client.dart';
import 'package:juying/features/nas/services/webdav_client.dart';

/// Comprehensive LAN NAS Storage Service (Samba SMBv2/v3, NFS, WebDAV, and Range Proxy).
///
/// **What**: Connects to authentic Samba, NFS, and WebDAV endpoints, queries directory trees,
/// probes active LAN subnets, scrapes local NFO/artwork metadata, and streams seekable 4K media
/// through `LocalProxyServer` (`http://127.0.0.1:9978/proxy/...`) with 206 Partial Content support.
///
/// **Why**: Media engines (`media_kit` / `libmpv`) cannot directly handle raw SMB/NFS socket state.
/// Translating all network storage streams into the local loopback Range HTTP proxy ensures random seeking,
/// external subtitle loading, multi-audio track switching, and zero RAM buffer bloat.
class LanNasService {
  LanNasService({
    LocalProxyServer? proxyServer,
    WebDavClient? webDavClient,
    LanScanner? lanScanner,
    SmbClient? smbClient,
    NfsClient? nfsClient,
  })  : _proxyServer = proxyServer ?? LocalProxyServer.instance,
        _webDavClient = webDavClient ?? WebDavClient(),
        _lanScanner = lanScanner ?? LanScanner(),
        _smbClient = smbClient ?? LibSmbClient(),
        _nfsClient = nfsClient ?? DartNfsClient();

  final LocalProxyServer _proxyServer;
  final WebDavClient _webDavClient;
  final LanScanner _lanScanner;
  final SmbClient _smbClient;
  final NfsClient _nfsClient;

  /// 使用应用内 SMB2/3 会话验证身份并列出真实磁盘共享。
  ///
  /// 不经过 Windows 重定向器，因此不会与资源管理器或系统盘符的凭据冲突。
  Future<List<NasRemoteShare>> listSmbShares(
    NasServerConfig server, {
    required String username,
    required String password,
  }) async {
    final cleanUser = username.trim();
    if (cleanUser.isEmpty && password.isNotEmpty) {
      throw const NasMountException('填写密码时必须同时填写用户名');
    }
    try {
      final shares = await _smbClient.listShares(
        host: server.host,
        username: cleanUser,
        password: password,
      );
      if (shares.isEmpty) {
        throw const NasMountException('该设备未公开可挂载的磁盘共享目录');
      }
      return shares;
    } on SmbClientException catch (error) {
      throw NasMountException(error.message);
    }
  }

  /// 通过应用内 ONC RPC 查询 mountd 的真实 export 列表。
  Future<List<NasRemoteShare>> listNfsExports(NasServerConfig server) async {
    try {
      final exports = await _nfsClient.listExports(server.host);
      if (exports.isEmpty) {
        throw const NasMountException('该 NFS 服务没有公开可挂载的导出目录');
      }
      return exports;
    } on NfsClientException catch (error) {
      throw NasMountException(error.message);
    }
  }

  /// 建立应用内 NFS 会话并返回选中的 export 配置，不创建系统盘符。
  Future<NasServerConfig> mountNfsExport(
    NasServerConfig server,
    NasRemoteShare export,
  ) async {
    final mounted = server.copyWith(
      id: '${server.id}_${export.path.hashCode.abs()}',
      name: '${server.hostname ?? server.host} · ${export.name}',
      shareName: export.path,
    );
    try {
      await _nfsClient.connect(mounted);
      return mounted;
    } on NfsClientException catch (error) {
      throw NasMountException(error.message);
    }
  }

  /// Lists files and directories inside a given NAS path using authentic protocols.
  Future<List<NasShareItem>> listDirectory(
    NasServerConfig server,
    String relativePath,
  ) async {
    // 1. Real WebDAV / Alist PROPFIND
    if (server.protocol == NasProtocol.webdav) {
      return _webDavClient.listDirectory(server, relativePath);
    }

    // 2. 应用内 libsmb2 目录访问，不借用系统挂载和 UNC 会话。
    if (server.protocol == NasProtocol.smb) {
      try {
        return await _smbClient.listDirectory(server, relativePath);
      } on SmbClientException catch (error) {
        throw NasMountException(error.message);
      }
    }

    if (server.protocol == NasProtocol.nfs) {
      try {
        return await _nfsClient.listDirectory(server, relativePath);
      } on NfsClientException catch (error) {
        throw NasMountException(error.message);
      }
    }

    return const <NasShareItem>[];
  }

  /// Registers a NAS file into the local loopback Range proxy, returning a seekable HTTP stream URL.
  String bridgeNasFileToProxy({
    required NasServerConfig server,
    required NasShareItem file,
  }) {
    final ownerId = 'nas:${server.id}';

    // 1. WebDAV Range Stream Provider
    if (server.protocol == NasProtocol.webdav) {
      return _proxyServer.registerStreamProxy(
        ownerId: ownerId,
        contentLength: file.sizeBytes > 0 ? file.sizeBytes : 1024 * 1024 * 500,
        contentType:
            file.name.endsWith('.mkv') ? 'video/x-matroska' : 'video/mp4',
        resolver: (int start, int? end) {
          return _webDavClient.openRangeStream(
            server: server,
            filePath: file.path,
            start: start,
            end: end,
          );
        },
      );
    }

    // 2. Samba Range 读取由应用内 libsmb2 直接完成，系统 SMB 状态不参与。
    if (server.protocol == NasProtocol.smb) {
      return _proxyServer.registerStreamProxy(
        ownerId: ownerId,
        contentLength: file.sizeBytes > 0 ? file.sizeBytes : 1024 * 1024 * 500,
        contentType:
            file.name.endsWith('.mkv') ? 'video/x-matroska' : 'video/mp4',
        resolver: (int start, int? end) async {
          try {
            return await _smbClient.openRangeStream(
              server: server,
              filePath: file.path,
              start: start,
              end: end,
            );
          } on SmbClientException catch (error) {
            throw NasMountException(error.message);
          }
        },
      );
    }

    // 3. NFS Range 读取同样走应用内 ONC RPC，不依赖盘符和系统内核挂载。
    return _proxyServer.registerStreamProxy(
      ownerId: ownerId,
      contentLength: file.sizeBytes > 0 ? file.sizeBytes : 1024 * 1024 * 500,
      contentType:
          file.name.endsWith('.mkv') ? 'video/x-matroska' : 'video/mp4',
      resolver: (int start, int? end) async {
        try {
          return await _nfsClient.openRangeStream(
            server: server,
            filePath: file.path,
            start: start,
            end: end,
          );
        } on NfsClientException catch (error) {
          throw NasMountException(error.message);
        }
      },
    );
  }

  /// Scans LAN broadcast domain for active Samba, NFS, and WebDAV servers using real socket probes.
  Future<List<NasServerConfig>> discoverLanServers() async {
    return _lanScanner.scanSubnet();
  }

  /// Unmounts and disconnects a NAS server connection, releasing active network sessions and stream proxies.
  Future<void> unmountServer(NasServerConfig server) async {
    try {
      // 1. Purge active local loopback Range stream tokens
      _proxyServer.unregisterOwner('nas:${server.id}');

      // 2. Samba 仅释放应用内 native 会话，不触碰用户的系统网络映射。
      if (server.protocol == NasProtocol.smb) {
        await _smbClient.disconnect(server);
      } else if (server.protocol == NasProtocol.nfs) {
        await _nfsClient.disconnect(server);
      }
    } catch (e) {
      debugPrint(
          '[LanNasService] Error unmounting NAS server ${server.name}: $e');
    }
  }

  /// Parses Kodi / Emby standard `movie.nfo` or `tvshow.nfo` XML into a structured [MediaItem].
  static MediaItem? parseNfoXml(String nfoContent, {required String fileId}) {
    try {
      final doc = XmlDocument.parse(nfoContent);

      final title = doc
              .findAllElements('title')
              .firstOrNull
              ?.innerText
              .trim() ??
          doc.findAllElements('originaltitle').firstOrNull?.innerText.trim();
      if (title == null || title.isEmpty) return null;

      final plot = doc.findAllElements('plot').firstOrNull?.innerText.trim() ??
          doc.findAllElements('outline').firstOrNull?.innerText.trim();

      final year = doc.findAllElements('year').firstOrNull?.innerText.trim() ??
          doc.findAllElements('premiered').firstOrNull?.innerText.trim();

      final ratingStr =
          doc.findAllElements('rating').firstOrNull?.innerText.trim() ??
              doc.findAllElements('value').firstOrNull?.innerText.trim();
      final rating = double.tryParse(ratingStr ?? '');

      final genres = doc
          .findAllElements('genre')
          .map((e) => e.innerText.trim())
          .where((g) => g.isNotEmpty)
          .toList();

      final poster =
          doc.findAllElements('poster').firstOrNull?.innerText.trim() ??
              doc.findAllElements('thumb').firstOrNull?.innerText.trim();

      return MediaItem(
        id: 'nas_$fileId',
        title: title,
        overview: plot,
        year: year,
        rating: rating,
        genres: genres,
        posterUrl: poster,
      );
    } catch (e) {
      debugPrint('[LanNasService] Error parsing NFO XML: $e');
      return null;
    }
  }
}

/// NAS 共享枚举、身份验证或系统挂载失败。
class NasMountException implements Exception {
  const NasMountException(this.message);

  final String message;

  @override
  String toString() => message;
}
