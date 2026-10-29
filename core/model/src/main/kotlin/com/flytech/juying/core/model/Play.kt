package com.flytech.juying.core.model

/** 字幕轨模型，包含字幕地址、语言代码与 MIME 类型。 */
data class Subtitle(val url: String, val lang: String? = null, val mimeType: String? = null)

/**
 * 播放器真正消费的标准化播放项。
 *
 * **What**: 封装主播放地址 [url]、请求头 [headers]、外挂字幕 [subtitles] 以及候选备用线路 [backupLines]。
 *
 * **Why**: 无论上游是 CCTV 动态流、IPTV 多线路、TVBox 选集还是 SMB/WebDAV/本地/UPnP 文件，
 * 进入 `PlayerEngine` 前全部收敛为同一结构；主线路失败时可由 `PlayerViewModel` 按 [backupLines] 自动切线。
 */
data class PlayItem(
    val id: String,
    val title: String,
    val url: String,
    val headers: Map<String, String> = emptyMap(),
    val isLive: Boolean = false,
    val subtitles: List<Subtitle> = emptyList(),
    val startPositionMs: Long = 0,
    val backupLines: List<PlayLine> = emptyList(),
    val route: PlaybackRoute = PlaybackRoute.NATIVE,
    /** 首次准备时固定最高分辨率视频轨；用户之后仍可手动选档或恢复自动，音轨不受影响。 */
    val preferHighestVideoQuality: Boolean = false,
)

/** 受保护的官方网页由其网页播放器处理；原生直链继续使用 SurfaceView / Media3。 */
enum class PlaybackRoute { NATIVE, WEB }

enum class PlayKind { LIVE, VOD, FILE }

/**
 * 跨页面跳转播放页时传递的「轻量请求」，只含 id/ref，不含大对象。
 * 由 GetPlayItemUseCase 解析成 PlayItem。
 */
data class PlayRequest(
    val kind: PlayKind,
    val sourceId: String,
    val ref: String,
    val title: String = "",
    val extra: Map<String, String> = emptyMap(),
)

/** 播放历史领域模型，包含数据源、内容引用、进度及续播所需扩展信息。 */
data class HistoryEntry(
    val id: String,
    val kind: PlayKind,
    val sourceId: String,
    val ref: String,
    val title: String,
    val positionMs: Long,
    val durationMs: Long,
    val updatedAt: Long,
    val cover: String? = null,
    /** 恢复选集所需的内容标识；不保存请求头或登录凭据。 */
    val extra: Map<String, String> = emptyMap(),
)

/** 用户收藏领域模型。 */
data class FavoriteEntry(
    val id: String,
    val kind: PlayKind,
    val sourceId: String,
    val ref: String,
    val title: String,
    val cover: String? = null,
    val createdAt: Long = 0L,
)
