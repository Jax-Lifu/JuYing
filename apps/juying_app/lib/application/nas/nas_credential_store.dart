import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NasCredentials {
  const NasCredentials({required this.username, required this.password});
  final String username;
  final String password;
}

/// NAS 凭据仅留在系统安全存储；调用方只得到 secure:// 引用。
class NasCredentialStore {
  NasCredentialStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  Future<String> save({
    required String connectionId,
    required NasCredentials credentials,
  }) async {
    if (credentials.username.trim().isEmpty || credentials.password.isEmpty) {
      throw ArgumentError('NAS 用户名和密码不能为空');
    }
    final ref = 'secure://nas/$connectionId';
    await _secureStorage.write(
      key: ref,
      value: jsonEncode({
        'username': credentials.username,
        'password': credentials.password,
      }),
    );
    return ref;
  }

  Future<NasCredentials?> read(String ref) async {
    if (!ref.startsWith('secure://nas/')) return null;
    try {
      final raw = await _secureStorage.read(key: ref);
      if (raw == null) return null;
      final value = jsonDecode(raw);
      if (value is! Map ||
          value['username'] is! String ||
          value['password'] is! String) {
        return null;
      }
      return NasCredentials(
        username: value['username'] as String,
        password: value['password'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
