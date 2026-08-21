import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/catalog/catalog_pagination.dart';

void main() {
  test('策略过滤清空当前页时仍可继续加载来源的后续页', () {
    expect(
      CatalogPagination.hasMore(currentPage: 1, total: 48, pageSize: 24),
      isTrue,
    );
  });

  test('来源末页后停止加载，避免重复请求', () {
    expect(
      CatalogPagination.hasMore(currentPage: 2, total: 48, pageSize: 24),
      isFalse,
    );
  });
}
