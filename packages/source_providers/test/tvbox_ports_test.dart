import 'package:test/test.dart';
import 'package:juying_source_providers/juying_source_providers.dart';

void main() {
  group('TVBox Jar-to-Dart Ported Spider Engine (VOD-07 & ADR-008)', () {
    final rule = SpiderRuleConfig(
      siteKey: 'csp_TestSpider',
      displayName: '测试影视源 (Dart Ported)',
      host: 'https://test-vod.example.com',
      homePath: '/api/featured',
      categoryPathTemplate: '/api/category?t={tid}&p={pg}',
      detailPathTemplate: '/api/detail?id={ids}',
      searchPathTemplate: '/api/search?k={key}',
      categories: const [
        {'id': '1', 'name': '电影'},
        {'id': '2', 'name': '电视剧'},
      ],
      defaultHeaders: const {'User-Agent': 'JuYing-Player/1.0'},
    );

    test('homeContent correctly formats category classes and home list',
        () async {
      final spider = RuleBasedPortedSpider(
        rule: rule,
        httpClient: (url, {headers}) async {
          expect(url, equals('https://test-vod.example.com/api/featured'));
          expect(headers?['User-Agent'], equals('JuYing-Player/1.0'));
          return '{"code": 1, "list": [{"vod_id": "100", "vod_name": "流浪地球2"}]}';
        },
      );

      final res = await spider.homeContent();
      expect(res['class'], hasLength(2));
      expect(res['class'][0]['type_name'], equals('电影'));
      expect(res['list'], hasLength(1));
      expect(res['list'][0]['vod_name'], equals('流浪地球2'));
    });

    test('categoryContent fetches paginated catalog items', () async {
      final spider = RuleBasedPortedSpider(
        rule: rule,
        httpClient: (url, {headers}) async {
          expect(
            url,
            equals('https://test-vod.example.com/api/category?t=1&p=2'),
          );
          return '{"code": 1, "list": [{"vod_id": "101", "vod_name": "星际穿越"}]}';
        },
      );

      final res = await spider.categoryContent('1', '2');
      expect(res['page'], equals(2));
      expect(res['list'], hasLength(1));
      expect(res['list'][0]['vod_name'], equals('星际穿越'));
    });

    test('detailContent parses media metadata and playlist sources', () async {
      final spider = RuleBasedPortedSpider(
        rule: rule,
        httpClient: (url, {headers}) async {
          expect(
            url,
            equals('https://test-vod.example.com/api/detail?id=100%2C101'),
          );
          return r'{"list": [{"vod_id": "100", "vod_name": "流浪地球2", "vod_play_from": "官方4K", "vod_play_url": "正片$https://example.com/live.m3u8"}]}';
        },
      );

      final res = await spider.detailContent(['100', '101']);
      expect(res['list'], hasLength(1));
      expect(res['list'][0]['vod_play_from'], equals('官方4K'));
    });

    test('searchContent queries target server with keyword', () async {
      final spider = RuleBasedPortedSpider(
        rule: rule,
        httpClient: (url, {headers}) async {
          expect(
            url,
            equals(
                'https://test-vod.example.com/api/search?k=%E4%B8%89%E4%BD%93'),
          );
          return '{"list": [{"vod_id": "200", "vod_name": "三体"}]}';
        },
      );

      final res = await spider.searchContent('三体');
      expect(res['list'], hasLength(1));
      expect(res['list'][0]['vod_name'], equals('三体'));
    });

    test('playerContent returns direct play URL and required headers',
        () async {
      final spider = RuleBasedPortedSpider(
        rule: rule,
        httpClient: (url, {headers}) async => '',
      );

      final res = await spider.playerContent(
          '官方4K', 'https://video.example.com/play.mp4');
      expect(res['parse'], equals(0));
      expect(res['url'], equals('https://video.example.com/play.mp4'));
      expect(res['header']['User-Agent'], equals('JuYing-Player/1.0'));
    });
  });
}
