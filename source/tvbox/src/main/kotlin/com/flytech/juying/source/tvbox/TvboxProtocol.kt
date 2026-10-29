package com.flytech.juying.source.tvbox

import com.flytech.juying.core.model.Episode
import com.flytech.juying.core.model.PlayGroup
import com.flytech.juying.core.model.VodCategory
import com.flytech.juying.core.model.VodDetail
import com.flytech.juying.core.model.VodItem
import com.flytech.juying.source.tvbox.config.TvboxSite
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** TVBox 的整数编码只在配置边界转换，业务层使用明确的运行时类型。 */
internal enum class TvboxSiteType(val code: Int) {
    CMS_XML(0), CMS_JSON(1), SPIDER(3), HTTP_SPIDER(4);

    companion object {
        fun fromCode(code: Int): TvboxSiteType = entries.firstOrNull { it.code == code }
            ?: throw UnsupportedOperationException("未知的 TVBox 站点类型")
    }
}

internal enum class SpiderLanguage { JAR, JAVASCRIPT, PYTHON }

internal fun TvboxSite.spiderLanguage(): SpiderLanguage = when {
    api.startsWith(JAR_API_PREFIX) -> SpiderLanguage.JAR
    api.substringBefore('?').substringBefore('#').endsWith(".js", ignoreCase = true) -> SpiderLanguage.JAVASCRIPT
    api.substringBefore('?').substringBefore('#').endsWith(".py", ignoreCase = true) -> SpiderLanguage.PYTHON
    else -> throw UnsupportedOperationException("无法识别 Spider 脚本类型")
}

internal const val JAR_API_PREFIX = "csp_"

/** 引用只保存稳定路由；播放 URL 与 Cookie 不写入历史记录。 */
@Serializable
internal data class TvboxItemRef(val siteKey: String, val id: String) {
    init { require(siteKey.isNotBlank() && id.isNotBlank()) { "无效的 TVBox 内容引用" } }
    fun encode(): String = Json.encodeToString(this)

    companion object {
        fun decode(value: String): TvboxItemRef = Json.decodeFromString(value)
    }
}

/** TVBox 分集引用模型，用于在不同子站点与线路间精确定位。 */
@Serializable
internal data class TvboxEpisodeRef(
    val item: TvboxItemRef,
    val groupName: String,
    val episodeName: String,
    val episodeIndex: Int,
) {
    init { require(episodeIndex >= 0) { "无效的 TVBox 分集引用" } }
    fun encode(): String = Json.encodeToString(this)

    companion object {
        fun decode(value: String): TvboxEpisodeRef = Json.decodeFromString(value)
    }
}

/** TVBox 分集模型，包含集名与直接播放/嗅探地址。 */
internal data class TvboxEpisode(val name: String, val playId: String)
/** TVBox 播放线路分组，包含线路名称与分集列表。 */
internal data class TvboxPlayGroup(val name: String, val episodes: List<TvboxEpisode>)
/** TVBox 影片基础实体。 */
internal data class TvboxVideo(
    val id: String,
    val title: String,
    val cover: String?,
    val remarks: String?,
    val description: String?,
    val year: String?,
    val area: String?,
    val groups: List<TvboxPlayGroup>,
) {
    fun item(sourceId: String, siteKey: String) = VodItem(
        id = TvboxItemRef(siteKey, id).encode(), sourceId = sourceId,
        title = title, cover = cover, remarks = remarks,
    )

    fun detail(sourceId: String, siteKey: String) = VodDetail(
        item = item(sourceId, siteKey), description = description, year = year, area = area,
        playGroups = groups.map { group ->
            PlayGroup(group.name, group.episodes.mapIndexed { index, episode ->
                Episode(episode.name, TvboxEpisodeRef(
                    TvboxItemRef(siteKey, id), group.name, episode.name, index,
                ).encode(), cover = cover)
            })
        },
    )
}

/** CMS JSON 与三种 Spider 共用同一响应协议，外部字段只在此处解析。 */
internal object TvboxJson {
    private const val GROUP_SEPARATOR = "$$$"
    private const val EPISODE_SEPARATOR = '#'
    private const val TITLE_SEPARATOR = '$'
    private val json = Json { ignoreUnknownKeys = true }

    fun response(text: String): JsonObject =
        json.parseToJsonElement(text.removePrefix("\uFEFF")) as? JsonObject
            ?: throw IllegalArgumentException("站点返回的内容不是 JSON 对象")

    fun categories(text: String, siteKey: String): List<VodCategory> =
        response(text).objects("class").mapNotNull { row ->
            val id = row.text("type_id") ?: return@mapNotNull null
            val name = row.text("type_name") ?: return@mapNotNull null
            VodCategory(TvboxItemRef(siteKey, id).encode(), name)
        }.distinctBy { it.id }

    fun hasMore(text: String, requestedPage: Int): Boolean? = hasMore(response(text), requestedPage)

    fun hasMore(root: JsonObject, requestedPage: Int): Boolean? {
        val pages = root.text("pagecount")?.toLongOrNull()?.takeIf { it > 0 }
        if (pages != null) return requestedPage < pages
        val total = root.text("total")?.toLongOrNull()?.takeIf { it >= 0 } ?: return null
        val limit = root.text("limit")?.toLongOrNull()?.takeIf { it > 0 } ?: return null
        return requestedPage.toLong() <= (total - 1) / limit && total > 0
    }

    fun videos(text: String): List<TvboxVideo> = videos(response(text))

    fun videos(root: JsonObject): List<TvboxVideo> = root.objects("list").mapNotNull { row ->
        val id = row.text("vod_id") ?: return@mapNotNull null
        val title = row.text("vod_name") ?: return@mapNotNull null
        TvboxVideo(
            id = id, title = title, cover = row.text("vod_pic"), remarks = row.text("vod_remarks"),
            description = row.text("vod_content"), year = row.text("vod_year"), area = row.text("vod_area"),
            groups = playGroups(row.text("vod_play_from").orEmpty(), row.text("vod_play_url").orEmpty()),
        )
    }.distinctBy { it.id }

    private fun playGroups(names: String, urls: String): List<TvboxPlayGroup> {
        if (urls.isBlank()) return emptyList()
        val labels = names.split(GROUP_SEPARATOR)
        return urls.split(GROUP_SEPARATOR).mapIndexedNotNull { index, group ->
            val episodes = group.split(EPISODE_SEPARATOR).mapIndexedNotNull { episodeIndex, value ->
                val split = value.indexOf(TITLE_SEPARATOR)
                val name = if (split >= 0) value.substring(0, split).trim() else "第 ${episodeIndex + 1} 集"
                val playId = (if (split >= 0) value.substring(split + 1) else value).trim()
                if (playId.isBlank()) null else TvboxEpisode(name.ifBlank { "第 ${episodeIndex + 1} 集" }, playId)
            }
            if (episodes.isEmpty()) null else TvboxPlayGroup(
                labels.getOrNull(index)?.takeIf { it.isNotBlank() } ?: "线路 ${index + 1}", episodes,
            )
        }
    }

    fun headers(value: JsonElement?): Map<String, String> {
        val obj = when (value) {
            null, JsonNull -> return emptyMap()
            is JsonObject -> value
            is JsonPrimitive -> response(value.content)
            else -> throw IllegalArgumentException("站点请求头格式错误")
        }
        return obj.mapValues { (_, v) ->
            (v as? JsonPrimitive)?.contentOrNull ?: throw IllegalArgumentException("站点请求头值格式错误")
        }.also { headers ->
            // 防止脚本把换行混入 HTTP 请求头；OkHttp 还会进行最终协议校验。
            require(headers.all { (key, value) ->
                key.isNotBlank() && key.none { it == '\r' || it == '\n' } && value.none { it == '\r' || it == '\n' }
            }) { "站点请求头含非法字符" }
        }
    }

    fun httpUrl(value: String, baseUrl: String? = null): String =
        (value.toHttpUrlOrNull() ?: baseUrl?.toHttpUrlOrNull()?.resolve(value))?.toString()
            ?: throw IllegalArgumentException("站点地址必须是 HTTP 或 HTTPS")

    fun JsonObject.text(key: String): String? =
        (get(key) as? JsonPrimitive)?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }

    private fun JsonObject.objects(key: String): List<JsonObject> = when (val value = get(key)) {
        null, JsonNull -> emptyList()
        is JsonArray -> value.mapNotNull { it as? JsonObject }
        else -> throw IllegalArgumentException("站点列表格式错误")
    }
}
