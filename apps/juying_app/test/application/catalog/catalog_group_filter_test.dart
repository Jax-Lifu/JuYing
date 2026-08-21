import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/catalog/catalog_group_filter.dart';
import 'package:juying/domain/models/unified_media.dart';

void main() {
  final items = [
    _item('cctv-1', '央视'),
    _item('cctv-5', '央视'),
    _item('sat-1', '卫视'),
    _item('other', null),
  ];

  test('目录分组从统一来源标签生成稳定的去重筛选项', () {
    expect(CatalogGroupFilter.groups(items), ['卫视', '央视']);
  });

  test('分组筛选仅过滤展示层，保留条目的来源身份', () {
    final filtered = CatalogGroupFilter.apply(items, '央视');
    expect(filtered.map((item) => item.id), ['live:cctv-1', 'live:cctv-5']);
    expect(CatalogGroupFilter.apply(items, null), items);
  });
}

MediaItem _item(String id, String? group) => MediaItem(
      sourceId: 'live',
      sourceItemId: id,
      title: id,
      category: MediaCategory.live,
      officialDetailUri: Uri.parse('https://official.example/$id'),
      defaultEpisodePageUri: Uri.parse('https://official.example/$id'),
      sourceCategoryLabel: group,
    );
