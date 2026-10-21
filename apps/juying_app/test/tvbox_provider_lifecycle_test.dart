import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/models/tvbox_subscription.dart';
import 'package:juying/features/tvbox/providers/tvbox_provider.dart';

const _oldUrl = 'https://old.test/config.json';
const _newUrl = 'https://new.test/config.json';
const _site = TvBoxSite(
  key: 'source',
  name: 'Source',
  type: 1,
  api: 'https://cms.test/api.php/provide/vod/',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void seedSavedSubscription() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tvbox_subscriptions_v2': json.encode(<Object>[
        TvBoxSubscription(
          id: TvBoxSubscription.idForUrl(_oldUrl),
          name: 'Saved',
          url: _oldUrl,
          sites: const <TvBoxSite>[_site],
        ).toJson(),
      ]),
    });
  }

  test('import during startup survives empty preference restoration', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final notifier = TvBoxSubscriptionsNotifier();
    addTearDown(notifier.dispose);
    notifier.upsert(url: _newUrl, sites: const <TvBoxSite>[_site]);

    await pumpEventQueue();

    expect(
        notifier.state.where((item) => !item.isBuiltIn).map((item) => item.url),
        <String>[_newUrl]);
  });

  test('startup import retains other saved subscriptions in memory and storage',
      () async {
    seedSavedSubscription();
    final notifier = TvBoxSubscriptionsNotifier();
    addTearDown(notifier.dispose);
    notifier.upsert(url: _newUrl, sites: const <TvBoxSite>[_site]);

    await pumpEventQueue();

    expect(
        notifier.state.where((item) => !item.isBuiltIn).map((item) => item.url),
        unorderedEquals(<String>[_oldUrl, _newUrl]));
    final preferences = await SharedPreferences.getInstance();
    final saved = json.decode(preferences.getString('tvbox_subscriptions_v2')!)
        as List<dynamic>;
    expect(saved.map((item) => (item as Map)['url']),
        unorderedEquals(<String>[_oldUrl, _newUrl]));
  });

  test('startup removal is not undone by a late preference restoration',
      () async {
    seedSavedSubscription();
    final notifier = TvBoxSubscriptionsNotifier();
    addTearDown(notifier.dispose);
    notifier.remove(TvBoxSubscription.idForUrl(_oldUrl));

    await pumpEventQueue();

    expect(notifier.state.where((item) => !item.isBuiltIn), isEmpty);
  });

  test('startup partial refresh merges with the saved subscription', () async {
    seedSavedSubscription();
    final notifier = TvBoxSubscriptionsNotifier();
    addTearDown(notifier.dispose);
    final added = _site.copyWith(key: 'added', name: 'Added');
    notifier.upsert(
      url: _oldUrl,
      sites: <TvBoxSite>[added],
      preserveMissing: true,
    );

    await pumpEventQueue();

    final imported = notifier.state.singleWhere((item) => !item.isBuiltIn);
    expect(
        imported.sites.map((item) => item.name), <String>['Source', 'Added']);
  });

  test('startup changes retain their order in the final saved snapshot',
      () async {
    seedSavedSubscription();
    final notifier = TvBoxSubscriptionsNotifier();
    addTearDown(notifier.dispose);
    notifier.upsert(url: _newUrl, sites: const <TvBoxSite>[_site]);
    notifier.remove(TvBoxSubscription.idForUrl(_oldUrl));
    notifier.remove(TvBoxSubscription.idForUrl(_newUrl));
    notifier.upsert(
      url: _newUrl,
      sites: const <TvBoxSite>[_site],
      name: 'Last import',
    );

    await pumpEventQueue();

    final imported = notifier.state.singleWhere((item) => !item.isBuiltIn);
    expect(imported.name, 'Last import');
    final preferences = await SharedPreferences.getInstance();
    final saved = json.decode(preferences.getString('tvbox_subscriptions_v2')!)
        as List<dynamic>;
    expect(saved, hasLength(1));
    expect((saved.single as Map)['name'], 'Last import');
  });

  test('disposing before restoration drops pending state changes safely',
      () async {
    seedSavedSubscription();
    final notifier = TvBoxSubscriptionsNotifier();
    notifier.upsert(url: _newUrl, sites: const <TvBoxSite>[_site]);
    notifier.dispose();

    await pumpEventQueue();

    final preferences = await SharedPreferences.getInstance();
    final saved = json.decode(preferences.getString('tvbox_subscriptions_v2')!)
        as List<dynamic>;
    expect(saved.map((item) => (item as Map)['url']), <String>[_oldUrl]);
  });

  test('startup explicit source selection wins over the saved selection',
      () async {
    final other = _site.copyWith(key: 'other', name: 'Other');
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tvbox_active_site_key_v1': _site.key,
    });
    final notifier = ActiveTvBoxSiteNotifier(<TvBoxSite>[_site, other]);
    addTearDown(notifier.dispose);
    notifier.selectSite(other);

    await pumpEventQueue();

    expect(notifier.state.key, other.key);
  });
}
