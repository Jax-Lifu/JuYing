enum NasProtocol { smb, webDav, nfs, jellyfin, plex, emby }

class NasConnection {
  const NasConnection({
    required this.id,
    required this.name,
    required this.protocol,
    required this.endpoint,
    required this.credentialsRef,
    this.lastVerifiedAt,
  });

  final String id;
  final String name;
  final NasProtocol protocol;
  final Uri endpoint;

  /// 仅保存 secure:// 引用；用户名、密码、cookie、token 绝不可出现在配置中。
  final String credentialsRef;
  final DateTime? lastVerifiedAt;
}
