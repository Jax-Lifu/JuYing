import 'package:flutter/foundation.dart';

/// 服务端公开的可挂载共享目录。
///
/// **What**: 统一承载 Samba share 与 NFS export 的显示名称、远端路径和说明。
/// **Why**: 主机发现只证明协议可达，只有用户选择真实共享后才能形成可用挂载配置。
@immutable
class NasRemoteShare {
  const NasRemoteShare({
    required this.name,
    required this.path,
    this.description,
  });

  final String name;
  final String path;
  final String? description;

  @override
  bool operator ==(Object other) {
    return other is NasRemoteShare &&
        other.name == name &&
        other.path == path &&
        other.description == description;
  }

  @override
  int get hashCode => Object.hash(name, path, description);
}
