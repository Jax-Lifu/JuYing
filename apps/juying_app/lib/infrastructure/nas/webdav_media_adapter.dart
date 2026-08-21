import 'dart:convert';

import '../../application/nas/nas_credential_store.dart';
import '../../domain/models/media_source.dart';
import '../../domain/models/nas_connection.dart';
import '../../domain/models/unified_media.dart';
import '../../domain/ports/media_source_adapter.dart';
import 'webdav_connection_service.dart';

/// 用户自有 WebDAV 的会话适配器：不索引、不上传路径，流地址只进入播放会话。
class WebDavMediaAdapter implements MediaSourceAdapter {
  WebDavMediaAdapter({
    required NasConnection connection,
    required NasCredentials credentials,
    required WebDavConnectionService service,
  })  : _connection = connection,
        _credentials = credentials,
        _service = service;

  final NasConnection _connection;
  final NasCredentials _credentials;
  final WebDavConnectionService _service;
  List<WebDavMediaFile>? _files;

  @override
  MediaSource get source => MediaSource(
        id: 'nas:${_connection.id}',
        name: _connection.name,
        kind: MediaSourceKind.nas,
        entryUrl: _connection.endpoint.toString(),
        enabled: true,
        authorization: SourceAuthorization.userOwned,
        capabilities: const {
          SourceCapability.browse,
          SourceCapability.episodes,
          SourceCapability.nativePublicPlayback,
          SourceCapability.playbackSpeed,
          SourceCapability.volumeControl,
          SourceCapability.fullscreen,
          SourceCapability.continueWatching,
        },
      );

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) async {
    if (query.category != MediaCategory.other) {
      return MediaCatalogPage(items: const [], page: query.page, total: 0);
    }
    final files = _files ??= await _service.listRootMedia(
      connection: _connection,
      credentials: _credentials,
    );
    final start = (query.page - 1) * query.pageSize;
    final end = (start + query.pageSize).clamp(0, files.length).toInt();
    final page = start >= files.length
        ? const <WebDavMediaFile>[]
        : files.sublist(start, end);
    return MediaCatalogPage(
      items: page.map(_item).toList(growable: false),
      page: query.page,
      total: files.length,
    );
  }

  @override
  Future<List<MediaSearchHit>> search(String query) async => const [];

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) async {
    _assertSource(item.sourceId);
    final file = await _find(item.sourceItemId);
    return [
      MediaEpisode(
        sourceId: source.id,
        sourceEpisodeId: item.sourceItemId,
        title: file.name,
        officialPageUri: file.uri,
      ),
    ];
  }

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) async {
    _assertSource(episode.sourceId);
    final file = await _find(episode.sourceEpisodeId);
    return PlaybackDescriptor(
      sourceId: source.id,
      sourceEpisodeId: episode.sourceEpisodeId,
      title: file.name,
      officialPageUri: file.uri,
      nativeStreamUri: file.uri,
      httpHeaders: {'Authorization': _authorization},
    );
  }

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(MediaEpisode episode) =>
      Future.error(StateError('NAS 媒体不支持官方页面回退'));

  MediaItem _item(WebDavMediaFile file) => MediaItem(
        sourceId: source.id,
        sourceItemId: file.uri.path,
        title: file.name,
        category: MediaCategory.other,
        officialDetailUri: file.uri,
        defaultEpisodePageUri: file.uri,
      );

  Future<WebDavMediaFile> _find(String path) async {
    final files = _files ??= await _service.listRootMedia(
      connection: _connection,
      credentials: _credentials,
    );
    return files.firstWhere(
      (file) => file.uri.path == path,
      orElse: () => throw StateError('NAS 文件已不存在或不在当前目录'),
    );
  }

  String get _authorization =>
      'Basic ${base64Encode(utf8.encode('${_credentials.username}:${_credentials.password}'))}';

  void _assertSource(String sourceId) {
    if (sourceId != source.id) {
      throw ArgumentError.value(sourceId, 'sourceId', '来源不匹配');
    }
  }
}
