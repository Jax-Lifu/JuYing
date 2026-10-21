// JSON factories are intentionally colocated with serialization methods.
// ignore_for_file: sort_constructors_first

import 'package:flutter/foundation.dart';

/// Supported LAN Storage Protocols.
enum NasProtocol {
  smb('Samba (SMBv2/v3)', 445),
  nfs('NFSv3', 2049),
  webdav('WebDAV / Alist', 5005);

  const NasProtocol(this.label, this.defaultPort);
  final String label;
  final int defaultPort;
}

/// Represents a configured LAN NAS storage server connection (Samba, NFS, WebDAV).
@immutable
class NasServerConfig {
  const NasServerConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    this.hostname,
    this.port,
    this.username,
    this.password,
    this.shareName = '',
    this.isAnonymous = false,
  });

  final String id;
  final String name;
  final NasProtocol protocol;
  final String host;
  final String? hostname;
  final int? port;
  final String? username;
  final String? password;
  final String shareName;
  final bool isAnonymous;

  int get effectivePort => port ?? protocol.defaultPort;

  String get summaryUri {
    final hostDisplay =
        (hostname != null && hostname!.isNotEmpty && hostname != host)
            ? '$hostname ($host)'
            : host;

    switch (protocol) {
      case NasProtocol.smb:
        return 'smb://$hostDisplay:$effectivePort/$shareName';
      case NasProtocol.nfs:
        return 'nfs://$hostDisplay:$effectivePort/$shareName';
      case NasProtocol.webdav:
        return 'http://$hostDisplay:$effectivePort/$shareName';
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'host': host,
        'hostname': hostname,
        'port': effectivePort,
        'username': username,
        'shareName': shareName,
        'isAnonymous': isAnonymous,
      };

  factory NasServerConfig.fromJson(Map<String, dynamic> json) {
    return NasServerConfig(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'NAS 存储',
      protocol: NasProtocol.values.firstWhere(
        (p) => p.name == json['protocol'],
        orElse: () => NasProtocol.smb,
      ),
      host: json['host']?.toString() ?? '127.0.0.1',
      hostname: json['hostname']?.toString(),
      port: json['port'] is int ? json['port'] as int : null,
      username: json['username']?.toString(),
      password: json['password']?.toString(),
      shareName: json['shareName']?.toString() ?? '',
      isAnonymous: json['isAnonymous'] == true,
    );
  }

  NasServerConfig copyWith({
    String? id,
    String? name,
    NasProtocol? protocol,
    String? host,
    String? hostname,
    int? port,
    String? username,
    String? password,
    String? shareName,
    bool? isAnonymous,
  }) {
    return NasServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      shareName: shareName ?? this.shareName,
      isAnonymous: isAnonymous ?? this.isAnonymous,
    );
  }
}
