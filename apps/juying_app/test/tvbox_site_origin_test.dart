import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/models/tvbox_subscription.dart';
import 'package:juying/features/tvbox/providers/tvbox_provider.dart';
import 'package:juying/features/tvbox/services/tvbox_config_service.dart';

const _url = 'https://warehouse.example/root.json';

void main() {
  Future<TvBoxSubscriptionsNotifier> notifierWith(List<TvBoxSite> sites) async {
    final id = TvBoxSubscription.idForUrl(_url);
    SharedPreferences.setMockInitialValues({
      'tvbox_subscriptions_v2': json.encode([
        TvBoxSubscription(
          id: id,
          name: 'Saved',
          url: _url,
          sites: sites
              .map((site) => site.copyWith(key: '$id::${site.key}'))
              .toList(),
        ).toJson(),
      ]),
    });
    final notifier = TvBoxSubscriptionsNotifier();
    await pumpEventQueue();
    addTearDown(notifier.dispose);
    return notifier;
  }

  test('identical sites in distinct children retain distinct persisted origins',
      () async {
    final config = await _load([
      'a',
      'b'
    ], {
      'a': _child('Same', 1),
      'b': _child('Same', 1),
    });
    expect(config.sites, hasLength(2));
    final origins = config.sites.map((site) => site.toJson()['originId']);
    expect(origins.every((origin) => origin is String && origin.isNotEmpty),
        isTrue);
    expect(origins.toSet(), hasLength(2));
    for (final site in config.sites) {
      final restored = TvBoxSite.fromJson(site.toJson());
      expect(restored.copyWith(name: 'Renamed').toJson()['originId'],
          site.toJson()['originId']);
      expect(restored.toJson()['originId'], isNot('untrusted-origin'));
    }
  });

  test('partial reordered refresh updates origin and preserves display keys',
      () async {
    final before = await _load([
      'a',
      'b',
      'offline'
    ], {
      'a': _child('A', 1),
      'b': _child('B', 1),
    });
    final notifier = await notifierWith(before.sites);
    final oldKeys = {
      for (final site in notifier.state.last.sites)
        site.toJson()['originId']: site.key,
    };
    final after = await _load([
      'b',
      'a',
      'offline'
    ], {
      'a': _child('A updated', 2),
      'b': _child('B updated', 2),
    });
    expect(after.isPartial, isTrue);
    for (var refresh = 0; refresh < 2; refresh++) {
      final updated = notifier.upsert(
        url: _url,
        sites: after.sites,
        preserveMissing: after.isPartial,
      );
      expect(updated.sites, hasLength(2), reason: 'refresh $refresh');
      expect(updated.sites.map((site) => site.name).toSet(),
          {'A updated', 'B updated'});
      for (final site in updated.sites) {
        expect(site.key, oldKeys[site.toJson()['originId']]);
        expect(site.jar, endsWith('engine-2.jar'));
        expect(site.ext, endsWith('rules-2.json'));
        expect(site.parses.single['url'], endsWith('parse-2?url='));
      }
    }
    await pumpEventQueue();
    final stored = (await SharedPreferences.getInstance())
        .getString('tvbox_subscriptions_v2')!;
    final restored = TvBoxSubscription.fromJson(
        Map<String, dynamic>.from((json.decode(stored) as List).single as Map));
    expect(restored.sites.map((site) => site.toJson()['originId']).toSet(),
        oldKeys.keys.toSet());
  });

  test('failed first child cannot be overwritten by a later child raw key',
      () async {
    final before = await _load([
      'a',
      'b'
    ], {
      'a': _child('A cached', 1),
      'b': _child('B cached', 1),
    });
    final notifier = await notifierWith(before.sites);
    final after = await _load(['a', 'b'], {'b': _child('B updated', 2)});
    final updated = notifier.upsert(
      url: _url,
      sites: after.sites,
      preserveMissing: after.isPartial,
    );
    expect(updated.sites, hasLength(2));
    expect(updated.sites.map((site) => site.name), ['A cached', 'B updated']);
    await pumpEventQueue();
  });

  test('new proven origin gets a stable key when another origin owns raw key',
      () async {
    final before = await _load(['a'], {'a': _child('A cached', 1)});
    final notifier = await notifierWith(before.sites);
    final after = await _load(['a', 'b'], {'b': _child('B new', 1)});
    final first =
        notifier.upsert(url: _url, sites: after.sites, preserveMissing: true);
    expect(first.sites, hasLength(2));
    final keys = first.sites.map((site) => site.key).toList();
    expect(keys.toSet(), hasLength(2));
    final second =
        notifier.upsert(url: _url, sites: after.sites, preserveMissing: true);
    expect(second.sites.map((site) => site.key), keys);
    expect(second.sites.map((site) => site.name), ['A cached', 'B new']);
    await pumpEventQueue();
  });

  test('complete refresh keeps known display key but removes missing origins',
      () async {
    final before = await _load([
      'a',
      'b'
    ], {
      'a': _child('A', 1),
      'b': _child('B', 1),
    });
    final notifier = await notifierWith(before.sites);
    final oldBKey = notifier.state.last.sites.last.key;
    final after = await _load(['b'], {'b': _child('B updated', 2)});
    final updated = notifier.upsert(url: _url, sites: after.sites);
    expect(updated.sites, hasLength(1));
    expect(updated.sites.single.key, oldBKey);
    await pumpEventQueue();
  });

  test(
      'partial legacy refresh preserves unknown origins without fuzzy migration',
      () async {
    final notifier = await notifierWith(const [
      TvBoxSite(key: 'shared', name: 'Old base', api: 'csp_Test'),
      TvBoxSite(key: 'shared_oldhash', name: 'New A', api: 'csp_Test'),
    ]);
    final after = await _load(['a'], {'a': _child('New A', 2)});
    for (var refresh = 0; refresh < 2; refresh++) {
      final updated =
          notifier.upsert(url: _url, sites: after.sites, preserveMissing: true);
      expect(updated.sites, hasLength(3));
      expect(updated.sites.first.name, 'Old base');
      expect(updated.sites.first.toJson()['originId'], isNull);
      expect(updated.sites[1].key, endsWith('::shared_oldhash'));
      expect(updated.sites[1].toJson()['originId'], isNull);
      expect(updated.sites.last.toJson()['originId'], isNotNull);
    }
    await pumpEventQueue();
  });

  test(
      'offline legacy first child survives partial refresh until complete load',
      () async {
    final notifier = await notifierWith(const [
      TvBoxSite(key: 'shared', name: 'A offline', api: 'csp_A'),
      TvBoxSite(key: 'shared_legacyhash', name: 'B cached', api: 'csp_Test'),
    ]);
    final after = await _load(['a', 'b'], {'b': _child('B updated', 2)});
    expect(after.isPartial, isTrue);
    List<String>? keys;
    for (var refresh = 0; refresh < 2; refresh++) {
      final updated = notifier.upsert(
          url: _url, sites: after.sites, preserveMissing: after.isPartial);
      expect(updated.sites.map((site) => site.name),
          ['A offline', 'B cached', 'B updated']);
      expect(updated.sites.first.api, 'csp_A');
      keys ??= updated.sites.map((site) => site.key).toList();
      expect(updated.sites.map((site) => site.key), keys);
    }
    final complete = notifier.upsert(url: _url, sites: after.sites);
    expect(complete.sites, hasLength(1));
    expect(complete.sites.single.name, 'B updated');
    expect(complete.sites.single.key, keys!.last);
    await pumpEventQueue();
  });
}

Map<String, Object> _child(String name, int version) => {
      'spider': './engine-$version.jar',
      'sites': [
        {
          'key': 'shared',
          'name': name,
          'api': 'csp_Test',
          'ext': './rules-$version.json',
          'originId': 'untrusted-origin',
        }
      ],
      'parses': [
        {'name': 'Parser', 'type': 1, 'url': './parse-$version?url='}
      ],
      'flags': ['flag-$version'],
    };

Future<TvBoxConfig> _load(
    List<String> children, Map<String, Object> documents) async {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final document = options.uri.path == '/root.json'
        ? {
            'urls': [
              for (final child in children) {'url': '$child.json'}
            ]
          }
        : documents[options.uri.path.substring(1).replaceAll('.json', '')];
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
  return (await TvBoxConfigService(dio: dio).loadConfig(_url))!;
}
