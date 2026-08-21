/// 目录分页以来源返回的页码与总数判断，不能以策略过滤后的可见条目数判断。
/// 否则儿童/地区过滤恰好清空当前页时，会错误地停止后续加载。
abstract final class CatalogPagination {
  static bool hasMore({
    required int currentPage,
    required int total,
    required int pageSize,
  }) =>
      currentPage > 0 && total > currentPage * pageSize;
}
