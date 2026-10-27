package com.flytech.juying.source.cctv

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

internal enum class CctvCategory(val label: String, val apiName: String = label) {
    MOVIE("电影"), ANIMATION("少儿动画", "动画片"), DRAMA("经典剧场", "电视剧"),
    DOCUMENTARY("纪录片"), VARIETY("综艺"), SPECIAL("特别节目"), SCIENCE("科教"), OPERA("戏曲"),
}

internal enum class CctvPlayback(val label: String) {
    NATIVE_HD("央视高清（原生播放）"),
    OFFICIAL("央视高清（原生播放）"), // 仅兼容旧历史引用，不再作为独立线路展示。
    STANDARD("官方标清（原生播放）"),
}

/** 专辑 ID 仅用于取分集；VDN 接口只接收视频 GUID，二者不能混用。 */
@Serializable
internal data class CctvEpisodeRef(
    val guid: String,
    val pageUrl: String,
    val title: String,
    val playback: CctvPlayback,
)

internal data class CctvAlbum(
    val id: String,
    val title: String,
    val cover: String?,
    val description: String?,
    val year: String?,
    val area: String?,
    val actors: String,
    val vsetId: String?,
)

internal data class CctvEpisode(
    val guid: String,
    val title: String,
    val pageUrl: String,
    val cover: String?,
    val part: Int?,
    val durationSeconds: Int,
)

internal object CctvJson {
    val format = Json { ignoreUnknownKeys = true }
    private const val MAIN_FEATURE_MIN_SECONDS = 8 * 60
    private val episodeNumber = Regex("第\\s*(\\d+)\\s*集")

    fun data(text: String): JsonObject =
        (format.parseToJsonElement(text) as? JsonObject)?.get("data") as? JsonObject
            ?: error("央视接口返回格式异常")

    fun rows(data: JsonObject): List<JsonObject> =
        (data["list"] as? JsonArray ?: error("央视接口缺少节目列表")).mapNotNull { it as? JsonObject }

    fun albums(data: JsonObject): List<CctvAlbum> = rows(data).mapNotNull { row ->
        val id = row.text("id").ifBlank { row.text("vsetid") }
        if (id.isBlank()) return@mapNotNull null
        CctvAlbum(
            id = id, title = row.text("title").trim().removeSurrounding("《", "》").removeSurrounding("〈", "〉"),
            cover = image(row.text("image2").ifBlank { row.text("image") }.ifBlank { row.text("image3") }),
            description = row.text("brief").ifBlank { null }, year = row.text("year").ifBlank { null },
            area = row.text("area").ifBlank { null }, actors = row.text("actors"),
            vsetId = row.text("vsetid").ifBlank { null },
        )
    }

    fun episodes(data: JsonObject): List<CctvEpisode> = rows(data).mapNotNull { row ->
        val guid = row.text("guid")
        if (guid.isBlank()) return@mapNotNull null
        val title = row.text("title")
        val part = row.number("part")?.takeIf { it > 0 }
            ?: episodeNumber.find(title)?.groupValues?.get(1)?.toIntOrNull()
        val duration = row.text("length").split(':').fold(0) { total, value ->
            total * 60 + (value.toIntOrNull() ?: 0)
        }
        CctvEpisode(guid, title, officialPage(row.text("url")), image(row.text("image")), part, duration)
    }

    fun mainEpisodes(episodes: List<CctvEpisode>): List<CctvEpisode> {
        val unique = episodes.distinctBy { it.guid }
        val numbered = unique.filter { it.part != null }
        if (numbered.isNotEmpty()) return numbered.distinctBy { it.part }.sortedBy { it.part }
        return unique.filter { it.durationSeconds >= MAIN_FEATURE_MIN_SECONDS }.ifEmpty { unique.take(1) }
    }

    fun officialPage(url: String): String {
        val parsed = url.toHttpUrlOrNull() ?: error("央视节目缺少官方播放页面")
        require(parsed.host == "tv.cctv.com") { "央视节目页面域名异常" }
        return parsed.newBuilder().scheme("https").build().toString()
    }

    private fun image(value: String): String? =
        (if (value.startsWith("//")) "https:$value" else value).toHttpUrlOrNull()?.toString()

    fun JsonObject.text(key: String): String = (get(key) as? JsonPrimitive)?.contentOrNull.orEmpty()
    fun JsonObject.number(key: String): Int? = (get(key) as? JsonPrimitive)?.intOrNull
}
