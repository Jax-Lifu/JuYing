import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/playback/playback_preference_store.dart';

void main() {
  test('偏好按档案和来源隔离，且不会存储播放地址', () async {
    final storage = _MemoryStorage();
    final store = PlaybackPreferenceStore(storage: storage);

    await store.save(
      profileId: 'child-a',
      sourceId: 'source-a',
      value: const PlaybackPreferences(
        qualityId: 'quality.hd',
        speed: 1.5,
        volume: 0.4,
      ),
    );

    expect(
      (await store.load(profileId: 'adult-a', sourceId: 'source-a')).qualityId,
      const PlaybackPreferences().qualityId,
    );
    expect(
      (await store.load(profileId: 'child-a', sourceId: 'source-a')).speed,
      1.5,
    );
    expect(
      (await store.load(profileId: 'child-a', sourceId: 'source-b')).qualityId,
      isNull,
    );
    final persisted = jsonDecode(storage.values.values.single) as Map;
    expect(persisted.containsKey('nativeStreamUri'), isFalse);
    expect(persisted.containsKey('officialPageUri'), isFalse);
  });

  test('旧版按来源偏好会迁移到当前档案且限制无效数值', () async {
    final storage = _MemoryStorage()
      ..values['playback.quality.source-a.official'] = '超清'
      ..doubles['playback.speed.source-a'] = 9
      ..doubles['playback.volume.source-a'] = -2;
    final store = PlaybackPreferenceStore(storage: storage);

    final preference = await store.load(
      profileId: 'adult-a',
      sourceId: 'source-a',
    );

    expect(preference.qualityId, '超清');
    expect(preference.speed, 3);
    expect(preference.volume, 0);
    expect(
        storage.values['playback.preferences.v1.adult-a.source-a'], isNotNull);
  });

  test('删除档案时只清除该档案的播放偏好', () async {
    final storage = _MemoryStorage();
    final store = PlaybackPreferenceStore(storage: storage);
    await store.save(
      profileId: 'child-a',
      sourceId: 'source-a',
      value: const PlaybackPreferences(speed: 1.5),
    );
    await store.save(
      profileId: 'adult-a',
      sourceId: 'source-a',
      value: const PlaybackPreferences(speed: 1.25),
    );

    await store.clearProfile('child-a');

    expect(storage.values['playback.preferences.v1.child-a.source-a'], isNull);
    expect(
        storage.values['playback.preferences.v1.adult-a.source-a'], isNotNull);
  });

  test('保存并读取上一次播放的直播频道且按档案隔离', () async {
    final storage = _MemoryStorage();
    final store = PlaybackPreferenceStore(storage: storage);

    expect(
      await store.getLastLiveChannel(
        profileId: 'adult-a',
        sourceId: 'cctv-live-official',
      ),
      isNull,
    );

    await store.saveLastLiveChannel(
      profileId: 'adult-a',
      sourceId: 'cctv-live-official',
      channelId: 'cctv13',
    );

    expect(
      await store.getLastLiveChannel(
        profileId: 'adult-a',
        sourceId: 'cctv-live-official',
      ),
      'cctv13',
    );
    expect(
      await store.getLastLiveChannel(
        profileId: 'child-b',
        sourceId: 'cctv-live-official',
      ),
      isNull,
    );
  });
}

class _MemoryStorage implements PlaybackPreferenceStorage {
  final values = <String, String>{};
  final doubles = <String, double>{};
  final stringLists = <String, List<String>>{};

  @override
  Future<double?> readDouble(String key) async => doubles[key];

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<List<String>?> readStringList(String key) async => stringLists[key];

  @override
  Future<void> writeString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> writeStringList(String key, List<String> value) async {
    stringLists[key] = List.of(value);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
    doubles.remove(key);
    stringLists.remove(key);
  }
}
