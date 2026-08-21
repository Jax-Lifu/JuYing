import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/sources/playlist_source_store.dart';
import 'package:juying/domain/models/playlist_source.dart';

void main() {
  test('直播来源只持久化 HTTP(S) 清单元数据和权利确认时间', () async {
    final storage = _MemoryStorage();
    final store = PlaylistSourceStore(storage: storage);
    final source = PlaylistSourceDefinition(
      id: 'playlist-home',
      name: '家庭清单',
      playlistUri: Uri.parse('https://playlist.example/home.m3u'),
      rightsConfirmedAt: DateTime.utc(2025, 8, 20),
    );

    await store.upsert(source);
    final restored = (await store.load()).single;

    expect(restored.id, source.id);
    expect(restored.playlistUri, source.playlistUri);
    expect(restored.rightsConfirmedAt, source.rightsConfirmedAt);
    expect(storage.value, isNot(contains('stream.example')));

    await store.remove(source.id);
    expect(await store.load(), isEmpty);
  });

  test('持久化数据中的缺少确认时间或账号信息来源会被忽略', () async {
    final storage = _MemoryStorage()
      ..value =
          '[{"id":"playlist-bad","name":"Bad","playlistUri":"http://user:password@bad.example/a.m3u","rightsConfirmedAt":"2026-08-20T00:00:00.000Z","enabled":true}]';

    expect(await PlaylistSourceStore(storage: storage).load(), isEmpty);
  });

  test('带查询参数的 HTTP 清单会在重启后恢复', () async {
    final storage = _MemoryStorage();
    final store = PlaylistSourceStore(storage: storage);
    final source = PlaylistSourceDefinition(
      id: 'playlist-http-query',
      name: 'HTTP 清单',
      playlistUri: Uri.parse('http://playlist.example/live?token=public'),
      rightsConfirmedAt: DateTime.utc(2026, 8, 20),
    );

    await store.upsert(source);

    expect((await store.load()).single.playlistUri, source.playlistUri);
  });
}

class _MemoryStorage implements PlaylistSourceStorage {
  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async => this.value = value;
}
