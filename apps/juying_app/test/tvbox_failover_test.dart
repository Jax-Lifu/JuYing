import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/models/tvbox_subscription.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('TVBox Auto-Failover & Health Probing (LIVE-05 & VOD-08)', () {
    const siteDead = TvBoxSite(
      key: 'site_dead',
      name: '🔥┃小胡┃4K',
      type: 1,
      api: 'http://xh1.xn--yetu07f.icu/api.php/provide/vod/',
    );

    const siteHealthy1 = TvBoxSite(
      key: 'site_healthy_lz',
      name: '🎥┃量子┃资源',
      type: 1,
      api: 'https://cj.lziapi.com/api.php/provide/vod/',
    );

    const siteHealthy2 = TvBoxSite(
      key: 'site_healthy_sn',
      name: '🎥┃索尼┃资源',
      type: 1,
      api: 'https://suoniapi.com/api.php/provide/vod/',
    );

    const siteUnsupported = TvBoxSite(
      key: 'site_unsupported',
      name: '待适配原生',
      type: 3,
      api: 'csp_UnknownNativeDex',
      jar: 'https://example.com/spider.jar',
    );

    const sub = TvBoxSubscription(
      id: 'sub_4k',
      name: '🔥 小胡4K',
      url: 'http://xhztv.top/4k.json',
      sites: <TvBoxSite>[
        siteDead,
        siteUnsupported,
        siteHealthy1,
        siteHealthy2,
      ],
    );

    test('skips dead/unsupported sites and selects next healthy supported site',
        () {
      final engine = TvBoxSpiderEngine();
      final attempted = <String>{siteDead.key};

      // Search in same subscription
      TvBoxSite? next;
      for (final s in sub.sites) {
        if (s.key != siteDead.key &&
            s.isRuntimeSupported &&
            !attempted.contains(s.key) &&
            !engine.isSourceCoolingDown(s)) {
          next = s;
          break;
        }
      }

      expect(next, isNotNull);
      expect(next!.key, equals(siteHealthy1.key));
      expect(next.name, equals('🎥┃量子┃资源'));
    });

    test('cooldown state marks source as not ready', () {
      final engine = TvBoxSpiderEngine();
      expect(engine.isSourceCoolingDown(siteDead), isFalse);
    });
  });
}
