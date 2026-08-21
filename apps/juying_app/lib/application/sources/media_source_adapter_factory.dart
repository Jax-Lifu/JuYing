import 'package:http/http.dart' as http;

import '../../core/config/source_configuration.dart';
import '../../domain/models/tvbox_source.dart';
import '../../domain/models/playlist_source.dart';
import '../../domain/models/unified_media.dart';
import '../../domain/ports/media_source_adapter.dart';
import '../../infrastructure/cctv/cctv_official_adapter.dart';
import '../../infrastructure/cctv/cctv_live_official_adapter.dart';
import '../../infrastructure/cctv/cctv_repository.dart';
import '../../infrastructure/tvbox/tvbox_config_adapter.dart';
import '../../infrastructure/playlist/m3u_playlist_adapter.dart';
import 'configured_media_source_adapter.dart';

/// 所有来源都从此工厂注册；配置只选择经过审计的适配器，不能携带执行逻辑。
class MediaSourceAdapterFactory {
  MediaSourceAdapterFactory({
    required CctvRepository cctvRepository,
    required http.Client client,
  })  : _cctvRepository = cctvRepository,
        _client = client;

  final CctvRepository _cctvRepository;
  final http.Client _client;

  List<MediaSourceAdapter> createAll(SourceConfiguration configuration) =>
      configuration.sources.map(create).toList(growable: false);

  MediaSourceAdapter create(ConfiguredMediaSource configured) {
    final delegate = switch (configured.adapter) {
      'cctvOfficial' => CctvOfficialAdapter(repository: _cctvRepository),
      'cctvLiveOfficial' => CctvLiveOfficialAdapter(),
      'playlistConfig' => M3uPlaylistAdapter(
          definition: PlaylistSourceDefinition(
            id: configured.source.id,
            name: configured.source.name,
            playlistUri: Uri.parse(configured.source.entryUrl),
            rightsConfirmedAt: DateTime.fromMillisecondsSinceEpoch(0),
            enabled: configured.source.enabled,
          ),
          client: _client,
        ),
      'tvboxConfig' => TvboxConfigAdapter(
          definition: TvboxSourceDefinition(
            id: configured.source.id,
            name: configured.source.name,
            configUri: Uri.parse(configured.source.entryUrl),
            rightsConfirmedAt: DateTime.fromMillisecondsSinceEpoch(0),
            enabled: configured.source.enabled,
          ),
          client: _client,
          initialCategory: MediaCategory.movie,
        ),
      _ => throw SourceConfigurationException(
          '未注册或不受信任的来源适配器：${configured.adapter}'),
    };
    if (configured.source.kind != delegate.source.kind ||
        configured.source.authorization != delegate.source.authorization ||
        configured.source.entryUrl != delegate.source.entryUrl) {
      throw const SourceConfigurationException('来源配置不能修改内建适配器的授权边界或官方入口');
    }
    return ConfiguredMediaSourceAdapter(delegate, configured.source);
  }
}
