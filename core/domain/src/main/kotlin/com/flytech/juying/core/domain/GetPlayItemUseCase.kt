package com.flytech.juying.core.domain

import com.flytech.juying.core.data.BrowseRepository
import com.flytech.juying.core.data.HistoryRepository
import com.flytech.juying.core.data.LiveRepository
import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.model.FileEntry
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import javax.inject.Inject

/** 把页面间传递的轻量 PlayRequest 解析成播放器可直接消费的 PlayItem（点播/本地视频自动恢复上次续播进度）。 */
class GetPlayItemUseCase @Inject constructor(
    private val live: LiveRepository,
    private val vod: VodRepository,
    private val browse: BrowseRepository,
    private val history: HistoryRepository,
) {
    suspend operator fun invoke(request: PlayRequest): PlayItem {
        val base = when (request.kind) {
            PlayKind.LIVE -> {
                val channel = live.findChannel(request.sourceId, request.ref)
                    ?: error("找不到频道: ${request.ref}")
                live.resolve(request.sourceId, channel)
            }
            PlayKind.VOD -> vod.resolve(request.sourceId, request.ref)
            PlayKind.FILE -> browse.playItem(
                request.sourceId,
                FileEntry(
                    name = request.title.ifEmpty { request.ref.substringAfterLast('/') },
                    path = request.ref,
                    isDirectory = false,
                    uri = request.extra["uri"],
                ),
            )
        }
        if (base.isLive || base.startPositionMs > 0L) return base
        val saved = history.get("${request.sourceId}:${request.ref}") ?: return base
        // 播放进度超过 5 秒且未接近片尾（<95%）时自动断点续播
        val shouldResume = saved.positionMs > 5_000L &&
            (saved.durationMs <= 0L || saved.positionMs < saved.durationMs * 95 / 100)
        return if (shouldResume) base.copy(startPositionMs = saved.positionMs) else base
    }
}
