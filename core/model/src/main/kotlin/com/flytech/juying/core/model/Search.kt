package com.flytech.juying.core.model

/** 搜索单位可以是独立源或复合源中的一个子站；内容仍用 sourceId 和不透明 ref 路由。 */
data class SearchTarget(val sourceId: String, val sourceName: String, val subSource: SubSource? = null) {
    val label: String get() = subSource?.let { "$sourceName · ${it.name}" } ?: sourceName
}

enum class SearchOutcome { SUCCESS, FAILED, TIMED_OUT }

/** 发现与结果逐个发出，流结束表示本页所有任务完成；取消流会取消仍在执行的源请求。 */
sealed interface SearchUpdate {
    /** 跨源搜索发现事件，包含本次发起查询的目标源列表。 */
    data class Discovered(val targets: List<SearchTarget>) : SearchUpdate
    /** 跨源单站搜索完成事件，包含查询状态与命中的点播条目。 */
    data class Finished(
        val target: SearchTarget,
        val outcome: SearchOutcome,
        val items: List<VodItem> = emptyList(),
    ) : SearchUpdate
}
