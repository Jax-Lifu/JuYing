package com.flytech.juying.source.tvbox

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.w3c.dom.Element
import org.xml.sax.InputSource
import java.io.StringReader
import javax.xml.parsers.DocumentBuilderFactory

/** CMS XML 在输入边界转换为共用的 TVBox 响应；禁止 DTD，避免实体展开与外部读取。 */
internal object TvboxXml {
    fun response(text: String): String {
        require(!text.contains("<!DOCTYPE", ignoreCase = true)) { "CMS XML 不允许 DTD" }
        val parser = DocumentBuilderFactory.newInstance().apply { isExpandEntityReferences = false }.newDocumentBuilder()
        parser.setEntityResolver { _, _ -> throw IllegalArgumentException("CMS XML 不允许外部实体") }
        val root = parser.parse(InputSource(StringReader(text))).documentElement
        require(root.tagName == "rss") { "站点返回的内容不是 CMS XML" }
        val classes = root.elements("ty").map { node ->
            JsonObject(mapOf("type_id" to JsonPrimitive(node.getAttribute("id")), "type_name" to JsonPrimitive(node.textContent)))
        }
        val videos = root.elements("video").map { node ->
            val fields = mapOf("id" to "vod_id", "name" to "vod_name", "pic" to "vod_pic",
                "note" to "vod_remarks", "des" to "vod_content", "year" to "vod_year", "area" to "vod_area")
                .map { (from, to) -> to to JsonPrimitive(node.elements(from).firstOrNull()?.textContent.orEmpty()) }.toMap()
            val lines = node.elements("dd")
            JsonObject(fields + mapOf(
                "vod_play_from" to JsonPrimitive(lines.joinToString("$$$") { it.getAttribute("flag") }),
                "vod_play_url" to JsonPrimitive(lines.joinToString("$$$") { it.textContent.trim() }),
            ))
        }
        val pagination = root.elements("list").firstOrNull()?.let { list ->
            listOf("page", "pagecount", "pagesize", "recordcount").mapNotNull { key ->
                val value = list.getAttribute(key).toLongOrNull() ?: return@mapNotNull null
                (when (key) { "pagesize" -> "limit"; "recordcount" -> "total"; else -> key }) to JsonPrimitive(value)
            }.toMap()
        }.orEmpty()
        return JsonObject(mapOf("class" to JsonArray(classes), "list" to JsonArray(videos)) + pagination).toString()
    }

    private fun Element.elements(tag: String): List<Element> = getElementsByTagName(tag).let { nodes ->
        (0 until nodes.length).map { nodes.item(it) as Element }
    }
}
