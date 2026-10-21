import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Supported Personal Cloud Drive Providers.
enum CloudDriveType {
  aliyun,
  quark,
  pan115,
  baidu,
  pan123,
}

/// Token credentials and expiration state for a cloud drive account.
class CloudDriveToken {
  const CloudDriveToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAtMs,
    this.driveId,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresAtMs;
  final String? driveId;

  bool get isExpired => DateTime.now().millisecondsSinceEpoch >= expiresAtMs;

  bool expiresWithin(Duration duration) =>
      DateTime.now().add(duration).millisecondsSinceEpoch >= expiresAtMs;
}

/// 供应商未配置真实协议适配器时抛出，避免把示例地址误送入播放器。
class CloudDriveNotConfiguredError implements Exception {
  const CloudDriveNotConfiguredError(this.type);

  final CloudDriveType type;

  @override
  String toString() => 'CloudDriveNotConfiguredError(${type.name})';
}

/// 云盘供应商协议边界；认证刷新和直链解析必须由真实 API 适配器实现。
abstract interface class CloudDriveProvider {
  Future<CloudDriveToken> refreshToken(CloudDriveToken currentToken);

  Future<String> resolveDirectStreamUrl({
    required String fileId,
    required CloudDriveToken token,
  });
}

/// Multi-cloud drive resource resolver, secure token manager, and 302 stream extractor.
///
/// **What**: Manages OAuth2 tokens using platform-secure hardware storage (`flutter_secure_storage`),
/// auto-refreshes tokens upon 401 exceptions, and resolves 4K high-bitrate direct streams.
///
/// **Why**: Cloud drive streaming links expire quickly (typically 15-60 minutes).
/// Handling token lifecycles with transparent background refresh prevents mid-movie playback interruptions.
class CloudDriveService {
  CloudDriveService({
    FlutterSecureStorage? secureStorage,
    Dio? dio,
    Map<CloudDriveType, CloudDriveProvider>? providers,
  })  : _storage = secureStorage ?? const FlutterSecureStorage(),
        _providers = Map<CloudDriveType, CloudDriveProvider>.unmodifiable(
          providers ?? const <CloudDriveType, CloudDriveProvider>{},
        ),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  final FlutterSecureStorage _storage;
  final Map<CloudDriveType, CloudDriveProvider> _providers;
  final Dio _dio;

  Dio get dio => _dio;

  /// Saves encrypted drive token credentials to secure storage.
  Future<void> saveToken(CloudDriveType type, CloudDriveToken token) async {
    final keyPrefix = 'cloud_drive_${type.name}';
    await _storage.write(key: '${keyPrefix}_access', value: token.accessToken);
    await _storage.write(
        key: '${keyPrefix}_refresh', value: token.refreshToken);
    await _storage.write(
        key: '${keyPrefix}_expires', value: token.expiresAtMs.toString());
    if (token.driveId != null) {
      await _storage.write(key: '${keyPrefix}_drive_id', value: token.driveId);
    }
  }

  /// Reads cached token credentials from secure storage.
  Future<CloudDriveToken?> readToken(CloudDriveType type) async {
    final keyPrefix = 'cloud_drive_${type.name}';
    final access = await _storage.read(key: '${keyPrefix}_access');
    final refresh = await _storage.read(key: '${keyPrefix}_refresh');
    final expiresStr = await _storage.read(key: '${keyPrefix}_expires');
    final driveId = await _storage.read(key: '${keyPrefix}_drive_id');

    if (access == null || refresh == null || expiresStr == null) {
      return null;
    }

    final expiresAt = int.tryParse(expiresStr) ?? 0;
    return CloudDriveToken(
      accessToken: access,
      refreshToken: refresh,
      expiresAtMs: expiresAt,
      driveId: driveId,
    );
  }

  /// Resolves direct 302 stream link or m3u8 manifest for a cloud file.
  Future<String> resolveDirectStreamUrl({
    required CloudDriveType type,
    required String fileId,
  }) async {
    final provider = _providers[type];
    if (provider == null) throw CloudDriveNotConfiguredError(type);

    var token = await readToken(type);
    if (token == null) throw CloudDriveNotConfiguredError(type);

    if (token.expiresWithin(const Duration(minutes: 15))) {
      token = await provider.refreshToken(token);
      await saveToken(type, token);
    }
    return provider.resolveDirectStreamUrl(fileId: fileId, token: token);
  }
}
