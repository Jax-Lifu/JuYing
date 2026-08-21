import 'package:flutter/services.dart';

import '../../domain/models/media_source.dart';
import 'source_configuration.dart';

class AppConfig {
  const AppConfig({
    required this.appName,
    required this.environment,
    required this.defaultLocale,
    required this.sources,
  });

  final String appName;
  final String environment;
  final String defaultLocale;
  final List<MediaSource> sources;

  /// 加载随应用发布的声明式来源清单；不会访问第三方配置 URL。
  static Future<LoadedAppConfig> loadBundled() async {
    try {
      final raw = await rootBundle.loadString('assets/config/sources.json');
      final sourceConfiguration = SourceConfiguration.fromJsonString(raw);
      return LoadedAppConfig(
        appConfig: AppConfig(
          appName: '聚映',
          environment: 'development',
          defaultLocale: 'zh-CN',
          sources: sourceConfiguration.sources
              .map((configured) => configured.source)
              .toList(growable: false),
        ),
        sourceConfiguration: sourceConfiguration,
      );
    } catch (_) {
      final fallback = AppConfig.development();
      return LoadedAppConfig(
        appConfig: fallback,
        sourceConfiguration: developmentSourceConfiguration(),
      );
    }
  }

  factory AppConfig.development() => const AppConfig(
        appName: '聚映',
        environment: 'development',
        defaultLocale: 'zh-CN',
        sources: [
          MediaSource(
            id: 'cctv-official',
            name: 'CCTV 节目官网',
            kind: MediaSourceKind.officialWeb,
            entryUrl:
                'https://tv.cctv.com/yxg/index.shtml?spm=C28340.P2qo7O8Q1Led.EEfEAhEnQFPl.64#datacid=dhp&datafl=&datadq=&fc=%E5%8A%A8%E7%94%BB%E7%89%87&dataszm=',
            enabled: true,
            authorization: SourceAuthorization.officialEntryOnly,
            capabilities: {
              SourceCapability.browse,
              SourceCapability.search,
              SourceCapability.episodes,
              SourceCapability.officialFallback,
              SourceCapability.qualitySelection,
            },
          ),
          MediaSource(
            id: 'cctv-live-official',
            name: 'CCTV 官方直播',
            kind: MediaSourceKind.officialWeb,
            entryUrl:
                'https://tv.cctv.com/live/index.shtml?spm=C28340.Pu9TN9YUsfNZ.E2PQtIunpEaz.2',
            enabled: true,
            authorization: SourceAuthorization.officialEntryOnly,
            capabilities: {
              SourceCapability.browse,
              SourceCapability.liveCatalog,
              SourceCapability.search,
              SourceCapability.episodes,
              SourceCapability.nativePublicPlayback,
              SourceCapability.officialFallback,
              SourceCapability.fullscreen,
            },
          ),
          MediaSource(
            id: 'iptv-default',
            name: 'IPTV',
            kind: MediaSourceKind.custom,
            entryUrl: 'https://iptv-org.github.io/iptv/index.m3u',
            enabled: true,
            authorization: SourceAuthorization.userOwned,
            capabilities: {
              SourceCapability.browse,
              SourceCapability.liveCatalog,
              SourceCapability.search,
              SourceCapability.episodes,
              SourceCapability.nativePublicPlayback,
              SourceCapability.qualitySelection,
              SourceCapability.volumeControl,
              SourceCapability.fullscreen,
            },
            priority: 85,
          ),
          MediaSource(
            id: 'xhztv-xhz',
            name: '聚玩盒子',
            kind: MediaSourceKind.custom,
            entryUrl: 'http://xhztv.top/xhz/',
            enabled: true,
            authorization: SourceAuthorization.userOwned,
            capabilities: {
              SourceCapability.browse,
              SourceCapability.liveCatalog,
              SourceCapability.search,
              SourceCapability.episodes,
              SourceCapability.nativePublicPlayback,
              SourceCapability.officialFallback,
              SourceCapability.qualitySelection,
              SourceCapability.volumeControl,
              SourceCapability.fullscreen,
            },
            priority: 80,
          ),
          MediaSource(
            id: 'xhztv-4k',
            name: '聚玩盒子 4K',
            kind: MediaSourceKind.custom,
            entryUrl: 'http://xhztv.top/4k.json',
            enabled: true,
            authorization: SourceAuthorization.userOwned,
            capabilities: {
              SourceCapability.browse,
              SourceCapability.liveCatalog,
              SourceCapability.search,
              SourceCapability.episodes,
              SourceCapability.nativePublicPlayback,
              SourceCapability.officialFallback,
              SourceCapability.qualitySelection,
              SourceCapability.volumeControl,
              SourceCapability.fullscreen,
            },
            priority: 70,
          ),
          MediaSource(
            id: 'xhztv-dc',
            name: '聚玩盒子多仓',
            kind: MediaSourceKind.custom,
            entryUrl: 'http://xhztv.top/DC.txt',
            enabled: true,
            authorization: SourceAuthorization.userOwned,
            capabilities: {
              SourceCapability.browse,
              SourceCapability.liveCatalog,
              SourceCapability.search,
              SourceCapability.episodes,
              SourceCapability.nativePublicPlayback,
              SourceCapability.officialFallback,
              SourceCapability.qualitySelection,
              SourceCapability.volumeControl,
              SourceCapability.fullscreen,
            },
            priority: 60,
          ),
        ],
      );

  static SourceConfiguration developmentSourceConfiguration() {
    final sources = AppConfig.development().sources;
    return SourceConfiguration(
      version: 1,
      sources: [
        ConfiguredMediaSource(
          adapter: 'cctvOfficial',
          source: sources[0],
        ),
        ConfiguredMediaSource(
          adapter: 'cctvLiveOfficial',
          source: sources[1],
        ),
        ConfiguredMediaSource(
          adapter: 'playlistConfig',
          source: sources[2],
        ),
        ConfiguredMediaSource(
          adapter: 'tvboxConfig',
          source: sources[3],
        ),
        ConfiguredMediaSource(
          adapter: 'tvboxConfig',
          source: sources[4],
        ),
        ConfiguredMediaSource(
          adapter: 'tvboxConfig',
          source: sources[5],
        ),
      ],
    );
  }
}

class LoadedAppConfig {
  const LoadedAppConfig({
    required this.appConfig,
    required this.sourceConfiguration,
  });

  final AppConfig appConfig;
  final SourceConfiguration sourceConfiguration;
}
