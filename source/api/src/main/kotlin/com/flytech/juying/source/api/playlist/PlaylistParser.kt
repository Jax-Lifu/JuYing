package com.flytech.juying.source.api.playlist

import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.PlayLine

/**
 * 解析 IPTV 的 m3u / txt(分组,#genre#) 两种常见格式；
 * 同组同名频道自动合并为多线路，并保留 `#EXTVLCOPT` 请求头（User-Agent / Referer）。
 */
object PlaylistParser {

    const val UNGROUPED = "未分组"
    private val ATTR = Regex("""([\w-]+)="([^"]*)"""")
    private val STREAM_URL = Regex("^(https?|rtsp|rtp|udp)://\\S+$", RegexOption.IGNORE_CASE)

    fun parse(text: String): List<ChannelGroup> {
        val clean = text.removePrefix("\uFEFF")
        val lines = clean.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }
        return if (clean.trimStart().startsWith("#EXTM3U")) parseM3u(lines) else parseTxt(lines)
    }

    private class Builder {
        private val groups = LinkedHashMap<String, LinkedHashMap<String, Channel>>()

        fun add(
            group: String,
            name: String,
            url: String,
            logo: String?,
            epgId: String?,
            headers: Map<String, String> = emptyMap(),
        ) {
            if (name.isBlank() || !STREAM_URL.matches(url)) return
            val byName = groups.getOrPut(group) { LinkedHashMap() }
            val newLine = PlayLine(url = url, headers = headers)
            val old = byName[name]
            byName[name] = if (old == null) {
                Channel(
                    id = "$group/$name",
                    name = name,
                    logo = logo,
                    urls = listOf(url),
                    epgId = epgId,
                    lines = listOf(newLine),
                )
            } else {
                val mergedUrls = (old.urls + url).distinct()
                val mergedLines = (old.lines + newLine).distinctBy { it.url }
                old.copy(
                    urls = mergedUrls,
                    logo = old.logo ?: logo,
                    epgId = old.epgId ?: epgId,
                    lines = mergedLines,
                )
            }
        }

        fun build() = groups.map { (g, ch) -> ChannelGroup(g, ch.values.toList()) }
    }

    private fun parseM3u(lines: Sequence<String>): List<ChannelGroup> {
        val b = Builder()
        var name = ""
        var attrs: Map<String, String> = emptyMap()
        var extGroup: String? = null
        val vlcHeaders = LinkedHashMap<String, String>()
        for (line in lines) {
            when {
                line.startsWith("#EXTINF") -> {
                    attrs = ATTR.findAll(line).associate { it.groupValues[1].lowercase() to it.groupValues[2] }
                    name = line.substringAfterLast(',', "").trim().ifEmpty { attrs["tvg-name"].orEmpty() }
                    attrs["http-user-agent"]?.takeIf { it.isNotBlank() }?.let { vlcHeaders["User-Agent"] = it }
                    attrs["http-referrer"]?.takeIf { it.isNotBlank() }?.let { vlcHeaders["Referer"] = it }
                }
                line.startsWith("#EXTGRP:") -> extGroup = line.removePrefix("#EXTGRP:").trim()
                line.startsWith("#EXTVLCOPT:", ignoreCase = true) -> {
                    val opt = line.substringAfter(':')
                    val key = opt.substringBefore('=', "").trim().lowercase()
                    val value = opt.substringAfter('=', "").trim()
                    if (value.isNotEmpty()) {
                        when (key) {
                            "http-user-agent" -> vlcHeaders["User-Agent"] = value
                            "http-referrer", "http-referer" -> vlcHeaders["Referer"] = value
                            "http-origin" -> vlcHeaders["Origin"] = value
                        }
                    }
                }
                line.startsWith("#") -> Unit
                else -> {
                    val group = attrs["group-title"]?.takeIf { it.isNotBlank() } ?: extGroup ?: UNGROUPED
                    b.add(group, name, line, attrs["tvg-logo"], attrs["tvg-id"], vlcHeaders.toMap())
                    name = ""
                    attrs = emptyMap()
                    extGroup = null
                    vlcHeaders.clear()
                }
            }
        }
        return b.build()
    }

    private fun parseTxt(lines: Sequence<String>): List<ChannelGroup> {
        val b = Builder()
        var group = UNGROUPED
        for (line in lines) {
            val idx = line.indexOf(',')
            if (idx <= 0) continue
            val left = line.substring(0, idx).trim()
            val right = line.substring(idx + 1).trim()
            if (right.equals("#genre#", ignoreCase = true)) group = left else b.add(group, left, right, null, null)
        }
        return b.build()
    }
}
