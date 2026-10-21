import 'dart:async';

import 'package:dart_smb2/dart_smb2.dart';

import 'package:juying/features/nas/models/nas_remote_share.dart';
import 'package:juying/features/nas/models/nas_server_config.dart';
import 'package:juying/features/nas/models/nas_share_item.dart';

/// 应用内 Samba 协议客户端契约，隔离平台文件系统和系统 SMB 会话。
abstract interface class SmbClient {
  Future<List<NasRemoteShare>> listShares({
    required String host,
    required String username,
    required String password,
  });

  Future<List<NasShareItem>> listDirectory(
    NasServerConfig server,
    String relativePath,
  );

  Future<Stream<List<int>>> openRangeStream({
    required NasServerConfig server,
    required String filePath,
    required int start,
    required int? end,
  });

  Future<void> disconnect(NasServerConfig server);
}

/// 基于 libsmb2 的跨平台客户端；每个挂载项维护独立凭据和连接池。
///
/// Windows 的 SMB 重复凭据限制只存在于系统重定向器中。应用直接建立 SMB2/3
/// 会话可让不同挂载使用不同账号，也能在移动端复用完全相同的数据通路。
class LibSmbClient implements SmbClient {
  final Map<String, _SmbSession> _sessions = <String, _SmbSession>{};

  @override
  Future<List<NasRemoteShare>> listShares({
    required String host,
    required String username,
    required String password,
  }) async {
    final identity = _parseIdentity(username);
    try {
      final shares = await Smb2Pool.listSharesOn(
        host: host,
        user: identity.username,
        password: password.isEmpty ? null : password,
        domain: identity.domain,
        timeoutSeconds: 8,
      );
      return shares
          .where((share) => share.isDisk && !share.isHidden)
          .map(
            (share) => NasRemoteShare(
              name: share.name,
              path: share.name,
            ),
          )
          .toList(growable: false);
    } on Smb2Exception catch (error) {
      throw SmbClientException(_friendlyMessage(error));
    }
  }

  @override
  Future<List<NasShareItem>> listDirectory(
    NasServerConfig server,
    String relativePath,
  ) async {
    try {
      final pool = await _poolFor(server);
      final cleanPath = _cleanPath(relativePath);
      final entries = await pool.listDirectory(cleanPath);
      return entries
          .map(
            (entry) => NasShareItem(
              name: entry.name,
              path: '$cleanPath/${entry.name}'.replaceAll(RegExp(r'^/+'), ''),
              isDirectory: entry.isDirectory,
              sizeBytes: entry.size,
              modifiedTime: entry.stat.modified,
            ),
          )
          .toList(growable: false);
    } on Smb2Exception catch (error) {
      throw SmbClientException(_friendlyMessage(error));
    }
  }

  @override
  Future<Stream<List<int>>> openRangeStream({
    required NasServerConfig server,
    required String filePath,
    required int start,
    required int? end,
  }) async {
    try {
      final pool = await _poolFor(server);
      return _readRange(
        pool,
        _cleanPath(filePath),
        start: start,
        end: end,
      );
    } on Smb2Exception catch (error) {
      throw SmbClientException(_friendlyMessage(error));
    }
  }

  Stream<List<int>> _readRange(
    Smb2Pool pool,
    String path, {
    required int start,
    required int? end,
  }) async* {
    const chunkSize = 1024 * 1024;
    final fileSize = await pool.fileSize(path);
    if (fileSize <= 0 || start >= fileSize) return;
    final lastByte = (end ?? fileSize - 1).clamp(start, fileSize - 1);
    var offset = start;
    while (offset <= lastByte) {
      final length = (lastByte - offset + 1).clamp(1, chunkSize);
      final bytes = await pool.readFileRange(
        path,
        offset: offset,
        length: length,
      );
      if (bytes.isEmpty) return;
      offset += bytes.length;
      yield bytes;
    }
  }

  Future<Smb2Pool> _poolFor(NasServerConfig server) async {
    final signature = Object.hash(
      server.host,
      server.shareName,
      server.username,
      server.password,
    );
    final current = _sessions[server.id];
    if (current != null && current.signature == signature) {
      return current.pool;
    }
    if (current != null) {
      try {
        await (await current.pool).disconnect();
      } catch (_) {
        // 旧连接已经失效时继续创建新会话，不能让清理错误阻断重新挂载。
      }
    }

    final identity = _parseIdentity(server.username ?? '');
    final pool = Smb2Pool.connect(
      host: server.host,
      share: server.shareName,
      user: identity.username,
      password: (server.password?.isEmpty ?? true) ? null : server.password,
      domain: identity.domain,
      workers: 2,
      timeoutSeconds: 10,
    );
    _sessions[server.id] = _SmbSession(signature, pool);
    try {
      return await pool;
    } catch (_) {
      _sessions.remove(server.id);
      rethrow;
    }
  }

  @override
  Future<void> disconnect(NasServerConfig server) async {
    final session = _sessions.remove(server.id);
    if (session == null) return;
    try {
      await (await session.pool).disconnect();
    } catch (_) {
      // 断线中的 native 会话仍需从缓存移除，避免下次挂载复用失效连接。
    }
  }

  String _cleanPath(String value) {
    return value.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
  }

  _SmbIdentity _parseIdentity(String value) {
    final clean = value.trim();
    final separator = clean.indexOf('\\');
    if (separator <= 0 || separator == clean.length - 1) {
      return _SmbIdentity(clean.isEmpty ? null : clean, null);
    }
    return _SmbIdentity(
      clean.substring(separator + 1),
      clean.substring(0, separator),
    );
  }

  String _friendlyMessage(Smb2Exception error) {
    return switch (error.type) {
      Smb2ErrorType.auth ||
      Smb2ErrorType.accessDenied =>
        'Samba 用户名或密码错误，或该账号无权访问共享',
      Smb2ErrorType.timeout => 'Samba 连接超时，请检查设备与网络',
      Smb2ErrorType.connection => '无法连接 Samba 服务，请检查设备与端口',
      _ => error.message.isEmpty ? 'Samba 操作失败' : error.message,
    };
  }
}

class _SmbSession {
  const _SmbSession(this.signature, this.pool);

  final int signature;
  final Future<Smb2Pool> pool;
}

class _SmbIdentity {
  const _SmbIdentity(this.username, this.domain);

  final String? username;
  final String? domain;
}

/// 对外屏蔽第三方 native 异常，避免协议实现细节泄漏到 UI。
class SmbClientException implements Exception {
  const SmbClientException(this.message);

  final String message;

  @override
  String toString() => message;
}
