import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:juying/app/bootstrap.dart';
import 'package:juying/app/router.dart';
import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/app/theme/theme_provider.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/i18n/locale_provider.dart';

/// Entry point of the JuYing application (Section 6.1 main.dart).
///
/// **What**: Delegates startup orchestration to [bootstrap] and mounts the root [JuYingApp].
///
/// **Why**: Implements Section 6.1 application skeleton: `main.dart` serves as the concise
/// entrypoint, delegating lifecycle and service initialization to `app/bootstrap.dart`.
void main() {
  bootstrap(() => const JuYingApp());
}

/// Root application widget configuring dynamic routes, themes, and locale definitions.
class JuYingApp extends ConsumerWidget {
  const JuYingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeThemePreset = ref.watch(themeProvider);
    final activeLanguage = ref.watch(localeProvider);

    final platformBrightness = MediaQuery.maybePlatformBrightnessOf(context) ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    final effectiveColors = activeThemePreset == AppThemePreset.system
        ? (platformBrightness == Brightness.light
            ? AppThemeColors.cleanLight
            : AppThemeColors.vscodeDark)
        : activeThemePreset.colors;

    return MaterialApp.router(
      title: '聚映',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(effectiveColors),
      locale: activeLanguage.locale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLanguage.values.map((l) => l.locale).toList(),
      routerConfig: appRouter,
    );
  }
}
