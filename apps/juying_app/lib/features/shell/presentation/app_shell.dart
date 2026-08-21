import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/config/source_configuration.dart';
import '../../../core/i18n/app_strings.dart';
import '../../../application/playback/playback_history_store.dart';
import '../../../application/playback/playback_launcher.dart';
import '../../../application/playback/playback_telemetry.dart';
import '../../../application/nas/nas_connection_store.dart';
import '../../../application/nas/nas_credential_store.dart';
import '../../../application/profiles/profile_session.dart';
import '../../../application/profiles/profile_data_cleaner.dart';
import '../../../application/sources/media_source_registry.dart';
import '../../../application/sources/media_source_adapter_factory.dart';
import '../../../application/sources/playlist_source_store.dart';
import '../../../application/sources/playlist_source_activation_service.dart';
import '../../../application/sources/tvbox_source_activation_service.dart';
import '../../../application/sources/tvbox_source_store.dart';
import '../../../application/sources/source_enablement_store.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../home/presentation/home_page.dart';
import '../../kids/presentation/kids_page.dart';
import '../../library/presentation/library_page.dart';
import '../../search/presentation/search_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../../infrastructure/cctv/cctv_repository.dart';
import '../../../infrastructure/nas/webdav_connection_service.dart';
import '../../../domain/models/playlist_source.dart';
import '../../../domain/models/tvbox_source.dart';
import '../../../platform/windows/windows_playback_launcher.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.config,
    required this.sourceConfiguration,
    required this.settings,
    super.key,
  });

  final AppConfig config;
  final SourceConfiguration sourceConfiguration;
  final AppSettingsController settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _selectedIndex = 0;
  late final CctvRepository _cctvRepository = CctvRepository();
  late final http.Client _sourceClient = http.Client();
  late final MediaSourceAdapterFactory _adapterFactory =
      MediaSourceAdapterFactory(
          cctvRepository: _cctvRepository, client: _sourceClient);
  late final MediaSourceRegistry _sources = MediaSourceRegistry(
      _adapterFactory.createAll(widget.sourceConfiguration));
  late final SourceEnablementStore _sourceEnablementStore =
      SourceEnablementStore();
  late final PlaylistSourceStore _playlistSourceStore = PlaylistSourceStore();
  late final PlaylistSourceActivationService _playlistSources =
      PlaylistSourceActivationService(
    store: _playlistSourceStore,
    registry: _sources,
    client: _sourceClient,
  );
  late final TvboxSourceActivationService _tvboxSources =
      TvboxSourceActivationService(
    store: TvboxSourceStore(),
    registry: _sources,
    client: _sourceClient,
  );
  late final PlaybackHistoryStore _historyStore = PlaybackHistoryStore();
  late final PlaybackLauncher _playbackLauncher = WindowsPlaybackLauncher();
  final PlaybackTelemetry _playbackTelemetry = PlaybackTelemetry.shared;
  late final ProfileDataCleaner _profileDataCleaner = ProfileDataCleaner();
  late final ProfileSession _profiles =
      ProfileSession(dataCleaner: _profileDataCleaner);
  late final NasConnectionStore _nasConnectionStore = NasConnectionStore();
  late final NasCredentialStore _nasCredentialStore = NasCredentialStore();
  late final WebDavConnectionService _webDavService = WebDavConnectionService();

  @override
  void initState() {
    super.initState();
    _profiles.addListener(_onProfilesChanged);
    _sources.addListener(_onSourcesChanged);
    _profiles.initialize();
    _initializeSources();
  }

  @override
  void dispose() {
    _profiles.removeListener(_onProfilesChanged);
    _sources.removeListener(_onSourcesChanged);
    _cctvRepository.close();
    _sourceClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final destinations = [
      _Destination(strings.home, Icons.home_rounded),
      _Destination(strings.search, Icons.search_rounded),
      _Destination(strings.kids, Icons.child_care_rounded),
      _Destination(strings.library, Icons.video_library_rounded),
      _Destination(strings.settings, Icons.tune_rounded),
    ];
    final pages = [
      HomePage(
        config: widget.config,
        adapters: _sources.allAdapters,
        historyStore: _historyStore,
        playbackLauncher: _playbackLauncher,
        profileId: _profiles.activeProfile.id,
        isChildProfile: _profiles.activeProfile.isChild,
        childDailyLimitMinutes:
            _profiles.activeProfile.child?.dailyLimitMinutes,
        onOpenProfiles: () => _select(2),
        onRetrySource: () =>
            _sources.restoreSource(_sources.allAdapters.first.source.id),
        onNavigateTab: _select,
      ),
      SearchPage(
        adapters: _sources.allAdapters,
        profileId: _profiles.activeProfile.id,
        isChildProfile: _profiles.activeProfile.isChild,
        playbackLauncher: _playbackLauncher,
        childDailyLimitMinutes:
            _profiles.activeProfile.child?.dailyLimitMinutes,
      ),
      KidsPage(session: _profiles),
      LibraryPage(
        connectionStore: _nasConnectionStore,
        credentialStore: _nasCredentialStore,
        webDavService: _webDavService,
        profileId: _profiles.activeProfile.id,
        isChildProfile: _profiles.activeProfile.isChild,
        playbackLauncher: _playbackLauncher,
        playlistSources: _sources.allAdapters,
        onAddPlaylistSource: _addPlaylistSource,
        onRemovePlaylistSource: _removePlaylistSource,
      ),
      SettingsPage(
        config: widget.config,
        settings: widget.settings,
        sources: _sources.allAdapters.map((adapter) => adapter.source).toList(),
        onSourceEnabledChanged: _setSourceEnabled,
        profileId: _profiles.activeProfile.id,
        onClearProfileData: _profileDataCleaner.clear,
        telemetry: _playbackTelemetry,
        onAddPlaylistSource: _addPlaylistSource,
        onAddTvboxSource: _addTvboxSource,
        onRemovePlaylistSource: _removePlaylistSource,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 820;
      final content = AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(
          key: ValueKey(_selectedIndex),
          child: pages[_selectedIndex],
        ),
      );
      if (wide) {
        return Scaffold(
          body: SafeArea(
            child: Row(children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: _BrandMark(label: strings.appName),
                ),
                destinations: destinations
                    .map((item) => NavigationRailDestination(
                          icon: Icon(item.icon),
                          label: Text(item.label),
                        ))
                    .toList(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ]),
          ),
        );
      }
      return Scaffold(
        body: SafeArea(child: content),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _select,
          destinations: destinations
              .map((item) => NavigationDestination(
                    icon: Icon(item.icon),
                    label: item.label,
                  ))
              .toList(),
        ),
      );
    });
  }

  void _select(int value) => setState(() => _selectedIndex = value);

  void _onProfilesChanged() {
    if (mounted) setState(() {});
  }

  void _onSourcesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initializeSources() async {
    await _playlistSources.restorePersisted();
    await _tvboxSources.restorePersisted();
    final disabledIds = await _sourceEnablementStore.loadDisabledSourceIds();
    for (final adapter in _sources.allAdapters) {
      if (disabledIds.contains(adapter.source.id)) {
        _sources.setEnabled(adapter.source.id, false);
      }
    }
  }

  Future<void> _addPlaylistSource(PlaylistSourceDefinition definition) async {
    await _playlistSources.detectAndActivate(definition);
  }

  Future<void> _addTvboxSource(TvboxSourceDefinition definition) async {
    await _tvboxSources.detectAndActivate(definition);
  }

  Future<void> _removePlaylistSource(String sourceId) async {
    if (sourceId.startsWith('tvbox-')) {
      await _tvboxSources.remove(sourceId);
    } else {
      await _playlistSources.remove(sourceId);
    }
    await _sourceEnablementStore.setEnabled(sourceId, true);
  }

  Future<void> _setSourceEnabled(String sourceId, bool enabled) async {
    if (!_sources.setEnabled(sourceId, enabled)) return;
    await _sourceEnablementStore.setEnabled(sourceId, enabled);
  }
}

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
        ),
      );
}
