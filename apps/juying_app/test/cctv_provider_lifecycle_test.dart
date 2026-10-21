import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/cctv/models/cctv_album.dart';
import 'package:juying/features/cctv/models/cctv_filter.dart';
import 'package:juying/features/cctv/providers/cctv_provider.dart';
import 'package:juying/features/cctv/services/cctv_api_service.dart';

class _DelayedCatalog extends CctvApiService {
  final requests = <Completer<CctvQueryResult>>[];

  @override
  Future<CctvQueryResult> fetchYxgAlbums({
    required String firstCategory,
    String genre = '',
    String area = '',
    String year = '',
    String letter = '',
    String channelId = '',
    int page = 1,
    int pageSize = 24,
  }) {
    final request = Completer<CctvQueryResult>();
    requests.add(request);
    return request.future;
  }
}

final _page = CctvQueryResult(
  total: 48,
  albums: List<CctvAlbum>.generate(
    24,
    (index) => CctvAlbum(
      id: '$index',
      title: '节目 $index',
      posterUrl: '',
      overview: '',
      category: '电视剧',
    ),
  ),
);

void main() {
  for (final fails in <bool>[false, true]) {
    test('disposed catalog ignores late first-page response (fails: $fails)',
        () async {
      final service = _DelayedCatalog();
      final notifier = CctvYxgNotifier(service, const CctvFilterState());
      notifier.dispose();

      if (fails) {
        service.requests.single.completeError(StateError('network failed'));
      } else {
        service.requests.single.complete(_page);
      }
      // The constructor starts the first request without returning its Future.
      await Future<void>.delayed(Duration.zero);
    });

    test('disposed catalog ignores late next-page response (fails: $fails)',
        () async {
      final service = _DelayedCatalog();
      final notifier = CctvYxgNotifier(service, const CctvFilterState());
      service.requests.single.complete(_page);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.albums, hasLength(24));

      final pending = notifier.loadMore();
      notifier.dispose();
      if (fails) {
        service.requests.last.completeError(StateError('network failed'));
      } else {
        service.requests.last.complete(_page);
      }
      await expectLater(pending, completes);
    });
  }
}
