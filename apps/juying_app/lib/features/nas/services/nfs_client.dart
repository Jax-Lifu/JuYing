import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:juying/features/nas/models/nas_remote_share.dart';
import 'package:juying/features/nas/models/nas_server_config.dart';
import 'package:juying/features/nas/models/nas_share_item.dart';

/// 应用内 NFS 数据通路契约，不依赖系统 mount、盘符或 root 权限。
abstract interface class NfsClient {
  Future<List<NasRemoteShare>> listExports(String host);

  Future<void> connect(NasServerConfig server);

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

/// 纯 Dart NFSv3 客户端，直接实现 Portmapper、mountd 与 NFS ONC RPC。
///
/// NFSv3 是目前唯一在所有 Dart IO 平台上都能稳定使用、且无需携带 GPL native
/// 二进制的方案。每个 export 保持独立 TCP 会话，Range 请求复用连接以避免播放时
/// 为每个分块反复握手。
class DartNfsClient implements NfsClient {
  final Map<String, _NfsSessionEntry> _sessions = <String, _NfsSessionEntry>{};

  @override
  Future<List<NasRemoteShare>> listExports(String host) async {
    _RpcTcpClient? mountRpc;
    try {
      final mountPort = await _portFor(
        host,
        program: _mountProgram,
        version: _mountVersion,
      );
      if (mountPort == 0) {
        throw const NfsClientException('设备未提供 NFSv3 mountd 服务');
      }
      mountRpc = _RpcTcpClient(host, mountPort);
      final response = await mountRpc.call(
        program: _mountProgram,
        version: _mountVersion,
        procedure: _mountExport,
      );
      final reader = _XdrReader(response);
      final exports = <NasRemoteShare>[];
      while (reader.readBool()) {
        final path = reader.readString();
        final groups = <String>[];
        while (reader.readBool()) {
          groups.add(reader.readString());
        }
        final name =
            path.split('/').where((part) => part.isNotEmpty).lastOrNull;
        exports.add(
          NasRemoteShare(
            name: name ?? path,
            path: path,
            description: groups.isEmpty ? null : groups.join(', '),
          ),
        );
      }
      return exports;
    } on NfsClientException {
      rethrow;
    } on Object catch (error) {
      throw NfsClientException(_friendlyError(error));
    } finally {
      await mountRpc?.close();
    }
  }

  @override
  Future<void> connect(NasServerConfig server) async {
    await _sessionFor(server);
  }

  @override
  Future<List<NasShareItem>> listDirectory(
    NasServerConfig server,
    String relativePath,
  ) async {
    try {
      return await (await _sessionFor(server)).listDirectory(relativePath);
    } on NfsClientException {
      rethrow;
    } on Object catch (error) {
      throw NfsClientException(_friendlyError(error));
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
      final session = await _sessionFor(server);
      return session.openRangeStream(filePath, start: start, end: end);
    } on NfsClientException {
      rethrow;
    } on Object catch (error) {
      throw NfsClientException(_friendlyError(error));
    }
  }

  Future<_NfsV3Session> _sessionFor(NasServerConfig server) async {
    if (server.shareName.isEmpty) {
      throw const NfsClientException('尚未选择 NFS 导出目录');
    }
    final signature = Object.hash(server.host, server.shareName);
    final current = _sessions[server.id];
    if (current != null && current.signature == signature) {
      return current.session;
    }
    if (current != null) {
      try {
        await (await current.session).close();
      } catch (_) {
        // 失效连接的清理不能阻断同一挂载项重新连接。
      }
    }
    final session = _NfsV3Session.connect(server.host, server.shareName);
    _sessions[server.id] = _NfsSessionEntry(signature, session);
    try {
      return await session;
    } catch (_) {
      _sessions.remove(server.id);
      rethrow;
    }
  }

  @override
  Future<void> disconnect(NasServerConfig server) async {
    final entry = _sessions.remove(server.id);
    if (entry == null) return;
    try {
      await (await entry.session).close();
    } catch (_) {
      // 缓存已经移除，远端断线时无需让卸载流程再次失败。
    }
  }

  Future<int> _portFor(
    String host, {
    required int program,
    required int version,
  }) async {
    final rpc = _RpcTcpClient(host, _portMapperPort);
    try {
      final arguments = _XdrWriter()
        ..writeUint(program)
        ..writeUint(version)
        ..writeUint(_ipProtocolTcp)
        ..writeUint(0);
      final response = await rpc.call(
        program: _portMapperProgram,
        version: _portMapperVersion,
        procedure: _portMapperGetPort,
        arguments: arguments.takeBytes(),
      );
      return _XdrReader(response).readUint();
    } finally {
      await rpc.close();
    }
  }

  String _friendlyError(Object error) {
    if (error is TimeoutException) return 'NFS 连接超时，请检查设备与网络';
    if (error is SocketException) return '无法连接 NFS 服务：${error.message}';
    return error.toString();
  }
}

class _NfsV3Session {
  _NfsV3Session._(
    this.host,
    this.exportPath,
    this._mountRpc,
    this._nfsRpc,
    this._rootHandle,
  ) {
    _handles['/'] = _rootHandle;
  }

  final String host;
  final String exportPath;
  final _RpcTcpClient _mountRpc;
  final _RpcTcpClient _nfsRpc;
  final Uint8List _rootHandle;
  final Map<String, Uint8List> _handles = <String, Uint8List>{};
  final Map<String, _NfsAttributes> _attributes = <String, _NfsAttributes>{};

  static Future<_NfsV3Session> connect(String host, String exportPath) async {
    final mountPort = await _queryPort(
      host,
      program: _mountProgram,
      version: _mountVersion,
    );
    var nfsPort = await _queryPort(
      host,
      program: _nfsProgram,
      version: _nfsVersion,
    );
    if (nfsPort == 0) nfsPort = 2049;
    if (mountPort == 0) {
      throw const NfsClientException(
        '该设备未开放 NFSv3 mountd；纯 NFSv4 服务暂不支持 export 枚举',
      );
    }
    // 许多 NFSv3 export 默认启用 secure，要求客户端使用 1024 以下源端口。
    // Windows 桌面可直接满足；移动端若无权限则服务端需开启 insecure。
    final mountRpc = _RpcTcpClient(host, mountPort, useReservedPort: true);
    final nfsRpc = _RpcTcpClient(host, nfsPort, useReservedPort: true);
    try {
      final arguments = _XdrWriter()..writeString(exportPath);
      final response = await mountRpc.call(
        program: _mountProgram,
        version: _mountVersion,
        procedure: _mountMount,
        arguments: arguments.takeBytes(),
      );
      final reader = _XdrReader(response);
      final status = reader.readUint();
      if (status != 0) throw NfsClientException(_mountStatusMessage(status));
      final handle = reader.readOpaque();
      final authCount = reader.readUint();
      for (var index = 0; index < authCount; index++) {
        reader.readUint();
      }
      final session = _NfsV3Session._(
        host,
        exportPath,
        mountRpc,
        nfsRpc,
        handle,
      );
      await session._getAttributes('/', handle);
      return session;
    } catch (_) {
      await mountRpc.close();
      await nfsRpc.close();
      rethrow;
    }
  }

  Future<List<NasShareItem>> listDirectory(String path) async {
    final normalized = _normalizePath(path);
    final directoryHandle = await _resolve(normalized);
    var cookie = 0;
    var verifier = Uint8List(8);
    var eof = false;
    final items = <NasShareItem>[];
    var pageCount = 0;
    while (!eof && pageCount < 256) {
      pageCount += 1;
      final arguments = _XdrWriter()
        ..writeOpaque(directoryHandle)
        ..writeHyper(cookie)
        ..writeFixedOpaque(verifier)
        ..writeUint(16 * 1024)
        ..writeUint(128 * 1024);
      final response = await _nfsRpc.call(
        program: _nfsProgram,
        version: _nfsVersion,
        procedure: _nfsReadDirPlus,
        arguments: arguments.takeBytes(),
      );
      final reader = _XdrReader(response);
      _checkNfsStatus(reader.readUint(), operation: '读取目录');
      _readOptionalAttributes(reader);
      verifier = reader.readFixedOpaque(8);
      while (reader.readBool()) {
        reader.readHyper(); // fileid
        final name = reader.readString();
        cookie = reader.readHyper();
        final attributes = _readOptionalAttributes(reader);
        final handle = _readOptionalHandle(reader);
        if (name == '.' || name == '..') continue;
        final childPath = _joinPath(normalized, name);
        if (handle != null) _handles[childPath] = handle;
        if (attributes != null) _attributes[childPath] = attributes;
        items.add(
          NasShareItem(
            name: name,
            path: childPath,
            isDirectory: attributes?.isDirectory ?? false,
            sizeBytes: attributes?.size ?? 0,
            modifiedTime: attributes?.modified,
          ),
        );
      }
      eof = reader.readBool();
    }
    if (!eof) throw const NfsClientException('NFS 目录条目过多，分页读取未能结束');
    return items;
  }

  Stream<List<int>> openRangeStream(
    String path, {
    required int start,
    required int? end,
  }) async* {
    const maxReadSize = 512 * 1024;
    final normalized = _normalizePath(path);
    final handle = await _resolve(normalized);
    final attributes =
        _attributes[normalized] ?? await _getAttributes(normalized, handle);
    if (attributes.size <= 0 || start >= attributes.size) return;
    final lastByte =
        (end ?? attributes.size - 1).clamp(start, attributes.size - 1);
    var offset = start;
    while (offset <= lastByte) {
      final requested = min(maxReadSize, lastByte - offset + 1);
      final arguments = _XdrWriter()
        ..writeOpaque(handle)
        ..writeHyper(offset)
        ..writeUint(requested);
      final response = await _nfsRpc.call(
        program: _nfsProgram,
        version: _nfsVersion,
        procedure: _nfsRead,
        arguments: arguments.takeBytes(),
      );
      final reader = _XdrReader(response);
      _checkNfsStatus(reader.readUint(), operation: '读取文件');
      _readOptionalAttributes(reader);
      final count = reader.readUint();
      final eof = reader.readBool();
      final bytes = reader.readOpaque();
      if (bytes.isEmpty) return;
      if (count != bytes.length) {
        throw const NfsClientException('NFS READ 返回长度不一致');
      }
      offset += bytes.length;
      yield bytes;
      if (eof) return;
    }
  }

  Future<Uint8List> _resolve(String path) async {
    final cached = _handles[path];
    if (cached != null) return cached;
    var currentPath = '/';
    var currentHandle = _rootHandle;
    for (final component in path.split('/').where((part) => part.isNotEmpty)) {
      final childPath = _joinPath(currentPath, component);
      final childCached = _handles[childPath];
      if (childCached != null) {
        currentPath = childPath;
        currentHandle = childCached;
        continue;
      }
      final arguments = _XdrWriter()
        ..writeOpaque(currentHandle)
        ..writeString(component);
      final response = await _nfsRpc.call(
        program: _nfsProgram,
        version: _nfsVersion,
        procedure: _nfsLookup,
        arguments: arguments.takeBytes(),
      );
      final reader = _XdrReader(response);
      _checkNfsStatus(reader.readUint(), operation: '解析路径 $childPath');
      final handle = _readOptionalHandle(reader);
      if (handle == null) throw NfsClientException('服务端未返回路径句柄：$childPath');
      final attributes = _readOptionalAttributes(reader);
      _readOptionalAttributes(reader); // parent directory attributes
      _handles[childPath] = handle;
      if (attributes != null) _attributes[childPath] = attributes;
      currentPath = childPath;
      currentHandle = handle;
    }
    return currentHandle;
  }

  Future<_NfsAttributes> _getAttributes(
    String path,
    Uint8List handle,
  ) async {
    final arguments = _XdrWriter()..writeOpaque(handle);
    final response = await _nfsRpc.call(
      program: _nfsProgram,
      version: _nfsVersion,
      procedure: _nfsGetAttr,
      arguments: arguments.takeBytes(),
    );
    final reader = _XdrReader(response);
    _checkNfsStatus(reader.readUint(), operation: '读取文件属性');
    final attributes = _readAttributes(reader);
    _attributes[path] = attributes;
    return attributes;
  }

  Future<void> close() async {
    try {
      final arguments = _XdrWriter()..writeString(exportPath);
      await _mountRpc.call(
        program: _mountProgram,
        version: _mountVersion,
        procedure: _mountUnmount,
        arguments: arguments.takeBytes(),
      );
    } catch (_) {
      // UMNT 仅更新服务端挂载记录，网络已经断开时可直接释放本地资源。
    } finally {
      await _mountRpc.close();
      await _nfsRpc.close();
    }
  }

  static Future<int> _queryPort(
    String host, {
    required int program,
    required int version,
  }) async {
    final rpc = _RpcTcpClient(host, _portMapperPort);
    try {
      final arguments = _XdrWriter()
        ..writeUint(program)
        ..writeUint(version)
        ..writeUint(_ipProtocolTcp)
        ..writeUint(0);
      final response = await rpc.call(
        program: _portMapperProgram,
        version: _portMapperVersion,
        procedure: _portMapperGetPort,
        arguments: arguments.takeBytes(),
      );
      return _XdrReader(response).readUint();
    } finally {
      await rpc.close();
    }
  }
}

class _RpcTcpClient {
  _RpcTcpClient(this.host, this.port, {this.useReservedPort = false});

  final String host;
  final int port;
  final bool useReservedPort;
  Socket? _socket;
  _SocketReader? _reader;
  var _nextXid = Random().nextInt(0x7fffffff);
  Future<void> _tail = Future<void>.value();
  static int _nextReservedPort = 700;

  Future<Uint8List> call({
    required int program,
    required int version,
    required int procedure,
    Uint8List? arguments,
  }) {
    final completer = Completer<Uint8List>();
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    () async {
      await previous;
      try {
        completer.complete(
          await _callWithRetry(
            program: program,
            version: version,
            procedure: procedure,
            arguments: arguments,
          ),
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        done.complete();
      }
    }();
    return completer.future;
  }

  Future<Uint8List> _callWithRetry({
    required int program,
    required int version,
    required int procedure,
    Uint8List? arguments,
  }) async {
    try {
      return await _callWire(
        program: program,
        version: version,
        procedure: procedure,
        arguments: arguments,
      );
    } on SocketException {
      await _reset();
      return _callWire(
        program: program,
        version: version,
        procedure: procedure,
        arguments: arguments,
      );
    } on TimeoutException {
      await _reset();
      return _callWire(
        program: program,
        version: version,
        procedure: procedure,
        arguments: arguments,
      );
    }
  }

  Future<Uint8List> _callWire({
    required int program,
    required int version,
    required int procedure,
    Uint8List? arguments,
  }) async {
    await _ensureConnected();
    final xid = (_nextXid = (_nextXid + 1) & 0x7fffffff);
    final credential = _XdrWriter()
      ..writeUint(DateTime.now().millisecondsSinceEpoch & 0xffffffff)
      ..writeString('juying')
      ..writeUint(65534)
      ..writeUint(65534)
      ..writeUint(0);
    final request = _XdrWriter()
      ..writeUint(xid)
      ..writeUint(0) // CALL
      ..writeUint(2) // RPC version
      ..writeUint(program)
      ..writeUint(version)
      ..writeUint(procedure)
      ..writeUint(1) // AUTH_SYS
      ..writeOpaque(credential.takeBytes())
      ..writeUint(0) // AUTH_NULL verifier
      ..writeOpaque(Uint8List(0));
    if (arguments != null) request.writeRaw(arguments);
    final body = request.takeBytes();
    final marker = ByteData(4)..setUint32(0, 0x80000000 | body.length);
    _socket!.add(marker.buffer.asUint8List());
    _socket!.add(body);
    await _socket!.flush().timeout(const Duration(seconds: 8));

    final reply =
        await _reader!.readRecord().timeout(const Duration(seconds: 8));
    final reader = _XdrReader(reply);
    if (reader.readUint() != xid) throw const NfsClientException('RPC 响应序号不匹配');
    if (reader.readUint() != 1) {
      throw const NfsClientException('RPC 返回了非 REPLY 消息');
    }
    final replyStatus = reader.readUint();
    if (replyStatus != 0) throw NfsClientException('RPC 请求被拒绝：$replyStatus');
    reader.readUint(); // verifier flavor
    reader.readOpaque();
    final acceptStatus = reader.readUint();
    if (acceptStatus != 0) {
      throw NfsClientException('RPC 过程调用失败：$acceptStatus');
    }
    return reader.readRemaining();
  }

  Future<void> _ensureConnected() async {
    if (_socket != null) return;
    Socket? socket;
    Object? lastError;
    final attempts = useReservedPort ? 32 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final sourcePort = useReservedPort ? _takeReservedPort() : 0;
      try {
        socket = await Socket.connect(
          host,
          port,
          sourcePort: sourcePort,
          timeout: const Duration(seconds: 5),
        );
        break;
      } on SocketException catch (error) {
        lastError = error;
      }
    }
    if (socket == null) {
      throw SocketException('无法分配 NFS 保留源端口：$lastError');
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    _reader = _SocketReader(socket);
  }

  static int _takeReservedPort() {
    final port = _nextReservedPort;
    _nextReservedPort = port >= 1023 ? 700 : port + 1;
    return port;
  }

  Future<void> _reset() async {
    final socket = _socket;
    _socket = null;
    _reader = null;
    await socket?.close();
  }

  Future<void> close() => _reset();
}

class _SocketReader {
  _SocketReader(Stream<List<int>> source) : _iterator = StreamIterator(source);

  final StreamIterator<List<int>> _iterator;
  Uint8List _current = Uint8List(0);
  int _offset = 0;

  Future<Uint8List> readRecord() async {
    final builder = BytesBuilder(copy: false);
    var lastFragment = false;
    while (!lastFragment) {
      final markerBytes = await readExact(4);
      final marker = ByteData.sublistView(markerBytes).getUint32(0);
      lastFragment = marker & 0x80000000 != 0;
      final length = marker & 0x7fffffff;
      if (length > 64 * 1024 * 1024) {
        throw const NfsClientException('RPC 响应尺寸异常');
      }
      builder.add(await readExact(length));
    }
    return builder.takeBytes();
  }

  Future<Uint8List> readExact(int length) async {
    final result = Uint8List(length);
    var written = 0;
    while (written < length) {
      if (_offset >= _current.length) {
        if (!await _iterator.moveNext()) {
          throw const SocketException('RPC socket closed');
        }
        _current = Uint8List.fromList(_iterator.current);
        _offset = 0;
      }
      final count = min(length - written, _current.length - _offset);
      result.setRange(written, written + count, _current, _offset);
      written += count;
      _offset += count;
    }
    return result;
  }
}

class _XdrWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void writeUint(int value) {
    final data = ByteData(4)..setUint32(0, value & 0xffffffff);
    _bytes.add(data.buffer.asUint8List());
  }

  void writeHyper(int value) {
    writeUint(value ~/ 0x100000000);
    writeUint(value & 0xffffffff);
  }

  void writeString(String value) => writeOpaque(utf8.encode(value));

  void writeOpaque(List<int> value) {
    writeUint(value.length);
    writeFixedOpaque(value);
  }

  void writeFixedOpaque(List<int> value) {
    _bytes.add(value);
    final padding = (4 - value.length % 4) % 4;
    if (padding > 0) _bytes.add(Uint8List(padding));
  }

  void writeRaw(List<int> value) => _bytes.add(value);

  Uint8List takeBytes() => _bytes.takeBytes();
}

class _XdrReader {
  _XdrReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int readUint() {
    _require(4);
    final value =
        ByteData.sublistView(_bytes, _offset, _offset + 4).getUint32(0);
    _offset += 4;
    return value;
  }

  int readHyper() => readUint() * 0x100000000 + readUint();

  bool readBool() => readUint() != 0;

  String readString() => utf8.decode(readOpaque(), allowMalformed: true);

  Uint8List readOpaque() => readFixedOpaque(readUint());

  Uint8List readFixedOpaque(int length) {
    _require(length);
    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    final padding = (4 - length % 4) % 4;
    _require(padding);
    _offset += padding;
    return Uint8List.fromList(value);
  }

  Uint8List readRemaining() {
    final value = Uint8List.sublistView(_bytes, _offset);
    _offset = _bytes.length;
    return Uint8List.fromList(value);
  }

  void _require(int length) {
    if (_offset + length > _bytes.length) {
      throw const NfsClientException('RPC/XDR 响应不完整');
    }
  }
}

class _NfsAttributes {
  const _NfsAttributes({
    required this.type,
    required this.size,
    required this.modified,
  });

  final int type;
  final int size;
  final DateTime modified;

  bool get isDirectory => type == 2;
}

_NfsAttributes _readAttributes(_XdrReader reader) {
  final type = reader.readUint();
  reader.readUint(); // mode
  reader.readUint(); // nlink
  reader.readUint(); // uid
  reader.readUint(); // gid
  final size = reader.readHyper();
  reader.readHyper(); // used
  reader.readUint(); // specdata major
  reader.readUint(); // specdata minor
  reader.readHyper(); // fsid
  reader.readHyper(); // fileid
  reader.readUint();
  reader.readUint(); // atime
  final modifiedSeconds = reader.readUint();
  final modifiedNanos = reader.readUint();
  reader.readUint();
  reader.readUint(); // ctime
  return _NfsAttributes(
    type: type,
    size: size,
    modified: DateTime.fromMicrosecondsSinceEpoch(
      modifiedSeconds * Duration.microsecondsPerSecond + modifiedNanos ~/ 1000,
    ),
  );
}

_NfsAttributes? _readOptionalAttributes(_XdrReader reader) {
  return reader.readBool() ? _readAttributes(reader) : null;
}

Uint8List? _readOptionalHandle(_XdrReader reader) {
  return reader.readBool() ? reader.readOpaque() : null;
}

void _checkNfsStatus(int status, {required String operation}) {
  if (status == 0) return;
  final message = switch (status) {
    1 => '操作不允许',
    2 => '文件或目录不存在',
    5 => 'I/O 错误',
    13 => '权限不足',
    20 => '路径不是目录',
    21 => '目标是目录',
    70 => '文件句柄已失效',
    _ => '错误码 $status',
  };
  throw NfsClientException('$operation失败：$message');
}

String _mountStatusMessage(int status) {
  return switch (status) {
    1 => 'NFS 挂载被拒绝：操作不允许',
    2 => 'NFS 导出目录不存在',
    13 => 'NFS 挂载被拒绝：当前设备不在允许访问范围',
    _ => 'NFS 挂载失败：错误码 $status',
  };
}

String _normalizePath(String value) {
  final parts = value
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();
  if (parts.any((part) => part == '..')) {
    throw const NfsClientException('NFS 路径不能包含上级目录跳转');
  }
  return parts.isEmpty ? '/' : '/${parts.join('/')}';
}

String _joinPath(String parent, String name) {
  return parent == '/' ? '/$name' : '$parent/$name';
}

class _NfsSessionEntry {
  const _NfsSessionEntry(this.signature, this.session);

  final int signature;
  final Future<_NfsV3Session> session;
}

/// 面向 UI 的稳定 NFS 错误，不暴露底层 RPC/XDR 实现细节。
class NfsClientException implements Exception {
  const NfsClientException(this.message);

  final String message;

  @override
  String toString() => message;
}

const int _portMapperPort = 111;
const int _ipProtocolTcp = 6;
const int _portMapperProgram = 100000;
const int _portMapperVersion = 2;
const int _portMapperGetPort = 3;
const int _mountProgram = 100005;
const int _mountVersion = 3;
const int _mountMount = 1;
const int _mountUnmount = 3;
const int _mountExport = 5;
const int _nfsProgram = 100003;
const int _nfsVersion = 3;
const int _nfsGetAttr = 1;
const int _nfsLookup = 3;
const int _nfsRead = 6;
const int _nfsReadDirPlus = 17;

extension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
