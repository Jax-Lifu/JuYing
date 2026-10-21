import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:juying/core/i18n/app_strings.dart';

/// Global state provider managing active application locale.
///
/// **What**: Persists and notifies UI components whenever the user toggles
/// between Chinese (Simplified/Traditional), Japanese, Korean, English, French, German, Spanish, and Russian.
///
/// **Why**: Media aggregation clients used across international regions or TV setups
/// require dynamic, reactive language switching without application restarts.
class LocaleNotifier extends StateNotifier<AppLanguage> {
  LocaleNotifier() : super(AppLanguage.zhCN);

  void setLanguage(AppLanguage language) {
    state = language;
    I18nService.instance.loadLanguage(language.code);
  }

  void setLocaleByCode(String code) {
    for (final lang in AppLanguage.values) {
      if (code.startsWith(lang.code) ||
          code.startsWith(lang.locale.languageCode)) {
        setLanguage(lang);
        return;
      }
    }
    setLanguage(AppLanguage.zhCN);
  }
}

final StateNotifierProvider<LocaleNotifier, AppLanguage> localeProvider =
    StateNotifierProvider<LocaleNotifier, AppLanguage>((ref) {
  return LocaleNotifier();
});
