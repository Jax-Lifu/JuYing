package com.flytech.juying.player.api

import android.view.SurfaceView
import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.PlayItem
import kotlinx.coroutines.flow.StateFlow

/** 播放内核底层状态模型，包含缓冲、宽高、播放中与错误状态。 */
data class PlayerState(
    val isPlaying: Boolean = false,
    val isBuffering: Boolean = false,
    val ended: Boolean = false,
    val videoWidth: Int = 0,
    val videoHeight: Int = 0,
    val error: String? = null,
)

/** Track IDs belong to the current item. VIDEO lists only decodable formats offered by the source. */
data class PlayerTrack(val id: String, val label: String, val selected: Boolean)

enum class PlayerTrackType { VIDEO, AUDIO, SUBTITLE }

/**
 * 播放内核抽象。UI 与业务只依赖这个接口，Media3 / IJK / mpv 等内核可互换。
 * 进度（position/duration）不放进 StateFlow，由 UI 在控制条可见时低频轮询，省 CPU。
 */
interface PlayerEngine {
    val state: StateFlow<PlayerState>

    /** 视频输出使用 SurfaceView（HDR / 杜比视界在多数设备上需要它）。 */
    fun setSurfaceView(view: SurfaceView?)
    /** Binds a lightweight native subtitle overlay; null detaches it when the activity stops. */
    fun setSubtitleContainer(container: android.view.ViewGroup?) {}
    fun prepare(item: PlayItem)
    fun play()
    fun pause()
    fun seekTo(positionMs: Long)
    fun seekBy(deltaMs: Long)
    fun positionMs(): Long
    fun durationMs(): Long
    fun tracks(type: PlayerTrackType): List<PlayerTrack> = emptyList()
    /** Null disables subtitles or restores automatic video/audio selection. */
    fun selectTrack(type: PlayerTrackType, id: String?) {}
    fun playbackSpeed(): Float = 1f
    fun setPlaybackSpeed(speed: Float) {}
    fun release()
}

fun interface PlayerEngineFactory {
    fun create(settings: AppSettings): PlayerEngine
}
