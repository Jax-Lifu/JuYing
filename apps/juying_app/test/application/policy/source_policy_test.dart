import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/policy/source_policy.dart';
import 'package:juying/domain/models/media_source.dart';

void main() {
  const officialSource = MediaSource(
    id: 'official',
    name: '官方来源',
    kind: MediaSourceKind.officialWeb,
    entryUrl: 'https://example.com',
    enabled: true,
    authorization: SourceAuthorization.officialEntryOnly,
    capabilities: {
      SourceCapability.browse,
      SourceCapability.search,
      SourceCapability.officialFallback,
    },
  );

  test('official-entry source only browses after explicit selection', () {
    expect(
      SourcePolicy.evaluate(
        officialSource,
        SourceAction.browse,
        explicitSourceSelection: false,
      ).allowed,
      isFalse,
    );
    expect(
      SourcePolicy.evaluate(
        officialSource,
        SourceAction.browse,
        explicitSourceSelection: true,
      ).allowed,
      isTrue,
    );
  });

  test('official-entry source cannot claim native playback without capability',
      () {
    final decision = SourcePolicy.evaluate(
      officialSource,
      SourceAction.nativePlayback,
      explicitSourceSelection: true,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, '来源未声明该能力');
  });

  test('expired or unavailable source is rejected before any action', () {
    final unavailable = MediaSource(
      id: 'unavailable',
      name: '不可用来源',
      kind: MediaSourceKind.authorizedApi,
      entryUrl: 'https://example.com',
      enabled: true,
      authorization: SourceAuthorization.licensed,
      capabilities: const {SourceCapability.browse},
      health: SourceHealth.unavailable,
    );

    expect(
      SourcePolicy.evaluate(
        unavailable,
        SourceAction.browse,
        explicitSourceSelection: true,
      ).allowed,
      isFalse,
    );
  });
}
