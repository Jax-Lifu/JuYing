package com.flytech.juying.source.iptv

import android.util.Xml
import com.flytech.juying.core.model.EpgProgram
import java.io.FilterInputStream
import java.io.InputStream
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import org.xmlpull.v1.XmlPullParser

/**
 * 针对低内存设备优化的轻量 XMLTV 电子节目单（EPG）流式解析器。
 *
 * **What**: 边读边解目标频道的当前与后续节目，内存中不持有完整 EPG DOM 树。
 *
 * **Why**: 局域网或公网 XMLTV 文件常达数十甚至上百兆，全量反序列化会直接导致 Low-RAM 盒子 OOM；
 * 采用 16MiB 消费上限护栏，关闭 DTD / 外部实体解析防 XXE 注入，按需提取当前及未来 48 小时内的有效节目单。
 */
internal object Xmltv {
    fun parse(input: InputStream, channelId: String, now: Long): List<EpgProgram> {
        val bounded = object : FilterInputStream(input) {
            var count = 0L
            fun consumed(size: Int) { if (size > 0) count += size; require(count <= 16 * 1024 * 1024) { "Guide is too large" } }
            override fun read(): Int = `in`.read().also { consumed(if (it < 0) 0 else 1) }
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int = `in`.read(bytes, offset, length).also(::consumed)
        }
        val parser = Xml.newPullParser().apply {
            setFeature(XmlPullParser.FEATURE_PROCESS_DOCDECL, false)
            setInput(bounded, null)
        }
        val result = mutableListOf<EpgProgram>()
        var selected = false
        var start: Long? = null
        var end: Long? = null
        var titleDepth = -1
        val title = StringBuilder()
        while (parser.nextToken() != XmlPullParser.END_DOCUMENT) {
            when (parser.eventType) {
                XmlPullParser.START_TAG -> when (parser.name) {
                    "programme" -> {
                        start = timestamp(parser.getAttributeValue(null, "start").orEmpty())
                        end = timestamp(parser.getAttributeValue(null, "stop").orEmpty())
                        selected = parser.getAttributeValue(null, "channel") == channelId && start != null && end != null &&
                            end > now && start < now + 48 * 60 * 60_000L && end > start
                        title.clear(); titleDepth = -1
                    }
                    "title" -> if (selected && title.isEmpty()) titleDepth = parser.depth
                }
                XmlPullParser.TEXT, XmlPullParser.CDSECT, XmlPullParser.ENTITY_REF -> if (selected && titleDepth > 0) {
                    // Unknown entities are never expanded; the native parser has DTD processing disabled.
                    val text = parser.text ?: error("Unsupported XML entity")
                    if (title.length < 500) title.append(text.take(500 - title.length))
                }
                XmlPullParser.END_TAG -> {
                    if (parser.depth == titleDepth) titleDepth = -1
                    if (parser.name == "programme") {
                        if (selected && title.isNotBlank() && result.size < 200) result += EpgProgram(channelId, title.toString().trim(), start!!, end!!)
                        selected = false
                    }
                }
            }
        }
        return result.distinct().sortedBy { it.startMs }
    }

    internal fun timestamp(value: String): Long? = runCatching {
        val parts = value.trim().split(Regex("\\s+"))
        val digits = parts.first()
        require(digits.length in listOf(8, 10, 12, 14) && digits.all(Char::isDigit))
        LocalDateTime.parse(digits.padEnd(14, '0'), DateTimeFormatter.ofPattern("uuuuMMddHHmmss").withResolverStyle(java.time.format.ResolverStyle.STRICT))
            .toInstant(ZoneOffset.of(parts.getOrElse(1) { "+0000" })).toEpochMilli()
    }.getOrNull()
}
