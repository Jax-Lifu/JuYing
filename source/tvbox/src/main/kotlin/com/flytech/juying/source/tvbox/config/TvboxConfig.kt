package com.flytech.juying.source.tvbox.config

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl

/** TVBox 订阅配置文件领域模型，包含站点、直播、解析器等。 */
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

/** TVBox 配置中声明的直播源定义。 */
@Serializable
data class TvboxLive(
    val name: String = "",
    val type: Int = 0,
    val url: String = "",
    val epg: String? = null,
    val logo: String? = null,
    val ua: String? = null,
)

/** TVBox 配置中声明的嗅探/JSON 播放解析器定义。 */
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

/** TVBox 多仓仓库子项配置定义。 */
@Serializable
data class TvboxRepoEntry(val url: String = "", val name: String = "")

/** TVBox 配置解码与解析器（支持 Base64、2423 CBC 及相对路径）。 */
@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
object TvboxConfigParser {

    internal const val MAX_NESTING_DEPTH = 64

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

    private fun decoded(text: String): String = clean(TvboxConfigDecoder.decode(text)).also(::checkNesting)

    // 在 JSON 解码与相对地址递归前拒绝深层输入，字符串和注释不参与结构计数。
    private fun checkNesting(value: String) {
        var depth = 0
        var quoted = false
        var index = 0
        while (index < value.length) {
            val char = value[index]
            when {
                quoted && char == '\\' -> index++
                char == '"' -> quoted = !quoted
                quoted -> Unit
                char == '/' && value.getOrNull(index + 1) == '/' -> {
                    index = value.indexOf('\n', index + 2).takeIf { it >= 0 } ?: value.length
                }
                char == '/' && value.getOrNull(index + 1) == '*' -> {
                    index = value.indexOf("*/", index + 2).takeIf { it >= 0 }?.plus(1) ?: value.length
                }
                char == '{' || char == '[' -> {
                    depth++
                    require(depth <= MAX_NESTING_DEPTH) { "TVBox 配置嵌套超过 $MAX_NESTING_DEPTH 层" }
                }
                char == '}' || char == ']' -> depth--
            }
            index++
        }
    }

    fun parse(text: String): TvboxConfig = json.decodeFromString(decoded(text))

    /** 仅修复 JSON 字符串中的相对地址，保留脚本文本和查询参数内部的 ./ 原义。 */
    internal fun document(text: String, baseUrl: String): JsonObject {
        fun resolve(element: JsonElement): JsonElement = when (element) {
            is JsonObject -> JsonObject(element.mapValues { resolve(it.value) })
            is JsonArray -> JsonArray(element.map(::resolve))
            is JsonPrimitive -> if (element.isString && (element.content.startsWith("./") || element.content.startsWith("../")))
                JsonPrimitive(baseUrl.toHttpUrl().resolve(element.content)?.toString() ?: element.content) else element
        }
        return resolve(json.parseToJsonElement(decoded(text))) as? JsonObject
            ?: error("订阅不是 JSON 对象")
    }

    /** 若是多仓配置返回仓库列表，否则返回 null。 */
    fun parseRepoList(text: String): List<TvboxRepoEntry>? {
        val value = runCatching { clean(TvboxConfigDecoder.decode(text)) }.getOrNull() ?: return null
        checkNesting(value)
        return runCatching { json.decodeFromString<TvboxRepoList>(value).urls }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() }
    }
}
