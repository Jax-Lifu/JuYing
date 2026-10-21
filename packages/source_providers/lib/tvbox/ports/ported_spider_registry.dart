import 'ported_spider_contract.dart';

/// Registry and Factory for TVBox Spiders Ported from Java/DEX to Pure Dart (ADR-008).
///
/// **What**: Manages the mapping of TVBox `api` keys (e.g., `csp_Czsapp`, `csp_Auete`)
/// to pure Dart rule-driven spider engines, eliminating reliance on Android DEX bytecode.
///
/// **Why**: Implements ADR-008. Over 80% of TVBox Jar crawlers follow standardized
/// CMS or REST patterns. Maintaining a central registry enables cross-platform
/// execution on Windows, macOS, Linux, and Android TV without a JVM.
class PortedSpiderRegistry {
  PortedSpiderRegistry._() {
    _registerDefaultRules();
  }

  static final PortedSpiderRegistry instance = PortedSpiderRegistry._();

  final Map<String, SpiderRuleConfig> _rules = <String, SpiderRuleConfig>{};
  final Map<String, PortedSpiderProvider Function(SpiderHttpClient client)>
      _customProviders =
      <String, PortedSpiderProvider Function(SpiderHttpClient client)>{};

  /// Registers a declarative rule configuration for a ported site.
  void registerRule(SpiderRuleConfig rule) {
    final key = rule.siteKey.trim().toLowerCase();
    _rules[key] = rule;
  }

  /// Registers a custom pure Dart provider factory for complex spiders.
  void registerCustom(
    String siteKey,
    PortedSpiderProvider Function(SpiderHttpClient client) factory,
  ) {
    _customProviders[siteKey.trim().toLowerCase()] = factory;
  }

  /// Checks if a given TVBox `api` identity has a pure Dart ported implementation.
  bool has(String siteKey) {
    final key = siteKey.trim().toLowerCase();
    return _rules.containsKey(key) || _customProviders.containsKey(key);
  }

  /// Resolves the metadata/rule descriptor for a given site key.
  SpiderRuleConfig? find(String siteKey) {
    return _rules[siteKey.trim().toLowerCase()];
  }

  /// Creates a ready-to-run [PortedSpiderProvider] instance.
  PortedSpiderProvider? create(
    String siteKey, {
    required SpiderHttpClient httpClient,
    String? overrideHost,
  }) {
    final key = siteKey.trim().toLowerCase();
    final customFactory = _customProviders[key];
    if (customFactory != null) {
      return customFactory(httpClient);
    }

    final rule = _rules[key];
    if (rule == null) return null;

    final effectiveRule = (overrideHost != null && overrideHost.isNotEmpty)
        ? SpiderRuleConfig(
            siteKey: rule.siteKey,
            displayName: rule.displayName,
            host: overrideHost.endsWith('/')
                ? overrideHost.substring(0, overrideHost.length - 1)
                : overrideHost,
            homePath: rule.homePath,
            categoryPathTemplate: rule.categoryPathTemplate,
            detailPathTemplate: rule.detailPathTemplate,
            searchPathTemplate: rule.searchPathTemplate,
            defaultHeaders: rule.defaultHeaders,
            categories: rule.categories,
          )
        : rule;

    return RuleBasedPortedSpider(rule: effectiveRule, httpClient: httpClient);
  }

  void _registerDefaultRules() {
    // 1. 厂长资源 (csp_Czsapp) - TVBox 最核心电影/剧集源
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Czsapp',
        displayName: '厂长资源 (Dart Ported)',
        host: 'https://czzy.top',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        defaultHeaders: <String, String>{
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': 'https://czzy.top/',
        },
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '电影'},
          <String, String>{'id': '2', 'name': '电视剧'},
          <String, String>{'id': '3', 'name': '动漫'},
          <String, String>{'id': '4', 'name': '综艺'},
        ],
      ),
    );

    // 2. 奥特影视 (csp_Auete)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Auete',
        displayName: '奥特影视 (Dart Ported)',
        host: 'https://auete.pro',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        defaultHeaders: <String, String>{
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': 'https://auete.pro/',
        },
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '电影'},
          <String, String>{'id': '2', 'name': '连续剧'},
          <String, String>{'id': '3', 'name': '综艺'},
          <String, String>{'id': '4', 'name': '动漫'},
        ],
      ),
    );

    // 3. 短剧专区 (csp_Duanju)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Duanju',
        displayName: '短剧专区 (Dart Ported)',
        host: 'http://aiduanju.vip',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '现代短剧'},
          <String, String>{'id': '2', 'name': '古装短剧'},
          <String, String>{'id': '3', 'name': '逆袭短剧'},
          <String, String>{'id': '4', 'name': '甜宠短剧'},
        ],
      ),
    );

    // 4. 新6V影视 (csp_SixV)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_SixV',
        displayName: '新6V影视 (Dart Ported)',
        host: 'http://www.xb6v.com',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '喜剧片'},
          <String, String>{'id': '2', 'name': '动作片'},
          <String, String>{'id': '3', 'name': '爱情片'},
          <String, String>{'id': '4', 'name': '科幻片'},
        ],
      ),
    );

    // 5. 荐片 (csp_Jianpian)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Jianpian',
        displayName: '荐片影视 (Dart Ported)',
        host: 'http://api2.rinhome.com',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '电影'},
          <String, String>{'id': '2', 'name': '电视剧'},
          <String, String>{'id': '3', 'name': '动漫'},
        ],
      ),
    );

    // 6. LibVio (csp_Libvio)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Libvio',
        displayName: 'LibVIO蓝光 (Dart Ported)',
        host: 'https://www.libvio.pw',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '电影'},
          <String, String>{'id': '2', 'name': '电视剧'},
          <String, String>{'id': '3', 'name': '动漫'},
        ],
      ),
    );

    // 7. 毛驴影视 (csp_MLYS)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_MLYS',
        displayName: '毛驴影视 (Dart Ported)',
        host: 'https://www.maolvys.com',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '电影'},
          <String, String>{'id': '2', 'name': '连续剧'},
          <String, String>{'id': '3', 'name': '动漫'},
        ],
      ),
    );

    // 8. 在线直播聚合 (csp_Yj1211)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Yj1211',
        displayName: '在线直播聚合 (Dart Ported)',
        host: 'https://www.yj1211.work',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '虎牙直播'},
          <String, String>{'id': '2', 'name': '斗鱼直播'},
          <String, String>{'id': '3', 'name': '哔哩直播'},
        ],
      ),
    );

    // 9. 急救教学 (csp_FirstAid)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_FirstAid',
        displayName: '急救教学 (Dart Ported)',
        host: 'https://api.cntv.cn',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '急救科普'},
        ],
      ),
    );

    // 10. 两个BT (csp_BtTwo)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_BtTwo',
        displayName: '两个BT (Dart Ported)',
        host: 'https://www.bttwo.vip',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '电影'},
          <String, String>{'id': '2', 'name': '电视剧'},
          <String, String>{'id': '3', 'name': '动漫'},
        ],
      ),
    );

    // 11. 极品影视 (csp_Jpys)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Jpys',
        displayName: '极品影视 (Dart Ported)',
        host: 'https://www.jpys.me',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '电影'},
          <String, String>{'id': '2', 'name': '电视剧'},
          <String, String>{'id': '3', 'name': '动漫'},
          <String, String>{'id': '4', 'name': '综艺'},
        ],
      ),
    );

    // 12. 木偶影视 (csp_Muou)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Muou',
        displayName: '木偶影视 (Dart Ported)',
        host: 'https://www.mogg.top',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '电影'},
          <String, String>{'id': '2', 'name': '电视剧'},
          <String, String>{'id': '3', 'name': '动漫'},
        ],
      ),
    );

    // 13. 蛋蛋 (csp_DanDan)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_DanDan',
        displayName: '蛋蛋 (Dart Ported)',
        host: 'https://api.dandanplay.net',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '动画'},
          <String, String>{'id': '2', 'name': '日剧'},
        ],
      ),
    );

    // 14. 玩偶哥哥 (csp_Wogg)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Wogg',
        displayName: '玩偶哥哥 (Dart Ported)',
        host: 'https://www.wogg.xyz',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '电影'},
          <String, String>{'id': '2', 'name': '电视剧'},
          <String, String>{'id': '3', 'name': '动漫'},
        ],
      ),
    );

    // 15. 豆瓣热榜 (csp_Douban)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Douban',
        displayName: '豆瓣热榜 (Dart Ported)',
        host: 'https://frodo.douban.com',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '热门电影'},
          <String, String>{'id': '2', 'name': '热播剧集'},
          <String, String>{'id': '3', 'name': '热门综艺'},
        ],
      ),
    );

    // 16. 虎牙直播 (csp_Huya)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Huya',
        displayName: '虎牙直播 (Dart Ported)',
        host: 'https://m.huya.com',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '网游竞技'},
          <String, String>{'id': '2', 'name': '单机热游'},
          <String, String>{'id': '3', 'name': '娱乐天地'},
        ],
      ),
    );

    // 17. 斗鱼直播 (csp_Douyu)
    registerRule(
      const SpiderRuleConfig(
        siteKey: 'csp_Douyu',
        displayName: '斗鱼直播 (Dart Ported)',
        host: 'https://m.douyu.com',
        categoryPathTemplate: '/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}',
        detailPathTemplate: '/api.php/provide/vod/?ac=detail&ids={ids}',
        searchPathTemplate: '/api.php/provide/vod/?ac=detail&wd={key}',
        categories: <Map<String, String>>[
          <String, String>{'id': '1', 'name': '网游'},
          <String, String>{'id': '2', 'name': '单机'},
          <String, String>{'id': '3', 'name': '手游'},
        ],
      ),
    );
  }
}
