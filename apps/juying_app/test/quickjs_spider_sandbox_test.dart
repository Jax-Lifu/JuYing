import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/tvbox/services/quickjs_spider_sandbox.dart';

void main() {
  bool isQuickJsAvailable() {
    try {
      final sandbox = QuickJsSpiderSandbox();
      sandbox.loadLegacyCatVod('globalThis.__JS_SPIDER__ = {};');
      sandbox.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  final nativeAvailable = isQuickJsAvailable();
  final skipReason = !nativeAvailable
      ? 'Native QuickJS FFI library not available in headless test environment'
      : null;

  test('executes the legacy CatVod contract on QuickJS', () {
    final sandbox = QuickJsSpiderSandbox();
    addTearDown(sandbox.dispose);

    sandbox.loadLegacyCatVod('''
function home() {
  return JSON.stringify({class: [{type_id: 'movie', type_name: '电影'}]});
}
function search(word) {
  return {list: [{vod_id: '1', vod_name: word}]};
}
globalThis.__JS_SPIDER__ = {home, search};
''');

    expect(
      sandbox.invoke('home', const <dynamic>[true]),
      <String, dynamic>{
        'class': <dynamic>[
          <String, dynamic>{'type_id': 'movie', 'type_name': '电影'},
        ],
      },
    );
    expect(
      sandbox.invoke('search', const <dynamic>['庆余年', false]),
      <String, dynamic>{
        'list': <dynamic>[
          <String, dynamic>{'vod_id': '1', 'vod_name': '庆余年'},
        ],
      },
    );
  }, skip: skipReason);

  test('does not expose host process or module loading', () {
    final sandbox = QuickJsSpiderSandbox();
    addTearDown(sandbox.dispose);

    sandbox.loadLegacyCatVod('''
function home() {
  return {process: typeof process, require: typeof require};
}
globalThis.__JS_SPIDER__ = {home};
''');

    expect(
      sandbox.invoke('home', const <dynamic>[]),
      <String, dynamic>{'process': 'undefined', 'require': 'undefined'},
    );
  }, skip: skipReason);

  test('rejects scripts without the CatVod export', () {
    final sandbox = QuickJsSpiderSandbox();
    addTearDown(sandbox.dispose);

    expect(
      () => sandbox.loadLegacyCatVod('const answer = 42;'),
      throwsA(isA<QuickJsSpiderException>()),
    );
  }, skip: skipReason);
}
