import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// NAS 密码存储契约，业务状态只持有运行时凭据，不把密码写入普通偏好存储。
abstract interface class NasCredentialStore {
  Future<String?> readPassword(String serverId);

  Future<void> writePassword(String serverId, String password);

  Future<void> deletePassword(String serverId);
}

/// 使用系统 Keychain/Keystore/Credential Locker 保存 NAS 密码。
class SecureNasCredentialStore implements NasCredentialStore {
  SecureNasCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _keyPrefix = 'juying_nas_password_v1_';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readPassword(String serverId) {
    return _storage.read(key: '$_keyPrefix$serverId');
  }

  @override
  Future<void> writePassword(String serverId, String password) {
    return _storage.write(key: '$_keyPrefix$serverId', value: password);
  }

  @override
  Future<void> deletePassword(String serverId) {
    return _storage.delete(key: '$_keyPrefix$serverId');
  }
}
