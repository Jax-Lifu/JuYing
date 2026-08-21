import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/application/nas/nas_credential_store.dart';
import 'package:juying/domain/models/nas_connection.dart';
import 'package:juying/infrastructure/nas/webdav_connection_service.dart';

void main() {
  const credentials = NasCredentials(username: 'family', password: 'secret');

  test('WebDAV 连接验证不会泄露凭据，并认可 2xx 状态', () async {
    final service = WebDavConnectionService(
      client: MockClient((request) async {
        expect(request.method, 'OPTIONS');
        expect(request.headers['authorization'], startsWith('Basic '));
        expect(request.headers['depth'], '0');
        return http.Response('', 204);
      }),
    );

    final check = await service.verify(
      connection: _connection(Uri.parse('https://nas.example.com/dav/')),
      credentials: credentials,
    );

    expect(check, NasConnectionCheck.available);
  });

  test('认证失败和不安全端点有明确状态', () async {
    final service = WebDavConnectionService(
      client: MockClient((_) async => http.Response('', 401)),
    );

    expect(
      await service.verify(
        connection: _connection(Uri.parse('https://nas.example.com/dav/')),
        credentials: credentials,
      ),
      NasConnectionCheck.unauthorized,
    );
    expect(
      await service.verify(
        connection: _connection(Uri.parse('ftp://nas.example.com/dav/')),
        credentials: credentials,
      ),
      NasConnectionCheck.unsupported,
    );
  });

  test('只读取 WebDAV 根目录第一层的受支持视频文件', () async {
    final service = WebDavConnectionService(
      client: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(request.headers['depth'], '1');
        return http.Response('''
          <d:multistatus xmlns:d="DAV:">
            <d:response><d:href>/dav/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
            <d:response><d:href>/dav/animation%20file.mp4</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
            <d:response><d:href>/dav/photo.jpg</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
            <d:response><d:href>/dav/folder/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
          </d:multistatus>
        ''', 207);
      }),
    );

    final files = await service.listRootMedia(
      connection: _connection(Uri.parse('https://nas.example.com/dav')),
      credentials: credentials,
    );

    expect(files, hasLength(1));
    expect(files.single.name, 'animation file.mp4');
    expect(files.single.uri.path, '/dav/animation%20file.mp4');
  });
}

NasConnection _connection(Uri endpoint) => NasConnection(
      id: 'home-webdav',
      name: '家庭 WebDAV',
      protocol: NasProtocol.webDav,
      endpoint: endpoint,
      credentialsRef: 'secure://nas/home-webdav',
    );
