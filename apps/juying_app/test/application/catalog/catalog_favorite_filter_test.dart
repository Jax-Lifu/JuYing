import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/catalog/catalog_favorite_filter.dart';
import 'package:juying/domain/models/unified_media.dart';

void main() {
  final items = [_item('one'), _item('two')];

  test('收藏筛选按来源命名空间条目 ID 过滤展示层', () {
    expect(
      CatalogFavoriteFilter.apply(items, {'live:two'}, enabled: true)
          .map((item) => item.id),
      ['live:two'],
    );
    expect(CatalogFavoriteFilter.apply(items, {'live:two'}, enabled: false),
        items);
  });
}

MediaItem _item(String id) => MediaItem(
      sourceId: 'live',
      sourceItemId: id,
      title: id,
      category: MediaCategory.live,
      officialDetailUri: Uri.parse('https://official.example/$id'),
      defaultEpisodePageUri: Uri.parse('https://official.example/$id'),
    );
