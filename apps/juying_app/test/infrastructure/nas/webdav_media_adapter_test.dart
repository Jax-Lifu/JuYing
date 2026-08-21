import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/application/nas/nas_credential_store.dart';
import 'package:juying/domain/models/nas_connection.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/infrastructure/nas/webdav_connection_service.dart';
import 'package:juying/infrastructure/nas/webdav_media_adapter.dart';

void main() {
  test('WebDAV 适配器输出统一条目与会话内原生播放描述', () async {
    final adapter = WebDavMediaAdapter(
      connection: _connection,
      credentials: const NasCredentials(username: 'family', password: 'secret'),
      service: WebDavConnectionService(
        client: MockClient((_) async => http.Response('''
          <d:multistatus xmlns:d="DAV:">
            <d:response><d:href>/dav/movie.mp4</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
          </d:multistatus>
        ''', 207)),
      ),
    );

    final page = await adapter.browse(
      const MediaCatalogQuery(category: MediaCategory.other),
    );
    final item = page.items.single;
    final episode = (await adapter.episodes(item)).single;
    final playback = await adapter.resolvePlayback(episode);

    expect(item.id, 'nas:home:/dav/movie.mp4');
    expect(playback.nativeStreamUri,
        Uri.parse('https://nas.example.com/dav/movie.mp4'));
    expect(playback.httpHeaders['Authorization'], startsWith('Basic '));
    expect(item.title, 'movie.mp4');
  });
}

final _connection = NasConnection(
  id: 'home',
  name: '家庭 NAS',
  protocol: NasProtocol.webDav,
  endpoint: Uri(scheme: 'https', host: 'nas.example.com', path: '/dav'),
  credentialsRef: 'secure://nas/home',
);
