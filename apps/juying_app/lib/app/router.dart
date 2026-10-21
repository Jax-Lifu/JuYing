import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:juying/app/shell.dart';
import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/cctv/presentation/cctv_page.dart';
import 'package:juying/features/detail/presentation/video_detail_page.dart';
import 'package:juying/features/download/presentation/download_page.dart';
import 'package:juying/features/home/presentation/home_page.dart';
import 'package:juying/features/live/presentation/live_page.dart';
import 'package:juying/features/nas/presentation/nas_page.dart';
import 'package:juying/features/receiver/presentation/receiver_page.dart';
import 'package:juying/features/search/presentation/search_page.dart';
import 'package:juying/features/settings/presentation/settings_page.dart';
import 'package:juying/features/sources/presentation/sources_management_page.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'shell');

/// Configures declarative routes for JuYing application (Section 6.1 app/router.dart).
///
/// **Why**: Declarative routing via [GoRouter] provides type-safe deep linking,
/// state preservation across tabs, and responsive layout wrapping via [ShellRoute].
final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: <RouteBase>[
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          name: 'home',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: HomePage(),
          ),
        ),
        GoRoute(
          path: '/cctv',
          name: 'cctv',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: CctvPage(),
          ),
        ),
        GoRoute(
          path: '/live',
          name: 'live',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: LivePage(),
          ),
        ),
        GoRoute(
          path: '/nas',
          name: 'nas',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: NasPage(),
          ),
        ),
        GoRoute(
          path: '/search',
          name: 'search',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: SearchPage(),
          ),
        ),
        GoRoute(
          path: '/download',
          name: 'download',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: DownloadPage(),
          ),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: SettingsPage(),
          ),
        ),
        GoRoute(
          path: '/sources',
          name: 'sources',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: SourcesManagementPage(),
          ),
        ),
        GoRoute(
          path: '/receiver',
          name: 'receiver',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: ReceiverPage(),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/detail',
      name: 'detail',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final media = state.extra as MediaItem?;
        return VideoDetailPage(
          mediaItem: media ??
              const MediaItem(
                id: 'fallback_unknown',
                title: '未知影视',
              ),
        );
      },
    ),
  ],
);
