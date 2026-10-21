import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:juying/features/nas/models/nas_server_config.dart';

/// 局域网 NAS 协议扫描器，只返回完成应用层握手的真实服务。
///
/// **What**: 在物理局域网 IPv4 网段内并发执行 SMB2 Negotiate、WebDAV
/// OPTIONS/PROPFIND 与 NFS RPC NULL 握手，并将通过协议结构校验的端点转换为配置。
///
/// **Why**: TCP 端口开放或普通 HTTP 状态码不能证明设备提供存储协议；路由器管理页、
/// 虚拟网卡代理和端口转发都会造成假阳性。全局有界并发也消除了逐批等待最慢地址的屏障。
class LanScanner {
  static const Set<int> _smbDialects = <int>{
    0x0202,
    0x0210,
    0x0300,
    0x0302,
  };

  /// 扫描真实局域网中的可达 NAS 服务。
  ///
  /// [maxConcurrent] 限制的是同时存在的网络连接，而不是主机数量。默认配置在一个
  /// `/24` 网段约需 1~2 秒，同时避免一次创建上千个 Socket 耗尽系统句柄。
  Future<List<NasServerConfig>> scanSubnet({
    Duration timeout = const Duration(milliseconds: 220),
    int maxConcurrent = 192,
    Duration discoveryWindow = const Duration(milliseconds: 220),
    bool deepScan = false,
  }) async {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(
        maxConcurrent,
        'maxConcurrent',
        '必须大于 0',
      );
    }

    try {
      final scanScope = await _buildScanScope(discoveryWindow);
      if (scanScope.fallbackTargets.isEmpty) return <NasServerConfig>[];

      final initialTargets = deepScan || scanScope.primaryTargets.isEmpty
          ? scanScope.fallbackTargets
          : scanScope.primaryTargets;
      var verified = await _probeTargets(
        initialTargets,
        timeout,
        maxConcurrent,
      );
      // 广播可能被防火墙拦截，也可能只返回非 NAS 设备；此时自动回退完整网段，
      // 保证“快速发现”不会退化成完全发现不到旧设备。
      if (!deepScan &&
          verified.isEmpty &&
          initialTargets.length < scanScope.fallbackTargets.length) {
        verified = await _probeTargets(
          scanScope.fallbackTargets,
          timeout,
          maxConcurrent,
        );
      }
      if (verified.isEmpty) return <NasServerConfig>[];

      final hosts = verified.map((endpoint) => endpoint.host).toSet();
      final hostnameEntries = await Future.wait(
        hosts.map(
          (host) async => MapEntry<String, String?>(
            host,
            await _resolveHostname(host),
          ),
        ),
      );
      final hostnames = Map<String, String?>.fromEntries(hostnameEntries);

      final results = verified
          .map((endpoint) => endpoint.toConfig(hostnames[endpoint.host]))
          .toList(growable: false)
        ..sort(_compareConfigs);
      return results;
    } catch (error) {
      debugPrint('[LanScanner] 局域网扫描失败: $error');
      return <NasServerConfig>[];
    }
  }

  Future<List<_VerifiedEndpoint>> _probeTargets(
    List<String> targets,
    Duration timeout,
    int maxConcurrent,
  ) async {
    final limiter = _AsyncLimiter(maxConcurrent);
    final tasks = <Future<_VerifiedEndpoint?>>[];
    for (final ip in targets) {
      tasks.add(limiter.run(() => _probeSmb(ip, timeout)));
      tasks.add(limiter.run(() => _probeWebdav(ip, 5244, '/dav/', timeout)));
      tasks.add(limiter.run(() => _probeWebdav(ip, 5005, '/', timeout)));
      tasks.add(limiter.run(() => _probeNfs(ip, timeout)));
    }
    return (await Future.wait(tasks))
        .whereType<_VerifiedEndpoint>()
        .toList(growable: false);
  }

  Future<_ScanScope> _buildScanScope(Duration discoveryWindow) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final localIps = <String>{};
    final prefixes = <String>{};

    for (final interface in interfaces) {
      if (_isVirtualInterface(interface.name)) continue;
      for (final address in interface.addresses) {
        final ip = address.address;
        if (!_isPrivateIpv4(ip)) continue;
        final parts = ip.split('.');
        localIps.add(ip);
        prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }

    final targets = <String>[];
    for (final prefix in prefixes) {
      for (var suffix = 1; suffix <= 254; suffix++) {
        final target = '$prefix.$suffix';
        if (!localIps.contains(target)) targets.add(target);
      }
    }

    final candidateGroups = await Future.wait(<Future<Set<String>>>[
      _discoverBroadcastCandidates(
        localIps: localIps,
        prefixes: prefixes,
        window: discoveryWindow,
      ),
      _readNeighborCandidates(prefixes),
    ]);
    final candidates = candidateGroups
        .expand((group) => group)
        .where((ip) => !localIps.contains(ip))
        .toSet()
        .toList(growable: false)
      ..sort(
          (left, right) => _ipv4SortKey(left).compareTo(_ipv4SortKey(right)));
    return _ScanScope(
      primaryTargets: candidates,
      fallbackTargets: targets,
    );
  }

  /// 同时发送 WS-Discovery、mDNS、NetBIOS 与 rpcbind 广播，只收集响应源地址。
  ///
  /// 广播只负责缩小候选集合，任何响应仍必须经过对应存储协议的深度握手。
  Future<Set<String>> _discoverBroadcastCandidates({
    required Set<String> localIps,
    required Set<String> prefixes,
    required Duration window,
  }) async {
    final candidates = <String>{};
    final sockets = <RawDatagramSocket>[];
    final subscriptions = <StreamSubscription<RawSocketEvent>>[];

    for (final localIp in localIps) {
      try {
        final socket = await RawDatagramSocket.bind(
          InternetAddress(localIp),
          0,
          reuseAddress: true,
        );
        socket.broadcastEnabled = true;
        sockets.add(socket);
        subscriptions.add(
          socket.listen((event) {
            if (event != RawSocketEvent.read) return;
            Datagram? datagram;
            while ((datagram = socket.receive()) != null) {
              final source = datagram!.address.address;
              if (_matchesPrefixes(source, prefixes) &&
                  !localIps.contains(source)) {
                candidates.add(source);
              }
            }
          }),
        );

        socket.send(
          _buildWsDiscoveryProbe(),
          InternetAddress('239.255.255.250'),
          3702,
        );
        socket.send(
          _buildMdnsStorageQuery(),
          InternetAddress('224.0.0.251'),
          5353,
        );
        final prefix = localIp.substring(0, localIp.lastIndexOf('.'));
        final broadcast = InternetAddress('$prefix.255');
        socket.send(_buildNetBiosNodeStatusQuery(), broadcast, 137);
        socket.send(_buildRpcBindNfsCallit(), broadcast, 111);
      } catch (_) {
        // 单个网卡不支持组播/广播时，不影响其他物理网卡和后续网段兜底。
      }
    }

    if (sockets.isNotEmpty && window > Duration.zero) {
      await Future<void>.delayed(window);
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final socket in sockets) {
      socket.close();
    }
    return candidates;
  }

  Future<Set<String>> _readNeighborCandidates(Set<String> prefixes) async {
    try {
      final executable = Platform.isWindows ? 'arp' : 'ip';
      final arguments = Platform.isWindows
          ? const <String>['-a']
          : const <String>['neigh', 'show'];
      final result = await Process.run(executable, arguments).timeout(
        const Duration(milliseconds: 250),
      );
      final matches = RegExp(
        r'(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)',
      ).allMatches(result.stdout.toString());
      return matches
          .map((match) => match.group(0)!)
          .where((ip) => _isPrivateIpv4(ip) && _matchesPrefixes(ip, prefixes))
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  bool _matchesPrefixes(String ip, Set<String> prefixes) {
    final separator = ip.lastIndexOf('.');
    return separator > 0 && prefixes.contains(ip.substring(0, separator));
  }

  Uint8List _buildWsDiscoveryProbe() {
    final suffix = DateTime.now()
        .microsecondsSinceEpoch
        .toRadixString(16)
        .padLeft(12, '0');
    final messageId = suffix.substring(suffix.length - 12);
    return Uint8List.fromList(
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" '
        'xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" '
        'xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery">'
        '<e:Header><w:MessageID>urn:uuid:00000000-0000-4000-8000-$messageId'
        '</w:MessageID><w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:'
        'ws:2005:04:discovery</w:To><w:Action e:mustUnderstand="true">http://'
        'schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action></e:Header>'
        '<e:Body><d:Probe/></e:Body></e:Envelope>',
      ),
    );
  }

  Uint8List _buildMdnsStorageQuery() {
    final bytes = <int>[
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x03,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    for (final service in <String>[
      '_smb._tcp.local',
      '_nfs._tcp.local',
      '_webdav._tcp.local',
    ]) {
      bytes
        ..addAll(_encodeDnsName(service))
        ..addAll(const <int>[0x00, 0x0C, 0x00, 0x01]);
    }
    return Uint8List.fromList(bytes);
  }

  List<int> _encodeDnsName(String name) {
    final result = <int>[];
    for (final label in name.split('.')) {
      final encoded = ascii.encode(label);
      result
        ..add(encoded.length)
        ..addAll(encoded);
    }
    result.add(0);
    return result;
  }

  Uint8List _buildNetBiosNodeStatusQuery() {
    final encodedName = <int>[];
    for (final byte in <int>[0x2A, ...List<int>.filled(15, 0)]) {
      encodedName
        ..add(0x41 + ((byte >> 4) & 0x0F))
        ..add(0x41 + (byte & 0x0F));
    }
    return Uint8List.fromList(<int>[
      0x4A,
      0x59,
      0x00,
      0x10,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x20,
      ...encodedName,
      0x00,
      0x00,
      0x21,
      0x00,
      0x01,
    ]);
  }

  Uint8List _buildRpcBindNfsCallit() {
    return Uint8List.fromList(const <int>[
      0x4A, 0x59, 0x4E, 0x46, // XID
      0x00, 0x00, 0x00, 0x00, // CALL
      0x00, 0x00, 0x00, 0x02, // RPC v2
      0x00, 0x01, 0x86, 0xA0, // Portmapper program 100000
      0x00, 0x00, 0x00, 0x02, // Portmapper v2
      0x00, 0x00, 0x00, 0x05, // PMAPPROC_CALLIT
      0x00, 0x00, 0x00, 0x00, // AUTH_NULL credential flavor
      0x00, 0x00, 0x00, 0x00, // Credential length
      0x00, 0x00, 0x00, 0x00, // AUTH_NULL verifier flavor
      0x00, 0x00, 0x00, 0x00, // Verifier length
      0x00, 0x01, 0x86, 0xA3, // NFS program 100003
      0x00, 0x00, 0x00, 0x03, // NFSv3
      0x00, 0x00, 0x00, 0x00, // NULL procedure
      0x00, 0x00, 0x00, 0x00, // Empty argument length
    ]);
  }

  bool _isVirtualInterface(String name) {
    final normalized = name.toLowerCase();
    return <String>[
      'virtual',
      'vethernet',
      'hyper-v',
      'vmware',
      'virtualbox',
      'docker',
      'wsl',
      'virbr',
      'tailscale',
      'zerotier',
      'loopback',
      'tunnel',
      ' tun',
      ' tap',
    ].any(normalized.contains);
  }

  bool _isPrivateIpv4(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList(growable: false);
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final octets = parts.cast<int>();
    if (octets.any((part) => part < 0 || part > 255)) return false;
    return octets[0] == 10 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168) ||
        (octets[0] == 169 && octets[1] == 254);
  }

  Future<_VerifiedEndpoint?> _probeSmb(
    String host,
    Duration timeout,
  ) async {
    final verified = await verifySmbEndpoint(
      host,
      port: 445,
      timeout: timeout,
    );
    return verified
        ? _VerifiedEndpoint(
            host: host,
            port: 445,
            protocol: NasProtocol.smb,
          )
        : null;
  }

  Future<_VerifiedEndpoint?> _probeWebdav(
    String host,
    int port,
    String path,
    Duration timeout,
  ) async {
    final verified = await verifyWebdavEndpoint(
      host,
      port: port,
      path: path,
      timeout: timeout,
    );
    return verified
        ? _VerifiedEndpoint(
            host: host,
            port: port,
            protocol: NasProtocol.webdav,
            shareName: path == '/' ? '' : path.replaceAll('/', ''),
            isAlist: port == 5244,
          )
        : null;
  }

  Future<_VerifiedEndpoint?> _probeNfs(
    String host,
    Duration timeout,
  ) async {
    final verified = await verifyNfsEndpoint(
      host,
      port: 2049,
      timeout: timeout,
    );
    return verified
        ? _VerifiedEndpoint(
            host: host,
            port: 2049,
            protocol: NasProtocol.nfs,
          )
        : null;
  }

  /// 对指定端点执行完整 SMB2 Negotiate，供扫描与端点诊断复用。
  @visibleForTesting
  Future<bool> verifySmbEndpoint(
    String host, {
    required int port,
    required Duration timeout,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final request = _buildSmbNegotiatePacket();
      socket.add(request);
      await socket.flush();
      final response = await _readSocketPacket(
        socket,
        timeout: timeout,
        isComplete: (bytes) {
          if (bytes.length < 4) return false;
          final payloadLength = (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
          return payloadLength > 0 && bytes.length >= payloadLength + 4;
        },
      );
      return response != null && _isValidSmbNegotiateResponse(response);
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Uint8List _buildSmbNegotiatePacket() {
    final payload = <int>[
      0xFE,
      0x53,
      0x4D,
      0x42,
      0x40,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x24,
      0x00,
      0x04,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0xAA,
      0xBB,
      0xCC,
      0xDD,
      0xEE,
      0xFF,
      0x11,
      0x22,
      0x33,
      0x44,
      0x55,
      0x66,
      0x77,
      0x88,
      0x99,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x02,
      0x02,
      0x10,
      0x02,
      0x00,
      0x03,
      0x02,
      0x03,
    ];
    // 初始 NEGOTIATE 必须使用 MessageId=0；部分 Samba/NAS 会直接丢弃
    // 非零首包而不返回错误响应。
    payload[24] = 0;
    final length = payload.length;
    return Uint8List.fromList(<int>[
      0x00,
      (length >> 16) & 0xFF,
      (length >> 8) & 0xFF,
      length & 0xFF,
      ...payload,
    ]);
  }

  bool _isValidSmbNegotiateResponse(Uint8List data) {
    // SMB2 NEGOTIATE Response 的固定体为 65 字节；连同 64 字节头和
    // NetBIOS 标记至少 133 字节，短前缀即使带有 FE SMB 魔数也不是完整响应。
    if (data.length < 133 || data[0] != 0) return false;
    final payloadLength = (data[1] << 16) | (data[2] << 8) | data[3];
    if (payloadLength != data.length - 4) return false;
    final isSmb2 = data[4] == 0xFE &&
        data[5] == 0x53 &&
        data[6] == 0x4D &&
        data[7] == 0x42;
    final structureSize = data[8] | (data[9] << 8);
    final statusIsSuccess = data.sublist(12, 16).every((byte) => byte == 0);
    final command = data[16] | (data[17] << 8);
    final messageIdMatches = data.sublist(28, 36).every((byte) => byte == 0);
    final negotiateStructureSize = data[68] | (data[69] << 8);
    final dialect = data[72] | (data[73] << 8);
    return isSmb2 &&
        structureSize == 64 &&
        statusIsSuccess &&
        command == 0 &&
        messageIdMatches &&
        negotiateStructureSize == 65 &&
        _smbDialects.contains(dialect);
  }

  /// 使用 OPTIONS 和 Depth:0 PROPFIND 双重验证 WebDAV，普通 HTTP 页面不通过。
  @visibleForTesting
  Future<bool> verifyWebdavEndpoint(
    String host, {
    required int port,
    required String path,
    required Duration timeout,
  }) async {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final options = await _requestHttpProbe(
      host,
      port,
      normalizedPath,
      method: 'OPTIONS',
      timeout: timeout,
    );
    if (options == null) return false;
    if (_hasDavCapability(options)) return true;

    final propfind = await _requestHttpProbe(
      host,
      port,
      normalizedPath,
      method: 'PROPFIND',
      timeout: timeout,
      headers: const <String, String>{'Depth': '0'},
    );
    if (propfind == null) return false;
    if (_hasDavCapability(propfind)) return true;
    if (propfind.statusCode != HttpStatus.multiStatus) return false;
    final body = propfind.body.toLowerCase();
    return body.contains('multistatus') &&
        (body.contains('<d:response') || body.contains('<response')) &&
        body.contains('href');
  }

  bool _hasDavCapability(_HttpProbeResponse response) {
    final dav = response.header('dav');
    final allow = response.header('allow').toLowerCase();
    final server = response.header('server').toLowerCase();
    final statusIsPlausible = response.statusCode >= 200 &&
        response.statusCode < HttpStatus.internalServerError;
    return statusIsPlausible &&
        (dav.isNotEmpty ||
            allow.split(',').any((method) => method.trim() == 'propfind') ||
            server.contains('alist'));
  }

  Future<_HttpProbeResponse?> _requestHttpProbe(
    String host,
    int port,
    String path, {
    required String method,
    required Duration timeout,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => 'DIRECT';
    try {
      final uri = Uri(scheme: 'http', host: host, port: port, path: path);
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers
        ..set(HttpHeaders.userAgentHeader, 'JuYing-NAS-Probe/2.0')
        ..set(HttpHeaders.connectionHeader, 'close');
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(',');
      });
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout, onTimeout: () => '');
      return _HttpProbeResponse(
        response.statusCode,
        responseHeaders,
        body,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 对 NFSv3 执行 RPC NULL 调用，并校验完整 Record Marking 与 RPC 接受状态。
  @visibleForTesting
  Future<bool> verifyNfsEndpoint(
    String host, {
    required int port,
    required Duration timeout,
  }) async {
    final v3 = await _verifyNfsVersion(host, port, 3, timeout);
    if (v3 == _RpcProbeResult.accepted) return true;
    return await _verifyNfsVersion(host, port, 4, timeout) ==
        _RpcProbeResult.accepted;
  }

  Future<_RpcProbeResult> _verifyNfsVersion(
    String host,
    int port,
    int version,
    Duration timeout,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final request = _buildNfsNullCall(version);
      socket.add(request);
      await socket.flush();
      final response = await _readSocketPacket(
        socket,
        timeout: timeout,
        isComplete: (bytes) {
          if (bytes.length < 4) return false;
          final recordLength = _readUint32(bytes, 0) & 0x7FFFFFFF;
          return recordLength > 0 && bytes.length >= recordLength + 4;
        },
      );
      if (response == null) return _RpcProbeResult.unreachable;
      return _parseNfsNullReply(response)
          ? _RpcProbeResult.accepted
          : _RpcProbeResult.rejected;
    } catch (_) {
      return _RpcProbeResult.unreachable;
    } finally {
      socket?.destroy();
    }
  }

  Uint8List _buildNfsNullCall(int version) {
    const xid = <int>[0x1A, 0x2B, 0x3C, 0x4D];
    return Uint8List.fromList(<int>[
      0x80, 0x00, 0x00, 0x28, // Record marker: final fragment, 40 bytes.
      ...xid,
      0x00, 0x00, 0x00, 0x00, // CALL
      0x00, 0x00, 0x00, 0x02, // RPC v2
      0x00, 0x01, 0x86, 0xA3, // NFS program 100003
      0x00, 0x00, 0x00, version,
      0x00, 0x00, 0x00, 0x00, // NULL procedure
      0x00, 0x00, 0x00, 0x00, // AUTH_NULL credential flavor
      0x00, 0x00, 0x00, 0x00, // Credential length
      0x00, 0x00, 0x00, 0x00, // AUTH_NULL verifier flavor
      0x00, 0x00, 0x00, 0x00, // Verifier length
    ]);
  }

  bool _parseNfsNullReply(Uint8List data) {
    if (data.length < 28) return false;
    final marker = _readUint32(data, 0);
    final isLastFragment = marker & 0x80000000 != 0;
    final recordLength = marker & 0x7FFFFFFF;
    if (!isLastFragment || recordLength != data.length - 4) return false;
    if (_readUint32(data, 4) != 0x1A2B3C4D) return false;
    if (_readUint32(data, 8) != 1 || _readUint32(data, 12) != 0) {
      return false;
    }
    final verifierLength = _readUint32(data, 20);
    final alignedVerifierLength = (verifierLength + 3) & ~3;
    final acceptStatusOffset = 24 + alignedVerifierLength;
    return acceptStatusOffset + 4 <= data.length &&
        _readUint32(data, acceptStatusOffset) == 0;
  }

  int _readUint32(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  Future<Uint8List?> _readSocketPacket(
    Socket socket, {
    required Duration timeout,
    required bool Function(Uint8List bytes) isComplete,
  }) async {
    final buffer = BytesBuilder(copy: false);
    final completer = Completer<Uint8List?>();
    late StreamSubscription<Uint8List> subscription;
    subscription = socket.listen(
      (chunk) {
        if (completer.isCompleted) return;
        buffer.add(chunk);
        final bytes = buffer.toBytes();
        if (bytes.length > 64 * 1024) {
          completer.complete(null);
        } else if (isComplete(bytes)) {
          completer.complete(bytes);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
      onDone: () {
        if (completer.isCompleted) return;
        final bytes = buffer.toBytes();
        completer.complete(isComplete(bytes) ? bytes : null);
      },
      cancelOnError: true,
    );
    final result = await completer.future.timeout(
      timeout,
      onTimeout: () => null,
    );
    await subscription.cancel();
    return result;
  }

  Future<String?> _resolveHostname(String ip) async {
    final candidates = await Future.wait(<Future<String?>>[
      _resolveReverseDnsHostname(ip),
      resolveNetBiosHostname(
        ip,
        timeout: const Duration(milliseconds: 250),
      ),
      _resolveMdnsHostname(
        ip,
        timeout: const Duration(milliseconds: 250),
      ),
    ]);
    for (final candidate in candidates) {
      final normalized = _normalizeHostname(candidate, ip);
      if (normalized != null) return normalized;
    }
    return null;
  }

  Future<String?> _resolveReverseDnsHostname(String ip) async {
    try {
      final reverse = await InternetAddress(ip)
          .reverse()
          .timeout(const Duration(milliseconds: 250));
      return reverse.host;
    } catch (_) {
      return null;
    }
  }

  /// 使用 NBSTAT 单播解析 Samba 设备名，不依赖路由器提供 PTR 反向记录。
  @visibleForTesting
  Future<String?> resolveNetBiosHostname(
    String ip, {
    int port = 137,
    required Duration timeout,
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final completer = Completer<String?>();
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        Datagram? datagram;
        while ((datagram = socket?.receive()) != null) {
          final value = _parseNetBiosNodeStatus(datagram!.data);
          if (value != null && !completer.isCompleted) {
            completer.complete(value);
          }
        }
      });
      socket.send(
        _buildNetBiosNodeStatusQuery(),
        InternetAddress(ip),
        port,
      );
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
  }

  String? _parseNetBiosNodeStatus(Uint8List data) {
    if (data.length < 12 || data[0] != 0x4A || data[1] != 0x59) return null;
    final answerCount = _readUint16(data, 6);
    if (answerCount < 1) return null;
    var offset = 12;
    final questionCount = _readUint16(data, 4);
    for (var index = 0; index < questionCount; index++) {
      final name = _readDnsName(data, offset);
      if (name == null || name.nextOffset + 4 > data.length) return null;
      offset = name.nextOffset + 4;
    }
    final answerName = _readDnsName(data, offset);
    if (answerName == null || answerName.nextOffset + 10 > data.length) {
      return null;
    }
    offset = answerName.nextOffset;
    final type = _readUint16(data, offset);
    final dataLength = _readUint16(data, offset + 8);
    final dataOffset = offset + 10;
    if (type != 0x21 ||
        dataOffset + dataLength > data.length ||
        dataLength < 1) {
      return null;
    }
    final nameCount = data[dataOffset];
    for (var index = 0; index < nameCount; index++) {
      final entryOffset = dataOffset + 1 + index * 18;
      if (entryOffset + 18 > dataOffset + dataLength) break;
      final suffix = data[entryOffset + 15];
      final flags = _readUint16(data, entryOffset + 16);
      final isGroup = flags & 0x8000 != 0;
      if (suffix != 0x00 || isGroup) continue;
      final name = ascii
          .decode(data.sublist(entryOffset, entryOffset + 15),
              allowInvalid: true)
          .trim();
      if (name.isNotEmpty && name != '__MSBROWSE__') return name;
    }
    return null;
  }

  Future<String?> _resolveMdnsHostname(
    String ip, {
    required Duration timeout,
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      final bindAddress = await _findInterfaceAddressFor(ip);
      socket = await RawDatagramSocket.bind(bindAddress, 0, reuseAddress: true);
      final completer = Completer<String?>();
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        Datagram? datagram;
        while ((datagram = socket?.receive()) != null) {
          final value = _parseMdnsPtrHostname(datagram!.data);
          if (value != null && !completer.isCompleted) {
            completer.complete(value);
          }
        }
      });
      final reverseName = '${ip.split('.').reversed.join('.')}.in-addr.arpa';
      socket.send(
        _buildDnsPtrQuery(reverseName, requestUnicast: true),
        InternetAddress('224.0.0.251'),
        5353,
      );
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
  }

  Future<InternetAddress> _findInterfaceAddressFor(String targetIp) async {
    final targetPrefix = targetIp.substring(0, targetIp.lastIndexOf('.'));
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.address.startsWith('$targetPrefix.')) return address;
      }
    }
    return InternetAddress.anyIPv4;
  }

  Uint8List _buildDnsPtrQuery(String name, {required bool requestUnicast}) {
    return Uint8List.fromList(<int>[
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      ..._encodeDnsName(name),
      0x00,
      0x0C,
      requestUnicast ? 0x80 : 0x00,
      0x01,
    ]);
  }

  String? _parseMdnsPtrHostname(Uint8List data) {
    if (data.length < 12) return null;
    var offset = 12;
    final questionCount = _readUint16(data, 4);
    final recordCount =
        _readUint16(data, 6) + _readUint16(data, 8) + _readUint16(data, 10);
    for (var index = 0; index < questionCount; index++) {
      final name = _readDnsName(data, offset);
      if (name == null || name.nextOffset + 4 > data.length) return null;
      offset = name.nextOffset + 4;
    }
    for (var index = 0; index < recordCount; index++) {
      final owner = _readDnsName(data, offset);
      if (owner == null || owner.nextOffset + 10 > data.length) return null;
      offset = owner.nextOffset;
      final type = _readUint16(data, offset);
      final dataLength = _readUint16(data, offset + 8);
      final dataOffset = offset + 10;
      if (dataOffset + dataLength > data.length) return null;
      if (type == 0x0C) {
        final target = _readDnsName(data, dataOffset);
        if (target != null && target.name.isNotEmpty) return target.name;
      }
      offset = dataOffset + dataLength;
    }
    return null;
  }

  ({String name, int nextOffset})? _readDnsName(
    Uint8List data,
    int offset, [
    int depth = 0,
  ]) {
    if (offset < 0 || offset >= data.length || depth > 8) return null;
    final labels = <String>[];
    var cursor = offset;
    var nextOffset = offset;
    while (cursor < data.length) {
      final length = data[cursor];
      if (length == 0) {
        nextOffset = cursor + 1;
        return (name: labels.join('.'), nextOffset: nextOffset);
      }
      if (length & 0xC0 == 0xC0) {
        if (cursor + 1 >= data.length) return null;
        final pointer = ((length & 0x3F) << 8) | data[cursor + 1];
        final pointed = _readDnsName(data, pointer, depth + 1);
        if (pointed == null) return null;
        if (pointed.name.isNotEmpty) labels.add(pointed.name);
        return (name: labels.join('.'), nextOffset: cursor + 2);
      }
      if (length > 63 || cursor + 1 + length > data.length) return null;
      labels.add(
        ascii.decode(
          data.sublist(cursor + 1, cursor + 1 + length),
          allowInvalid: true,
        ),
      );
      cursor += length + 1;
      nextOffset = cursor;
    }
    return null;
  }

  int _readUint16(Uint8List bytes, int offset) {
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  String? _normalizeHostname(String? value, String ip) {
    if (value == null) return null;
    final normalized = value.trim().replaceFirst(
          RegExp(
            r'\.(local|lan|home|gateway|localdomain|corp)\.?$',
            caseSensitive: false,
          ),
          '',
        );
    if (normalized.isEmpty || normalized == ip || normalized.length > 253) {
      return null;
    }
    return normalized;
  }

  static int _compareConfigs(NasServerConfig left, NasServerConfig right) {
    final hostComparison = _ipv4SortKey(left.host).compareTo(
      _ipv4SortKey(right.host),
    );
    if (hostComparison != 0) return hostComparison;
    final portComparison = left.effectivePort.compareTo(right.effectivePort);
    if (portComparison != 0) return portComparison;
    return left.protocol.index.compareTo(right.protocol.index);
  }

  static int _ipv4SortKey(String ip) {
    final octets = ip.split('.').map(int.tryParse).toList(growable: false);
    if (octets.length != 4 || octets.any((octet) => octet == null)) return 0;
    return octets.cast<int>().fold(
          0,
          (value, octet) => (value << 8) | octet,
        );
  }
}

class _ScanScope {
  const _ScanScope({
    required this.primaryTargets,
    required this.fallbackTargets,
  });

  final List<String> primaryTargets;
  final List<String> fallbackTargets;
}

class _VerifiedEndpoint {
  const _VerifiedEndpoint({
    required this.host,
    required this.port,
    required this.protocol,
    this.shareName = '',
    this.isAlist = false,
  });

  final String host;
  final int port;
  final NasProtocol protocol;
  final String shareName;
  final bool isAlist;

  NasServerConfig toConfig(String? hostname) {
    final suffix = switch (protocol) {
      NasProtocol.smb => 'Samba 共享',
      NasProtocol.nfs => 'NFS 服务',
      NasProtocol.webdav => isAlist ? 'Alist WebDAV' : 'WebDAV',
    };
    return NasServerConfig(
      id: 'verified_${protocol.name}_${host.replaceAll('.', '_')}_$port',
      name: '$host ($suffix)',
      protocol: protocol,
      host: host,
      hostname: hostname,
      port: port,
      shareName: shareName,
    );
  }
}

class _HttpProbeResponse {
  const _HttpProbeResponse(this.statusCode, this.headers, this.body);

  final int statusCode;
  final Map<String, String> headers;
  final String body;

  String header(String name) => headers[name.toLowerCase()] ?? '';
}

enum _RpcProbeResult { unreachable, accepted, rejected }

/// FIFO 并发闸门让快速失败的地址立即释放名额，避免固定批次的尾部延迟。
class _AsyncLimiter {
  _AsyncLimiter(this.limit);

  final int limit;
  int _active = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < limit) {
      _active++;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      return;
    }
    _active--;
  }
}
