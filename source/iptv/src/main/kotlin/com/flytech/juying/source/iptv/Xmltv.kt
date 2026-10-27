package com.flytech.juying.source.iptv

import android.util.Xml
import com.flytech.juying.core.model.EpgProgram
import java.io.FilterInputStream
import java.io.InputStream
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import org.xmlpull.v1.XmlPullParser

/** Reads one channel's current/next programmes without retaining the full guide in memory. */
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
                            end!! > now && start!! < now + 48 * 60 * 60_000L && end!! > start!!
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
