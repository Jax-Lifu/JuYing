import 'package:flutter_test/flutter_test.dart';
import 'package:juying/features/tvbox/services/cctv_vod_adapter.dart';

void main() {
  group('CctvVodAdapter Tests', () {
    test('fetches CCTV animation album list from official REST API', () async {
      final adapter = CctvVodAdapter();
      final albums = await adapter.fetchAlbumList(
        channelId: CctvVodAdapter.channelAnimation,
        firstCategory: '动画片',
        pageSize: 5,
      );

      expect(albums, isNotEmpty);
      expect(albums.first.title, isNotEmpty);
      expect(albums.first.id, startsWith('cctv_album_'));
    });

    test('fetches CCTV album episodes and resolves real HLS manifest',
        () async {
      final adapter = CctvVodAdapter();
      // Test album: 《小小围棋少年》VIDA8lgsyrdD1LuVvEdkr2Fd260625
      final candidate =
          await adapter.fetchAlbumEpisodes('VIDA8lgsyrdD1LuVvEdkr2Fd260625');

      expect(candidate, isNotNull);
      expect(candidate!.episodes, isNotEmpty);
      expect(candidate.episodes.first.url, startsWith('cctv_guid://'));

      // Resolve GUID to real HLS URL
      final guid = candidate.episodes.first.url.replaceAll('cctv_guid://', '');
      final hlsUrl = await adapter.resolveCctvGuid(guid);

      expect(hlsUrl, isNotNull);
      expect(hlsUrl, startsWith('http'));
      expect(hlsUrl, contains('.m3u8'));
    });
  });
}
