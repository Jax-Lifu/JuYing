package com.flytech.juying.core.model

/**
 * 单条可播放物理线路，携带该线路专属的 HTTP 请求头（如防盗链 Referer / User-Agent / Cookie）。
 */
data class PlayLine(
    val url: String,
    val label: String = "",
    val headers: Map<String, String> = emptyMap(),
)

/**
 * 一个直播频道，可包含多条备用线路（[lines] / [urls]）。
 * `urls` 与 `lines` 均为空时表示需要在起播时由数据源动态鉴权解析（如央视官方源）。
 */
data class Channel(
    val id: String,
    val name: String,
    val logo: String? = null,
    val urls: List<String> = emptyList(),
    val epgId: String? = null,
    val lines: List<PlayLine> = urls.map { PlayLine(url = it) },
)

data class ChannelGroup(val name: String, val channels: List<Channel>)

data class EpgProgram(val channelId: String, val title: String, val startMs: Long, val endMs: Long)
