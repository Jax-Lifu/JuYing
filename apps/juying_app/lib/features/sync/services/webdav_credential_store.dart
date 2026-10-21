import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WebDAV 认证信息；URL 也可能包含私有路径，因此与账号、密码一起加密保存。
class WebDavCredentials {
  const WebDavCredentials({
    required this.url,
    required this.username,
    required this.password,
  });

  final String url;
  final String username;
  final String password;

  bool get isComplete =>
      url.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.trim().isNotEmpty;
}

/// WebDAV 凭据存储契约，允许测试替换平台 Keychain/Keystore 实现。
abstract interface class WebDavCredentialStore {
  Future<WebDavCredentials?> read({SharedPreferences? legacyPreferences});

  Future<void> write(
    WebDavCredentials credentials, {
    SharedPreferences? legacyPreferences,
  });

  Future<void> clear({SharedPreferences? legacyPreferences});
}

/// 使用平台安全存储保存 WebDAV 凭据，并一次性迁移旧版明文偏好。
class SecureWebDavCredentialStore implements WebDavCredentialStore {
  SecureWebDavCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String urlKey = 'juying_webdav_url_v1';
  static const String usernameKey = 'juying_webdav_username_v1';
  static const String passwordKey = 'juying_webdav_password_v1';

  static const String _legacyUrlKey = 'pref_webdav_url';
  static const String _legacyUsernameKey = 'pref_webdav_user';
  static const String _legacyPasswordKey = 'pref_webdav_pass';

  final FlutterSecureStorage _storage;

  @override
  Future<WebDavCredentials?> read(
      {SharedPreferences? legacyPreferences}) async {
    final secure = WebDavCredentials(
      url: await _storage.read(key: urlKey) ?? '',
      username: await _storage.read(key: usernameKey) ?? '',
      password: await _storage.read(key: passwordKey) ?? '',
    );
    if (secure.isComplete) return secure;

    final preferences =
        legacyPreferences ?? await SharedPreferences.getInstance();
    final legacy = WebDavCredentials(
      url: preferences.getString(_legacyUrlKey) ?? '',
      username: preferences.getString(_legacyUsernameKey) ?? '',
      password: preferences.getString(_legacyPasswordKey) ?? '',
    );
    if (!legacy.isComplete) return null;

    // 先完成三项安全写入再删除明文，避免迁移中断导致凭据永久丢失。
    await write(legacy, legacyPreferences: preferences);
    return legacy;
  }

  @override
  Future<void> write(
    WebDavCredentials credentials, {
    SharedPreferences? legacyPreferences,
  }) async {
    if (!credentials.isComplete) {
      throw ArgumentError('WebDAV credentials must be complete');
    }
    await _storage.write(key: urlKey, value: credentials.url.trim());
    await _storage.write(
      key: usernameKey,
      value: credentials.username.trim(),
    );
    await _storage.write(key: passwordKey, value: credentials.password);
    await _purgeLegacy(legacyPreferences);
  }

  @override
  Future<void> clear({SharedPreferences? legacyPreferences}) async {
    await _storage.delete(key: urlKey);
    await _storage.delete(key: usernameKey);
    await _storage.delete(key: passwordKey);
    await _purgeLegacy(legacyPreferences);
  }

  Future<void> _purgeLegacy(SharedPreferences? legacyPreferences) async {
    final preferences =
        legacyPreferences ?? await SharedPreferences.getInstance();
    await preferences.remove(_legacyUrlKey);
    await preferences.remove(_legacyUsernameKey);
    await preferences.remove(_legacyPasswordKey);
  }
}
