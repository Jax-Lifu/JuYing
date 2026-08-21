import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/sources/source_enablement_store.dart';

void main() {
  test('来源启停偏好只保存用户主动停用的来源', () async {
    final storage = _FakeStorage();
    final store = SourceEnablementStore(storage: storage);

    await store.setEnabled('cctv-official', false);
    await store.setEnabled('webdav-private', false);
    await store.setEnabled('cctv-official', true);

    expect(await store.loadDisabledSourceIds(), {'webdav-private'});
  });
}

class _FakeStorage implements SourceEnablementStorage {
  final Map<String, List<String>> _values = {};

  @override
  Future<List<String>?> readStringList(String key) async => _values[key];

  @override
  Future<void> writeStringList(String key, List<String> value) async {
    _values[key] = List.of(value);
  }
}
