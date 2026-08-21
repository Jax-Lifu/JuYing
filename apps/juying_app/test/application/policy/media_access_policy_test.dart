import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/policy/media_access_policy.dart';
import 'package:juying/application/policy/source_policy.dart';
import 'package:juying/domain/models/media_source.dart';
import 'package:juying/domain/models/unified_media.dart';

void main() {
  final source = MediaSource(
    id: 'licensed-cn',
    name: '授权来源',
    kind: MediaSourceKind.authorizedApi,
    entryUrl: 'https://licensed.example.com',
    enabled: true,
    authorization: SourceAuthorization.licensed,
    capabilities: const {SourceCapability.search},
    regionCode: 'CN',
  );

  test('地区限制在来源查询前被拒绝，不能依赖页面自行判断', () {
    expect(
      MediaAccessPolicy.evaluateSource(
        source,
        SourceAction.search,
        context: const MediaAccessContext(regionCode: 'US'),
        explicitSourceSelection: true,
      ).allowed,
      isFalse,
    );
  });

  test('儿童规则在结果聚合前拒绝不安全分类', () {
    final item = MediaItem(
      sourceId: source.id,
      sourceItemId: 'movie-1',
      title: '电影',
      category: MediaCategory.movie,
      officialDetailUri: Uri.parse('https://licensed.example.com/detail'),
      defaultEpisodePageUri: Uri.parse('https://licensed.example.com/episode'),
    );
    expect(
      MediaAccessPolicy.evaluateItem(
        source,
        item,
        SourceAction.search,
        context: const MediaAccessContext(
          isChildProfile: true,
          regionCode: 'CN',
        ),
        explicitSourceSelection: true,
      ).reason,
      '当前儿童档案不可访问该内容',
    );
  });
}
