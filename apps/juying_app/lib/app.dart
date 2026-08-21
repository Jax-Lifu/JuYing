import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/config/app_config.dart';
import 'core/config/source_configuration.dart';
import 'core/i18n/app_strings.dart';
import 'core/settings/app_settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/presentation/app_shell.dart';

class JuYingApp extends StatefulWidget {
  const JuYingApp({
    required this.config,
    required this.sourceConfiguration,
    super.key,
  });

  final AppConfig config;
  final SourceConfiguration sourceConfiguration;

  @override
  State<JuYingApp> createState() => _JuYingAppState();
}

class _JuYingAppState extends State<JuYingApp> {
  late final AppSettingsController _settings = AppSettingsController(
    fallbackLocale: localeFromTag(widget.config.defaultLocale),
  );

  @override
  void initState() {
    super.initState();
    _settings.initialize();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _settings,
        builder: (context, _) => MaterialApp(
          title: widget.config.appName,
          debugShowCheckedModeBanner: false,
          theme: _settings.highContrast
              ? AppTheme.highContrastLight
              : AppTheme.light,
          darkTheme: _settings.highContrast
              ? AppTheme.highContrastDark
              : AppTheme.dark,
          themeMode: _settings.themeMode,
          locale: _settings.locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AppShell(
            config: widget.config,
            sourceConfiguration: widget.sourceConfiguration,
            settings: _settings,
          ),
        ),
      );
}
