import '../juying_source_providers.dart';

/// Local Filesystem Media Provider (LIB-01).
class LocalFsSourceProvider implements SourceProvider {
  @override
  String get type => 'local_fs';

  @override
  Set<SourceCapability> get capabilities => {
        SourceCapability.vod,
        SourceCapability.browse,
      };

  @override
  Future<SourceValidationResult> validate(SourceConfig config) async {
    return const SourceValidationResult(isValid: true);
  }
}

/// Samba SMB2/3 Media Storage Provider (LIB-02).
class SmbSourceProvider implements SourceProvider {
  @override
  String get type => 'smb';

  @override
  Set<SourceCapability> get capabilities => {
        SourceCapability.vod,
        SourceCapability.browse,
      };

  @override
  Future<SourceValidationResult> validate(SourceConfig config) async {
    if (config.endpoint.startsWith('smb://') || config.endpoint.isNotEmpty) {
      return const SourceValidationResult(isValid: true);
    }
    return const SourceValidationResult(
      isValid: false,
      message: 'SMB 主机地址或共享路径无效',
    );
  }
}

/// WebDAV & Alist Virtual Drive Provider (LIB-03).
class WebDavSourceProvider implements SourceProvider {
  @override
  String get type => 'webdav';

  @override
  Set<SourceCapability> get capabilities => {
        SourceCapability.vod,
        SourceCapability.browse,
      };

  @override
  Future<SourceValidationResult> validate(SourceConfig config) async {
    final uri = Uri.tryParse(config.endpoint);
    if (uri != null && uri.hasScheme) {
      return const SourceValidationResult(isValid: true);
    }
    return const SourceValidationResult(
      isValid: false,
      message: 'WebDAV 服务端地址必须是有效的 HTTP(S) URL',
    );
  }
}

/// NFSv3/v4 Media Storage Provider (LIB-07 & PoC-7).
class NfsSourceProvider implements SourceProvider {
  @override
  String get type => 'nfs';

  @override
  Set<SourceCapability> get capabilities => {
        SourceCapability.vod,
        SourceCapability.browse,
      };

  @override
  Future<SourceValidationResult> validate(SourceConfig config) async {
    if (config.endpoint.startsWith('nfs://') || config.endpoint.isNotEmpty) {
      return const SourceValidationResult(isValid: true);
    }
    return const SourceValidationResult(
      isValid: false,
      message: 'NFS 挂载路径或服务器地址无效',
    );
  }
}
