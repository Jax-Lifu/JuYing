package com.flytech.juying.core.model

/** 点播分类模型，包含分类 ID 与分类名称。 */
data class VodCategory(val id: String, val name: String)

/** hasMore 为 null 表示源未提供分页信息；调用方才使用去重后的增长判断结束。 */
data class VodPage(val items: List<VodItem>, val hasMore: Boolean? = null)

/** 点播影片列表条目，包含唯一标识、所属数据源、片名及封面。 */
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
    val cover: String? = null,
)

/** 点播播放线路分组，包含线路名称与该线路下的分集列表。 */
data class PlayGroup(val name: String, val episodes: List<Episode>)

/** 点播影片详情实体，包含演职员、剧情简介、上映年份及多线路分集。 */
data class VodDetail(
    val item: VodItem,
    val description: String? = null,
    val year: String? = null,
    val area: String? = null,
    val playGroups: List<PlayGroup> = emptyList(),
)
