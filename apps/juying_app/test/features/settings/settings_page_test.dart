import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juying/core/config/app_config.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/settings/app_settings_controller.dart';
import 'package:juying/application/playback/playback_telemetry.dart';
import 'package:juying/domain/models/playlist_source.dart';
import 'package:juying/features/settings/presentation/settings_page.dart';

void main() {
  testWidgets('设置页跟随当前语言显示核心文案', (tester) async {
    final settings = AppSettingsController(fallbackLocale: const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: SettingsPage(
            config: AppConfig.development(),
            settings: settings,
            sources: AppConfig.development().sources,
            onSourceEnabledChanged: (sourceId, enabled) async {},
            profileId: 'adult-default',
            onClearProfileData: (_) async {},
            telemetry: PlaybackTelemetry(),
          ),
        ),
      ),
    );

    expect(find.text('Appearance & language'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Content sources'),
      160,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Content sources'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Family & device'),
      160,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Family & device'), findsOneWidget);
  });

  testWidgets('内容来源开关将用户选择交给来源注册表入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? changedSource;
    bool? changedEnabled;
    final settings = AppSettingsController(fallbackLocale: const Locale('zh'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: SettingsPage(
            config: AppConfig.development(),
            settings: settings,
            sources: AppConfig.development().sources,
            onSourceEnabledChanged: (sourceId, enabled) async {
              changedSource = sourceId;
              changedEnabled = enabled;
            },
            profileId: 'adult-default',
            onClearProfileData: (_) async {},
            telemetry: PlaybackTelemetry(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('内容来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(changedSource, 'cctv-official');
    expect(changedEnabled, isFalse);
  });

  testWidgets('来源管理可手动检测并自动添加已确认权利的 M3U', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    PlaylistSourceDefinition? added;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: SettingsPage(
            config: AppConfig.development(),
            settings: AppSettingsController(fallbackLocale: const Locale('zh')),
            sources: AppConfig.development().sources,
            onSourceEnabledChanged: (_, __) async {},
            onAddPlaylistSource: (source) async => added = source,
            profileId: 'adult-default',
            onClearProfileData: (_) async {},
            telemetry: PlaybackTelemetry(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('内容来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加 IPTV 直播来源'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '家庭直播');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://playlist.example/family.m3u',
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('检测并自动添加'));
    await tester.pumpAndSettle();

    expect(added?.name, '家庭直播');
    expect(
        added?.playlistUri, Uri.parse('https://playlist.example/family.m3u'));
    expect(added?.rightsConfirmedAt, isNotNull);
  });

  testWidgets('来源管理可预填 IPTV-ORG 的公开 M3U 地址', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: SettingsPage(
            config: AppConfig.development(),
            settings: AppSettingsController(fallbackLocale: const Locale('zh')),
            sources: AppConfig.development().sources,
            onSourceEnabledChanged: (_, __) async {},
            onAddPlaylistSource: (_) async {},
            profileId: 'adult-default',
            onClearProfileData: (_) async {},
            telemetry: PlaybackTelemetry(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('内容来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加 IPTV-ORG 直播来源'));
    await tester.pumpAndSettle();

    expect(find.text('IPTV-ORG'), findsOneWidget);
    expect(
        find.text('https://iptv-org.github.io/iptv/index.m3u'), findsOneWidget);
  });

  testWidgets('清除数据仅调用当前档案的本地清理入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? clearedProfileId;
    final settings = AppSettingsController(fallbackLocale: const Locale('zh'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: SettingsPage(
            config: AppConfig.development(),
            settings: settings,
            sources: AppConfig.development().sources,
            onSourceEnabledChanged: (sourceId, enabled) async {},
            profileId: 'child-7',
            onClearProfileData: (profileId) async {
              clearedProfileId = profileId;
            },
            telemetry: PlaybackTelemetry(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('清除此档案的本机数据'));
    await tester.pumpAndSettle();
    expect(find.text('清除本机档案数据？'), findsOneWidget);
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    expect(clearedProfileId, 'child-7');
    expect(find.text('已清除本机档案数据'), findsOneWidget);
  });

  testWidgets('播放诊断仅显示脱敏事件并支持清空', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final telemetry = PlaybackTelemetry();
    telemetry.recordEvent(
      event: PlaybackTelemetryEvent.failed,
      mode: PlaybackTelemetryMode.officialPage,
      sourceId: 'cctv-official',
      sourceEpisodeId: 'episode-3',
      platform: 'windows',
      errorCode: 'official_ready_timeout',
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: SettingsPage(
            config: AppConfig.development(),
            settings: AppSettingsController(fallbackLocale: const Locale('zh')),
            sources: AppConfig.development().sources,
            onSourceEnabledChanged: (sourceId, enabled) async {},
            profileId: 'adult-default',
            onClearProfileData: (_) async {},
            telemetry: telemetry,
          ),
        ),
      ),
    );

    await tester.tap(find.text('播放诊断'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cctv-official / episode-3'), findsOneWidget);
    await tester.tap(find.text('清空诊断'));
    await tester.pump();

    expect(find.text('暂无播放诊断事件'), findsOneWidget);
  });
}
