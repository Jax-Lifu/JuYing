import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/features/sync/services/webdav_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('migrates complete legacy WebDAV credentials and purges plaintext',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_webdav_url': 'https://dav.example/private/',
      'pref_webdav_user': 'user@example.com',
      'pref_webdav_pass': 'app-secret',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = SecureWebDavCredentialStore();

    final credentials = await store.read(legacyPreferences: preferences);

    expect(credentials?.url, 'https://dav.example/private/');
    expect(credentials?.username, 'user@example.com');
    expect(credentials?.password, 'app-secret');
    expect(preferences.containsKey('pref_webdav_url'), isFalse);
    expect(preferences.containsKey('pref_webdav_user'), isFalse);
    expect(preferences.containsKey('pref_webdav_pass'), isFalse);
    const secureStorage = FlutterSecureStorage();
    expect(
      await secureStorage.read(key: SecureWebDavCredentialStore.passwordKey),
      'app-secret',
    );
  });

  test('does not erase incomplete legacy credentials when migration cannot run',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_webdav_url': 'https://dav.example/private/',
      'pref_webdav_user': 'user@example.com',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = SecureWebDavCredentialStore();

    expect(await store.read(legacyPreferences: preferences), isNull);
    expect(preferences.getString('pref_webdav_url'), isNotNull);
    expect(preferences.getString('pref_webdav_user'), isNotNull);
  });
}
