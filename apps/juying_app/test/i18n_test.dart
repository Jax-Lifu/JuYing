import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:juying/core/i18n/app_strings.dart';

void main() {
  setUpAll(() {
    // Load local JSON asset files directly into I18nService cache for unit testing
    var dir = Directory('assets/i18n');
    if (!dir.existsSync()) {
      dir = Directory('apps/juying_app/assets/i18n');
    }
    if (dir.existsSync()) {
      for (final file in dir.listSync().whereType<File>()) {
        final code = file.uri.pathSegments.last.replaceAll('.json', '');
        final jsonMap =
            json.decode(file.readAsStringSync()) as Map<String, dynamic>;
        I18nService.instance.setTranslations(
          code,
          jsonMap.map((k, v) => MapEntry<String, String>(k, v.toString())),
        );
      }
    }
  });

  group('i18n Multilingual Tests', () {
    test('resolves translation keys across all 9 mainstream languages', () {
      // 1. Simplified Chinese (zh_CN)
      expect(AppStrings.tr('nav_home', langCode: 'zh_CN'), '首页推荐');
      expect(AppStrings.tr('home_top_pick', langCode: 'zh_CN'), '今日主推');

      // 2. Traditional Chinese (zh_TW)
      expect(AppStrings.tr('nav_home', langCode: 'zh_TW'), '首頁推薦');
      expect(AppStrings.tr('home_top_pick', langCode: 'zh_TW'), '今日主推');

      // 3. English (en_US)
      expect(AppStrings.tr('nav_home', langCode: 'en_US'), 'Home');
      expect(AppStrings.tr('home_top_pick', langCode: 'en_US'), 'Top Pick');

      // 4. Japanese (ja_JP)
      expect(AppStrings.tr('nav_home', langCode: 'ja_JP'), 'ホーム');
      expect(AppStrings.tr('home_top_pick', langCode: 'ja_JP'), '本日のおすすめ');

      // 5. Korean (ko_KR)
      expect(AppStrings.tr('nav_home', langCode: 'ko_KR'), '홈');
      expect(AppStrings.tr('home_top_pick', langCode: 'ko_KR'), '오늘의 추천');

      // 6. French (fr_FR)
      expect(AppStrings.tr('nav_home', langCode: 'fr_FR'), 'Accueil');
      expect(AppStrings.tr('home_top_pick', langCode: 'fr_FR'), 'À la une');

      // 7. German (de_DE)
      expect(AppStrings.tr('nav_home', langCode: 'de_DE'), 'Startseite');
      expect(AppStrings.tr('home_top_pick', langCode: 'de_DE'),
          'Empfehlung des Tages');

      // 8. Spanish (es_ES)
      expect(AppStrings.tr('nav_home', langCode: 'es_ES'), 'Inicio');
      expect(AppStrings.tr('home_top_pick', langCode: 'es_ES'),
          'Destacado de hoy');

      // 9. Russian (ru_RU)
      expect(AppStrings.tr('nav_home', langCode: 'ru_RU'), 'Главная');
      expect(AppStrings.tr('home_top_pick', langCode: 'ru_RU'), 'Выбор дня');
    });

    test('falls back safely to default language if key missing', () {
      expect(AppStrings.tr('non_existent_key', langCode: 'en_US'),
          'non_existent_key');
    });
  });
}
