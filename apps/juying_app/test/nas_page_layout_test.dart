import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/features/nas/models/nas_server_config.dart';
import 'package:juying/features/nas/models/nas_share_item.dart';
import 'package:juying/features/nas/presentation/nas_page.dart';
import 'package:juying/features/nas/providers/nas_provider.dart';
import 'package:juying/features/nas/services/nas_credential_store.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mounted NAS header fits and keeps large server sets navigable',
      (tester) async {
    await _pumpNasPage(tester, _servers);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);

    final unmountFocus = tester.widget<TvFocusWrapper>(
      find.ancestor(
        of: find.text('卸载'),
        matching: find.byType(TvFocusWrapper),
      ),
    );
    final detailsFocus = tester.widget<TvFocusWrapper>(
      find.ancestor(
        of: find.text('详情'),
        matching: find.byType(TvFocusWrapper),
      ),
    );
    expect(unmountFocus.borderRadius, BorderRadius.circular(8));
    expect(detailsFocus.borderRadius, BorderRadius.circular(6));
  });

  testWidgets('empty NAS header reserves the permanent TV focus ring',
      (tester) async {
    await _pumpNasPage(tester, const <NasServerConfig>[]);

    expect(tester.takeException(), isNull);
    expect(find.text('尚未挂载任何 NAS 存储'), findsOneWidget);
  });
}

Future<void> _pumpNasPage(
  WidgetTester tester,
  List<NasServerConfig> servers,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1200, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        nasServersProvider.overrideWith(
          (ref) => _TestNasServersNotifier(servers),
        ),
        nasDirectoryContentsProvider.overrideWith(
          (ref) async => <NasShareItem>[],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.buildTheme(AppThemeColors.cinemaDark),
        home: const NasPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final List<NasServerConfig> _servers = List<NasServerConfig>.generate(
  12,
  (index) => NasServerConfig(
    id: 'nas-$index',
    name: 'NAS $index · share',
    protocol: index.isEven ? NasProtocol.smb : NasProtocol.nfs,
    host: '192.168.1.${index + 10}',
    shareName: 'media-$index',
  ),
);

class _TestNasServersNotifier extends NasServersNotifier {
  _TestNasServersNotifier(List<NasServerConfig> servers)
      : super(credentialStore: _MemoryCredentialStore()) {
    state = servers;
  }
}

class _MemoryCredentialStore implements NasCredentialStore {
  @override
  Future<void> deletePassword(String serverId) async {}

  @override
  Future<String?> readPassword(String serverId) async => null;

  @override
  Future<void> writePassword(String serverId, String password) async {}
}
