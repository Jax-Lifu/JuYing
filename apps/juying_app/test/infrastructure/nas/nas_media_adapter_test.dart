import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/nas/nas_credential_store.dart';
import 'package:juying/domain/models/nas_connection.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/infrastructure/nas/nas_media_adapter.dart';

void main() {
  group('NasMediaAdapter', () {
    test('Samba (SMB) 适配器解析带凭据的原生播放地址', () async {
      final connection = NasConnection(
        id: 'smb-123',
        name: '客厅 NAS Samba',
        protocol: NasProtocol.smb,
        endpoint: Uri.parse('smb://192.168.1.100/video/movie.mkv'),
        credentialsRef: 'secure://nas/smb-123',
      );
      final adapter = NasMediaAdapter(
        connection: connection,
        credentials: const NasCredentials(username: 'admin', password: 'pwd!123'),
      );

      final page = await adapter.browse(
        const MediaCatalogQuery(category: MediaCategory.other),
      );
      expect(page.items.length, 1);
      expect(page.items.first.title, 'movie.mkv');

      final episodes = await adapter.episodes(page.items.first);
      expect(episodes.length, 1);

      final playback = await adapter.resolvePlayback(episodes.first);
      expect(
        playback.nativeStreamUri,
        Uri.parse('smb://admin:pwd!123@192.168.1.100/video/movie.mkv'),
      );
    });

    test('NFS 适配器解析原生共享播放地址', () async {
      final connection = NasConnection(
        id: 'nfs-456',
        name: '影视库 NFS',
        protocol: NasProtocol.nfs,
        endpoint: Uri.parse('nfs://192.168.1.200/volume1/media/show.mp4'),
        credentialsRef: 'secure://nas/nfs-456',
      );
      final adapter = NasMediaAdapter(
        connection: connection,
        credentials: const NasCredentials(username: '', password: ''),
      );

      final page = await adapter.browse(
        const MediaCatalogQuery(category: MediaCategory.other),
      );
      expect(page.items.length, 1);
      expect(page.items.first.title, 'show.mp4');

      final episodes = await adapter.episodes(page.items.first);
      final playback = await adapter.resolvePlayback(episodes.first);
      expect(
        playback.nativeStreamUri,
        Uri.parse('nfs://192.168.1.200/volume1/media/show.mp4'),
      );
    });
  });
}
