import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/proxy/local_proxy_server.dart';
import 'package:juying/features/nas/models/nas_remote_share.dart';
import 'package:juying/features/nas/models/nas_server_config.dart';
import 'package:juying/features/nas/models/nas_share_item.dart';
import 'package:juying/features/nas/providers/nas_provider.dart';
import 'package:juying/features/nas/services/lan_nas_service.dart';
import 'package:juying/features/nas/services/lan_scanner.dart';
import 'package:juying/features/nas/services/nas_credential_store.dart';
import 'package:juying/features/nas/services/nfs_client.dart';
import 'package:juying/features/nas/services/smb_client.dart';
import 'package:juying/features/nas/services/webdav_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LAN NAS & Real Protocol Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('verifies NasServerConfig hostname and URI representations', () {
      const smb = NasServerConfig(
        id: 'smb1',
        name: 'Samba Test',
        protocol: NasProtocol.smb,
        host: '192.168.1.50',
        hostname: 'Synology-DS920',
        shareName: 'movies',
      );
      expect(smb.effectivePort, 445);
      expect(smb.hostname, 'Synology-DS920');
      expect(smb.summaryUri, 'smb://Synology-DS920 (192.168.1.50):445/movies');

      const nfs = NasServerConfig(
        id: 'nfs1',
        name: 'NFS Test',
        protocol: NasProtocol.nfs,
        host: '192.168.1.60',
        shareName: '/volume1/video',
      );
      expect(nfs.effectivePort, 2049);
      expect(nfs.summaryUri, 'nfs://192.168.1.60:2049//volume1/video');

      const webdav = NasServerConfig(
        id: 'dav1',
        name: 'WebDAV Test',
        protocol: NasProtocol.webdav,
        host: '192.168.1.70',
        hostname: 'Alist-Server',
        port: 5244,
        shareName: 'dav',
      );
      expect(webdav.effectivePort, 5244);
      expect(webdav.hostname, 'Alist-Server');
      expect(webdav.summaryUri, 'http://Alist-Server (192.168.1.70):5244/dav');
    });

    test('NasShareItem accurately detects media, subtitles, and NFO formats',
        () {
      final video = NasShareItem(
        name: 'Inception.2010.2160p.mkv',
        path: '/movies/Inception.2010.2160p.mkv',
        isDirectory: false,
        sizeBytes: 25769803776,
        modifiedTime: DateTime(2024, 1, 1, 12, 0),
      );
      expect(video.isMediaFile, isTrue);
      expect(video.isSubtitles, isFalse);
      expect(video.formattedSize, contains('24.00 GB'));
      expect(video.fileTypeName, 'MKV 视频');
      expect(video.resolutionTag, '4K UHD');
      expect(video.formattedModifiedTime, '2024-01-01 12:00');

      const srt = NasShareItem(
        name: 'Inception.zh-CN.srt',
        path: '/movies/Inception.zh-CN.srt',
        isDirectory: false,
        sizeBytes: 52428,
      );
      expect(srt.isSubtitles, isTrue);
      expect(srt.isMediaFile, isFalse);
      expect(srt.fileTypeName, '外挂字幕');

      const nfo = NasShareItem(
        name: 'movie.nfo',
        path: '/movies/movie.nfo',
        isDirectory: false,
        sizeBytes: 2048,
      );
      expect(nfo.isNfo, isTrue);
      expect(nfo.fileTypeName, 'NFO 元数据');
    });

    test('WebDavClient accurately parses authentic PROPFIND multi-status XML',
        () {
      const propfindXml = '''<?xml version="1.0" encoding="utf-8" ?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/movies/</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype><D:collection/></D:resourcetype>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/movies/Oppenheimer.2023.2160p.mkv</D:href>
    <D:propstat>
      <D:prop>
        <D:getcontentlength>34359738368</D:getcontentlength>
        <D:getlastmodified>Sun, 01 Jan 2024 12:00:00 GMT</D:getlastmodified>
        <D:resourcetype/>
        <D:displayname>Oppenheimer.2023.2160p.mkv</D:displayname>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/movies/4K%20Remux/</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype><D:collection/></D:resourcetype>
        <D:displayname>4K Remux</D:displayname>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''';

      final items = WebDavClient.parsePropfindXml(
        propfindXml,
        requestedPath: '/dav/movies',
      );

      expect(items.length, 2);

      final file = items.firstWhere((i) => !i.isDirectory);
      expect(file.name, 'Oppenheimer.2023.2160p.mkv');
      expect(file.sizeBytes, 34359738368);
      expect(file.isMediaFile, isTrue);

      final dir = items.firstWhere((i) => i.isDirectory);
      expect(dir.name, '4K Remux');
      expect(dir.isDirectory, isTrue);
    });

    test(
        'LanNasService bridges NAS files to loopback Range proxy URL and unmounts cleanly',
        () async {
      final service = LanNasService();
      const server = NasServerConfig(
        id: 'test_nas_unmount',
        name: 'Synology',
        protocol: NasProtocol.webdav,
        host: '192.168.1.100',
        shareName: 'video',
      );
      const file = NasShareItem(
        name: 'Avatar.2009.4K.mkv',
        path: '/video/Avatar.2009.4K.mkv',
        isDirectory: false,
        sizeBytes: 30000000000,
      );

      final proxyUrl = service.bridgeNasFileToProxy(server: server, file: file);
      expect(proxyUrl, startsWith('http://127.0.0.1:'));
      expect(proxyUrl, contains('/proxy/'));

      // Test unmount logic
      await service.unmountServer(server);
    });

    test('LanNasService parses Kodi/Emby standard NFO XML metadata', () {
      const nfoXml = '''
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <movie>
        <title>星际穿越</title>
        <originaltitle>Interstellar</originaltitle>
        <plot>近未来地球黄沙遍野，前NASA宇航员库珀穿过虫洞为人类寻找新家园。</plot>
        <year>2014</year>
        <rating>9.4</rating>
        <genre>科幻</genre>
        <genre>冒险</genre>
        <poster>https://example.com/interstellar.jpg</poster>
      </movie>
      ''';

      final media = LanNasService.parseNfoXml(nfoXml, fileId: 'interstellar');
      expect(media, isNotNull);
      expect(media!.title, '星际穿越');
      expect(media.year, '2014');
      expect(media.rating, 9.4);
      expect(media.genres, contains('科幻'));
      expect(media.genres, contains('冒险'));
      expect(media.posterUrl, 'https://example.com/interstellar.jpg');
    });

    test('NasServersNotifier persists and unmounts NAS configurations cleanly',
        () async {
      final credentialStore = _MemoryCredentialStore();
      final notifier = NasServersNotifier(credentialStore: credentialStore);
      final service = LanNasService();
      expect(notifier.state, isEmpty);

      const newServer = NasServerConfig(
        id: 'nas_custom_1',
        name: '我的私人群晖',
        protocol: NasProtocol.smb,
        host: '192.168.1.200',
        hostname: 'Synology-DS920',
        shareName: 'video',
        password: 'secure-secret',
      );

      await notifier.addServer(newServer);
      expect(notifier.state.length, 1);
      expect(notifier.state.first.hostname, 'Synology-DS920');

      // Verify SharedPreferences has the JSON
      final prefs = await SharedPreferences.getInstance();
      final storedJson = prefs.getString('juying_persisted_nas_servers_v1');
      expect(storedJson, isNotNull);
      final decoded = json.decode(storedJson!) as List<dynamic>;
      expect(decoded.length, 1);
      expect(decoded.first['hostname'], 'Synology-DS920');
      expect(decoded.first.containsKey('password'), isFalse);
      expect(
        await credentialStore.readPassword(newServer.id),
        'secure-secret',
      );

      // Test unmount and removal
      await notifier.unmountAndRemoveServer(newServer, service);
      expect(notifier.state, isEmpty);
      expect(await credentialStore.readPassword(newServer.id), isNull);
    });

    test('LanScanner executes deep protocol handshake without false positives',
        () async {
      final scanner = LanScanner();
      final results = await scanner.scanSubnet(
        timeout: const Duration(milliseconds: 30),
        maxConcurrent: 64,
        discoveryWindow: const Duration(milliseconds: 30),
      );
      expect(results, isA<List<NasServerConfig>>());
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('LanScanner rejects ordinary HTTP and accepts advertised WebDAV',
        () async {
      final scanner = LanScanner();
      final ordinaryHttp =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final ordinarySubscription = ordinaryHttp.listen((request) async {
        request.response.statusCode = request.method == 'PROPFIND'
            ? HttpStatus.methodNotAllowed
            : HttpStatus.ok;
        await request.response.close();
      });
      addTearDown(() async {
        await ordinarySubscription.cancel();
        await ordinaryHttp.close(force: true);
      });

      final webdav = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final webdavSubscription = webdav.listen((request) async {
        request.response.headers.set('DAV', '1, 2');
        request.response.headers.set('Allow', 'OPTIONS, PROPFIND');
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      addTearDown(() async {
        await webdavSubscription.cancel();
        await webdav.close(force: true);
      });

      final realHttpOverrides = _RealHttpOverrides();
      final fakeResult = await HttpOverrides.runZoned(
        () => scanner.verifyWebdavEndpoint(
          InternetAddress.loopbackIPv4.address,
          port: ordinaryHttp.port,
          path: '/',
          timeout: const Duration(seconds: 1),
        ),
        createHttpClient: realHttpOverrides.createHttpClient,
      );
      final realResult = await HttpOverrides.runZoned(
        () => scanner.verifyWebdavEndpoint(
          InternetAddress.loopbackIPv4.address,
          port: webdav.port,
          path: '/',
          timeout: const Duration(seconds: 1),
        ),
        createHttpClient: realHttpOverrides.createHttpClient,
      );

      expect(fakeResult, isFalse);
      expect(realResult, isTrue);
    });

    test('LanScanner validates complete SMB2 and NFS RPC response structures',
        () async {
      final scanner = LanScanner();
      final fake = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final fakeSubscription = fake.listen((socket) {
        socket.listen((_) async {
          socket.add(utf8.encode('HTTP/1.1 200 OK\r\n\r\n'));
          await socket.flush();
          await socket.close();
        });
      });
      addTearDown(() async {
        await fakeSubscription.cancel();
        await fake.close();
      });

      final smb = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final smbRequest = Completer<Uint8List>();
      final smbSubscription = smb.listen((socket) {
        socket.listen((data) async {
          if (!smbRequest.isCompleted) {
            smbRequest.complete(Uint8List.fromList(data));
          }
          socket.add(_validSmb2NegotiateResponse());
          await socket.flush();
          await socket.close();
        });
      });
      addTearDown(() async {
        await smbSubscription.cancel();
        await smb.close();
      });

      final nfs = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final nfsRequest = Completer<Uint8List>();
      final nfsSubscription = nfs.listen((socket) {
        socket.listen((data) async {
          if (!nfsRequest.isCompleted) {
            nfsRequest.complete(Uint8List.fromList(data));
          }
          socket.add(_validNfsNullReply());
          await socket.flush();
          await socket.close();
        });
      });
      addTearDown(() async {
        await nfsSubscription.cancel();
        await nfs.close();
      });

      expect(
        await scanner.verifySmbEndpoint(
          InternetAddress.loopbackIPv4.address,
          port: fake.port,
          timeout: const Duration(seconds: 1),
        ),
        isFalse,
      );
      expect(
        await scanner.verifyNfsEndpoint(
          InternetAddress.loopbackIPv4.address,
          port: fake.port,
          timeout: const Duration(seconds: 1),
        ),
        isFalse,
      );
      expect(
        await scanner.verifySmbEndpoint(
          InternetAddress.loopbackIPv4.address,
          port: smb.port,
          timeout: const Duration(seconds: 1),
        ),
        isTrue,
      );
      final smbPacket = await smbRequest.future;
      final smbPayloadLength =
          (smbPacket[1] << 16) | (smbPacket[2] << 8) | smbPacket[3];
      expect(smbPayloadLength, smbPacket.length - 4);
      expect(smbPacket.sublist(28, 36), everyElement(0));

      expect(
        await scanner.verifyNfsEndpoint(
          InternetAddress.loopbackIPv4.address,
          port: nfs.port,
          timeout: const Duration(seconds: 1),
        ),
        isTrue,
      );
      final nfsPacket = await nfsRequest.future;
      final nfsRecordLength = ((nfsPacket[0] & 0x7F) << 24) |
          (nfsPacket[1] << 16) |
          (nfsPacket[2] << 8) |
          nfsPacket[3];
      expect(nfsPacket.length, 44);
      expect(nfsRecordLength, nfsPacket.length - 4);
    });

    test('LanScanner resolves hostname from NetBIOS node status', () async {
      final responder = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final subscription = responder.listen((event) {
        if (event != RawSocketEvent.read) return;
        final request = responder.receive();
        if (request == null) return;
        responder.send(
          _netBiosNodeStatusResponse('LIVINGROOM-NAS'),
          request.address,
          request.port,
        );
      });
      addTearDown(() async {
        await subscription.cancel();
        responder.close();
      });

      final hostname = await LanScanner().resolveNetBiosHostname(
        InternetAddress.loopbackIPv4.address,
        port: responder.port,
        timeout: const Duration(seconds: 1),
      );

      expect(hostname, 'LIVINGROOM-NAS');
    });

    test('LanNasService delegates Samba credentials to the in-app client',
        () async {
      final smbClient = _FakeSmbClient();
      final service = LanNasService(smbClient: smbClient);
      const server = NasServerConfig(
        id: 'plain-user',
        name: 'NAS',
        protocol: NasProtocol.smb,
        host: '192.168.0.101',
      );

      final shares = await service.listSmbShares(
        server,
        username: 'fuli',
        password: 'secret',
      );

      expect(shares.single.path, 'media');
      expect(smbClient.lastHost, '192.168.0.101');
      expect(smbClient.lastUsername, 'fuli');
      expect(smbClient.lastPassword, 'secret');
    });

    test('LanNasService browses and streams Samba without UNC paths', () async {
      final smbClient = _FakeSmbClient();
      final service = LanNasService(smbClient: smbClient);
      const server = NasServerConfig(
        id: 'in-app-session',
        name: 'NAS',
        protocol: NasProtocol.smb,
        host: '192.168.0.101',
        username: 'fuli',
        password: 'secret',
        shareName: 'media',
      );

      final entries = await service.listDirectory(server, '/movies');

      expect(entries.single.name, 'demo.mkv');
      expect(smbClient.lastDirectory, '/movies');
      await service.unmountServer(server);
      expect(smbClient.disconnected, isTrue);
    });

    test('LanNasService mounts and browses NFS without a system drive',
        () async {
      final nfsClient = _FakeNfsClient();
      final service = LanNasService(nfsClient: nfsClient);
      const discovered = NasServerConfig(
        id: 'nfs-host',
        name: 'NFS',
        protocol: NasProtocol.nfs,
        host: '192.168.0.105',
      );

      final exports = await service.listNfsExports(discovered);
      final mounted = await service.mountNfsExport(discovered, exports.first);
      final entries = await service.listDirectory(mounted, '/');

      expect(mounted.shareName, '/home/media');
      expect(nfsClient.connected, isTrue);
      expect(entries.single.name, 'movie.mkv');
      await service.unmountServer(mounted);
      expect(nfsClient.disconnected, isTrue);
    });

    test('LocalProxyServer unregisters stream proxies on unmount', () {
      final proxy = LocalProxyServer.instance;
      proxy.registerStreamProxy(
        token: 'nas_test123_abc',
        resolver: (s, e) async => const Stream<List<int>>.empty(),
        contentLength: 1000,
      );

      proxy.unregisterStreamProxiesForPrefix('nas_test123_');
    });

    test('verifies NasViewMode options and labels', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(NasViewMode.values.length, 3);
      expect(NasViewMode.grid.label, '图标');
      expect(NasViewMode.list.label, '列表');
      expect(NasViewMode.details.label, '详情');
      expect(container.read(nasViewModeProvider), NasViewMode.details);
    });
  });
}

Uint8List _validSmb2NegotiateResponse() {
  final response = Uint8List(133);
  const payloadLength = 129;
  response[2] = payloadLength >> 8;
  response[3] = payloadLength & 0xFF;
  response.setRange(4, 8, const <int>[0xFE, 0x53, 0x4D, 0x42]);
  response[8] = 0x40;
  response[68] = 0x41;
  response[72] = 0x10;
  response[73] = 0x02;
  return response;
}

class _FakeSmbClient implements SmbClient {
  String? lastHost;
  String? lastUsername;
  String? lastPassword;
  String? lastDirectory;
  bool disconnected = false;

  @override
  Future<List<NasRemoteShare>> listShares({
    required String host,
    required String username,
    required String password,
  }) async {
    lastHost = host;
    lastUsername = username;
    lastPassword = password;
    return const <NasRemoteShare>[
      NasRemoteShare(name: 'media', path: 'media'),
    ];
  }

  @override
  Future<List<NasShareItem>> listDirectory(
    NasServerConfig server,
    String relativePath,
  ) async {
    lastDirectory = relativePath;
    return const <NasShareItem>[
      NasShareItem(
        name: 'demo.mkv',
        path: 'movies/demo.mkv',
        isDirectory: false,
        sizeBytes: 4,
      ),
    ];
  }

  @override
  Future<Stream<List<int>>> openRangeStream({
    required NasServerConfig server,
    required String filePath,
    required int start,
    required int? end,
  }) async {
    return Stream<List<int>>.value(<int>[1, 2, 3, 4]);
  }

  @override
  Future<void> disconnect(NasServerConfig server) async {
    disconnected = true;
  }
}

class _FakeNfsClient implements NfsClient {
  bool connected = false;
  bool disconnected = false;

  @override
  Future<List<NasRemoteShare>> listExports(String host) async {
    return const <NasRemoteShare>[
      NasRemoteShare(
        name: 'media',
        path: '/home/media',
        description: '*',
      ),
    ];
  }

  @override
  Future<void> connect(NasServerConfig server) async {
    connected = true;
  }

  @override
  Future<List<NasShareItem>> listDirectory(
    NasServerConfig server,
    String relativePath,
  ) async {
    return const <NasShareItem>[
      NasShareItem(
        name: 'movie.mkv',
        path: '/movie.mkv',
        isDirectory: false,
        sizeBytes: 4,
      ),
    ];
  }

  @override
  Future<Stream<List<int>>> openRangeStream({
    required NasServerConfig server,
    required String filePath,
    required int start,
    required int? end,
  }) async {
    return Stream<List<int>>.value(<int>[1, 2, 3, 4]);
  }

  @override
  Future<void> disconnect(NasServerConfig server) async {
    disconnected = true;
  }
}

Uint8List _validNfsNullReply() {
  return Uint8List.fromList(const <int>[
    0x80,
    0x00,
    0x00,
    0x18,
    0x1A,
    0x2B,
    0x3C,
    0x4D,
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
  ]);
}

Uint8List _netBiosNodeStatusResponse(String hostname) {
  final name = ascii.encode(hostname.padRight(15).substring(0, 15));
  return Uint8List.fromList(<int>[
    0x4A,
    0x59,
    0x85,
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
    0x21,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x13,
    0x01,
    ...name,
    0x00,
    0x00,
    0x00,
  ]);
}

class _RealHttpOverrides extends HttpOverrides {}

class _MemoryCredentialStore implements NasCredentialStore {
  final Map<String, String> _passwords = <String, String>{};

  @override
  Future<void> deletePassword(String serverId) async {
    _passwords.remove(serverId);
  }

  @override
  Future<String?> readPassword(String serverId) async {
    return _passwords[serverId];
  }

  @override
  Future<void> writePassword(String serverId, String password) async {
    _passwords[serverId] = password;
  }
}
