import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/models/tvbox_subscription.dart';
import 'package:juying/features/tvbox/providers/tvbox_provider.dart';
import 'package:juying/features/tvbox/services/tvbox_config_service.dart';

void main() {
  const url = 'https://warehouse.example/root.json';
  const oldSites = <TvBoxSite>[
    TvBoxSite(key: 'available', name: 'Old', api: 'https://old.example/api'),
    TvBoxSite(
        key: 'offline', name: 'Cached', api: 'https://offline.example/api'),
  ];

  Future<TvBoxSubscriptionsNotifier> restoredNotifier() async {
    final id = TvBoxSubscription.idForUrl(url);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tvbox_subscriptions_v2': json.encode([
        TvBoxSubscription(
          id: id,
          name: 'Saved subscription',
          url: url,
          sites: oldSites.map((s) => s.copyWith(key: '$id::${s.key}')).toList(),
        ).toJson(),
      ]),
    });
    final notifier = TvBoxSubscriptionsNotifier();
    await pumpEventQueue();
    addTearDown(notifier.dispose);
    return notifier;
  }

  test('partial child refresh preserves missing cached sites and new context',
      () async {
    final notifier = await restoredNotifier();
    final config = await _service({
      '/root.json': {
        'urls': [
          {'url': 'available.json'},
          {'url': 'offline.json'},
        ],
      },
      '/available.json': {
        'sites': [
          {
            'key': 'available',
            'name': 'Updated',
            'api': 'https://new.example/api'
          },
        ],
        'flags': ['vip'],
        'parses': [
          {'name': 'parser', 'type': 1, 'url': './parse?url='},
        ],
      },
    }).loadConfig(url);
    expect(config!.isPartial, isTrue);
    final refreshed = notifier.upsert(
      url: url,
      sites: config.sites,
      preserveMissing: config.isPartial,
    );
    expect(refreshed.sites, hasLength(3));
    final updated = refreshed.sites.firstWhere((s) => s.originId != null);
    expect(updated.name, 'Updated');
    expect(updated.flags, ['vip']);
    expect(
        updated.parses.single['url'], 'https://warehouse.example/parse?url=');
    expect(refreshed.sites.take(2).map((s) => s.name), ['Old', 'Cached']);
    expect(notifier.state.where((s) => !s.isBuiltIn), hasLength(1));
    // Re-applying already namespaced results must not create duplicate identities.
    notifier.upsert(url: url, sites: refreshed.sites, preserveMissing: true);
    await pumpEventQueue();
    final stored = (await SharedPreferences.getInstance())
        .getString('tvbox_subscriptions_v2')!;
    final restored = TvBoxSubscription.fromJson(
        Map<String, dynamic>.from((json.decode(stored) as List).single as Map));
    expect(restored.sites, hasLength(3));
    expect(restored.sites.last.parses, updated.parses);
  });

  test('complete refresh still removes intentionally deleted sites', () async {
    final notifier = await restoredNotifier();
    final config = await _service({
      '/root.json': {
        'sites': [
          {
            'key': 'available',
            'name': 'Updated',
            'api': 'https://new.example/api'
          },
        ],
      },
    }).loadConfig(url);
    expect(config!.isPartial, isFalse);
    final refreshed = notifier.upsert(
      url: url,
      sites: config.sites,
      preserveMissing: config.isPartial,
    );
    expect(refreshed.sites, hasLength(1));
    expect(refreshed.sites.single.name, 'Updated');
    await pumpEventQueue();
  });

  test('nested failed warehouses propagate partial status through the root',
      () async {
    final config = await _service({
      '/root.json': {
        'urls': [
          {'url': 'nested.json'}
        ]
      },
      '/nested.json': {
        'urls': [
          {'url': 'offline.json'}
        ]
      },
    }).loadConfig(url);
    expect(config!.isPartial, isTrue);
    expect(config.sites, isEmpty);
    final notifier = await restoredNotifier();
    final refreshed = notifier.upsert(
      url: url,
      sites: config.sites,
      preserveMissing: config.isPartial,
    );
    expect(refreshed.sites.map((site) => site.name), ['Old', 'Cached']);
    await pumpEventQueue();
  });
}

TvBoxConfigService _service(Map<String, Object> documents) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final document = documents[options.uri.path];
    if (document == null) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      ));
      return;
    }
    handler.resolve(Response<String>(
      requestOptions: options,
      statusCode: 200,
      data: json.encode(document),
    ));
  }));
  return TvBoxConfigService(dio: dio);
}
