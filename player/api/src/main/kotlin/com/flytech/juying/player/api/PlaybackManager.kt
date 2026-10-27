package com.flytech.juying.player.api

import com.flytech.juying.core.datastore.SettingsDataSource
import kotlinx.coroutines.flow.first
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 应用级播放器持有者：全局最多一个引擎；退出播放页时 release 立即释放解码器和缓冲，
 * 这是低内存设备上最重要的一条。后台音频/投屏接入时在这里扩展。
 */
@Singleton
class PlaybackManager @Inject constructor(
    private val factory: PlayerEngineFactory,
    private val settings: SettingsDataSource,
) {
    private var engine: PlayerEngine? = null

    suspend fun acquire(): PlayerEngine {
        synchronized(this) { engine }?.let { return it }
        val s = settings.settings.first()
        return synchronized(this) {
            engine ?: factory.create(s).also {
                engine = it
                Timber.d("PlaybackManager acquired new PlayerEngine: decoder=%s", s.decoderMode)
            }
        }
    }

    fun current(): PlayerEngine? = synchronized(this) { engine }

    /**
     * 释放播放器引擎。
     * @param owner 若传入非空引用，仅当当前全局引擎与 owner 为同一实例时才执行释放，
     *              防止旧播放页 onCleared 竞态误杀新播放页刚创建的解码器。
     */
    fun release(owner: PlayerEngine? = null) {
        val e = synchronized(this) {
            val cur = engine ?: return
            if (owner != null && cur !== owner) {
                Timber.d("Skip release: current engine differs from owner")
                return
            }
            engine = null
            cur
        }
        Timber.d("PlaybackManager releasing PlayerEngine")
        e.release()
    }
}
