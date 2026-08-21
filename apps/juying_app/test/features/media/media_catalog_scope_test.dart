import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/playback/playback_launcher.dart';
import 'package:juying/domain/models/media_source.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/domain/ports/media_source_adapter.dart';
import 'package:juying/domain/ports/source_catalog_scopes.dart';
import 'package:juying/features/media/presentation/media_catalog_page.dart'
    as presentation;

void main() {
  testWidgets('统一目录页显示来源内站点名称和 key，并允许切换', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = _ScopedAdapter();

    await tester.pumpWidget(MaterialApp(
      home: presentation.MediaCatalogPage(
        adapter: adapter,
        profileId: 'adult-default',
        isChildProfile: false,
        playbackLauncher: const _PlaybackLauncher(),
        initialCategory: MediaCategory.movie,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('站点（2）'), findsOneWidget);
    expect(find.text('全部站点'), findsOneWidget);
    expect(find.text('可用站点'), findsOneWidget);
    expect(find.text('自动选择可用站点'), findsOneWidget);

    await tester.tap(find.text('自动选择可用站点'));
    await tester.pumpAndSettle();
    expect(find.text('一号站 · alpha'), findsOneWidget);
    expect(find.text('二号站 · beta'), findsOneWidget);

    await tester.tap(find.text('二号站 · beta'));
    await tester.pumpAndSettle();

    expect(adapter.selectedCatalogScopeId, 'beta');
    expect(adapter.browsedScopes.last, 'beta');

    await tester.tap(find.text('可用站点'));
    await tester.pumpAndSettle();

    expect(find.text('站点（可用 1 / 全部 2）'), findsOneWidget);
    expect(adapter.selectedCatalogScopeId, isNull);
    expect(adapter.availabilityChecks, 1);
  });
}

class _ScopedAdapter implements MediaSourceAdapter, SourceCatalogScopes {
  @override
  final MediaSource source = const MediaSource(
    id: 'scoped-source',
    name: '多站点来源',
    kind: MediaSourceKind.custom,
    entryUrl: 'https://config.example/source.json',
    enabled: true,
    authorization: SourceAuthorization.userOwned,
    capabilities: {SourceCapability.browse},
  );

  @override
  String? selectedCatalogScopeId;

  final browsedScopes = <String?>[];
  var availabilityChecks = 0;

  @override
  Future<Set<String>> availableCatalogScopeIds({
    required MediaCategory category,
    bool refresh = false,
  }) async {
    availabilityChecks++;
    return const {'alpha'};
  }

  @override
  Future<List<SourceCatalogScope>> catalogScopes() async => const [
        SourceCatalogScope(id: 'alpha', label: '一号站', sourceKey: 'alpha'),
        SourceCatalogScope(id: 'beta', label: '二号站', sourceKey: 'beta'),
      ];

  @override
  Future<void> selectCatalogScope(String? id) async {
    selectedCatalogScopeId = id;
  }

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) async {
    browsedScopes.add(selectedCatalogScopeId);
    return MediaCatalogPage(items: const [], page: query.page, total: 0);
  }

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) => Future.value(const []);

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(MediaEpisode episode) =>
      throw UnimplementedError();

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) =>
      throw UnimplementedError();

  @override
  Future<List<MediaSearchHit>> search(String query) => Future.value(const []);
}

class _PlaybackLauncher implements PlaybackLauncher {
  const _PlaybackLauncher();

  @override
  Future<void> launchNative(
    BuildContext context,
    PlaybackLaunchRequest request,
  ) async {}

  @override
  Future<void> launchOfficial(
    BuildContext context,
    PlaybackLaunchRequest request,
  ) async {}
}
