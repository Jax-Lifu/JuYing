package com.flytech.juying.core.model

data class VodCategory(val id: String, val name: String)

/** hasMore 为 null 表示源未提供分页信息；调用方才使用去重后的增长判断结束。 */
data class VodPage(val items: List<VodItem>, val hasMore: Boolean? = null)

data class VodItem(
    val id: String,
    val sourceId: String,
    val title: String,
    val cover: String? = null,
    val remarks: String? = null,
)

/** ref 由数据源自行定义，resolve 时原样交还给数据源。 */
data class Episode(
    val name: String,
    val ref: String,
    /** 旧播放引用仅用于恢复历史选集；发起新的播放请求始终使用 ref。 */
    val legacyRefs: List<String> = emptyList(),
)

data class PlayGroup(val name: String, val episodes: List<Episode>)

data class VodDetail(
    val item: VodItem,
    val description: String? = null,
    val year: String? = null,
    val area: String? = null,
    val playGroups: List<PlayGroup> = emptyList(),
)
