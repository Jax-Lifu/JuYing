import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/core/network/network_request_policy.dart';
import 'package:juying/infrastructure/cctv/cctv_models.dart';
import 'package:juying/infrastructure/cctv/cctv_repository.dart';

void main() {
  test('animation catalog uses the official animation channel and label',
      () async {
    Uri? requested;
    final repository = CctvRepository(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
            jsonEncode({
              'data': {'total': 0, 'list': []},
            }),
            200);
      }),
    );

    await repository.fetchPrograms(
      category: CctvCatalogCategory.animation,
      page: 2,
    );

    expect(requested?.host, 'api.cntv.cn');
    expect(requested?.queryParameters['channelid'], 'CHAL1460955899450127');
    expect(requested?.queryParameters['fc'], '动画片');
    expect(requested?.queryParameters['p'], '2');
  });

  test('search calls the public CCTV search endpoint', () async {
    Uri? requested;
    final repository = CctvRepository(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode({'list': []}), 200);
      }),
    );

    await repository.searchPrograms('熊出没');

    expect(requested?.host, 'search.cctv.com');
    expect(requested?.path, '/ifsearch.php');
    expect(requested?.queryParameters['qtext'], '熊出没');
  });

  test('falls back to the album entry when no episode list is published',
      () async {
    final program = CctvProgram(
      id: 'album-1',
      title: '测试节目',
      officialPageUrl: Uri.parse('https://tv.cctv.com/album.shtml'),
      episodePageUrl: Uri.parse('https://tv.cctv.com/episode.shtml'),
      category: CctvCatalogCategory.animation,
    );
    final repository = CctvRepository(
      client: MockClient((_) async => http.Response('<html></html>', 200)),
    );

    final episodes = await repository.fetchEpisodes(program);

    expect(episodes, hasLength(1));
    expect(episodes.single.officialPageUrl.path, '/episode.shtml');
  });

  test('临时来源故障会在有限次数内退避重试，随后保留成功响应', () async {
    var requests = 0;
    final waits = <Duration>[];
    final repository = CctvRepository(
      networkPolicy: const NetworkRequestPolicy(
        maxAttempts: 2,
        retryBaseDelay: Duration(milliseconds: 1),
      ),
      wait: (delay) async => waits.add(delay),
      client: MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('busy', 503)
            : http.Response(
                jsonEncode({
                  'data': {'total': 0, 'list': []}
                }),
                200);
      }),
    );

    await repository.fetchPrograms();

    expect(requests, 2);
    expect(waits, [const Duration(milliseconds: 1)]);
  });

  test('来源明确拒绝的请求不会被无意义重试', () async {
    var requests = 0;
    final repository = CctvRepository(
      networkPolicy: const NetworkRequestPolicy(maxAttempts: 3),
      wait: (_) async {},
      client: MockClient((_) async {
        requests++;
        return http.Response('missing', 404);
      }),
    );

    await expectLater(repository.fetchPrograms(), throwsA(isA<Exception>()));
    expect(requests, 1);
  });
}
