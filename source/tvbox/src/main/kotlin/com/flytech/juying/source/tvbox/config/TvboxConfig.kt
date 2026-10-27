package com.flytech.juying.source.tvbox.config

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl

@Serializable
data class TvboxConfig(
    val spider: String? = null,
    val wallpaper: String? = null,
    val sites: List<TvboxSite> = emptyList(),
    val lives: List<TvboxLive> = emptyList(),
    val parses: List<TvboxParse> = emptyList(),
    val flags: List<String> = emptyList(),
)

/** type: 0=CMS(xml) 1=CMS(json) 3=自定义爬虫(jar/js/py) 4=远程 json。ext 可能是字符串或对象。 */
@Serializable
data class TvboxSite(
    val key: String = "",
    val name: String = "",
    val type: Int = 0,
    val api: String = "",
    val searchable: Int = 1,
    val quickSearch: Int = 1,
    val filterable: Int = 1,
    val ext: JsonElement? = null,
    val jar: String? = null,
    val header: JsonElement? = null,
)

@Serializable
data class TvboxLive(
    val name: String = "",
    val type: Int = 0,
    val url: String = "",
    val epg: String? = null,
    val logo: String? = null,
    val ua: String? = null,
)

@Serializable
data class TvboxParse(
    val name: String = "",
    val type: Int = 0,
    val url: String = "",
    val ext: JsonElement? = null,
)

/** 多仓配置：{"urls":[{"url":"...","name":"..."}]} */
@Serializable
data class TvboxRepoList(val urls: List<TvboxRepoEntry> = emptyList())

@Serializable
data class TvboxRepoEntry(val url: String = "", val name: String = "")

@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
object TvboxConfigParser {

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
        allowTrailingComma = true
        allowComments = true
    }

    /** TVBox 配置常带 BOM 和整行 // 注释，先清洗。 */
    internal fun clean(text: String): String =
        text.removePrefix("\uFEFF")
            .lineSequence()
            .filterNot { it.trimStart().startsWith("//") }
            .joinToString("\n")

    fun parse(text: String): TvboxConfig = json.decodeFromString(clean(TvboxConfigDecoder.decode(text)))

    /** 仅修复 JSON 字符串中的相对地址，保留脚本文本和查询参数内部的 ./ 原义。 */
    internal fun document(text: String, baseUrl: String): JsonObject {
        fun resolve(element: JsonElement): JsonElement = when (element) {
            is JsonObject -> JsonObject(element.mapValues { resolve(it.value) })
            is JsonArray -> JsonArray(element.map(::resolve))
            is JsonPrimitive -> if (element.isString && (element.content.startsWith("./") || element.content.startsWith("../")))
                JsonPrimitive(baseUrl.toHttpUrl().resolve(element.content)?.toString() ?: element.content) else element
        }
        return resolve(json.parseToJsonElement(clean(TvboxConfigDecoder.decode(text)))) as? JsonObject
            ?: error("订阅不是 JSON 对象")
    }

    /** 若是多仓配置返回仓库列表，否则返回 null。 */
    fun parseRepoList(text: String): List<TvboxRepoEntry>? =
        runCatching { json.decodeFromString<TvboxRepoList>(clean(TvboxConfigDecoder.decode(text))).urls }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() }
}
