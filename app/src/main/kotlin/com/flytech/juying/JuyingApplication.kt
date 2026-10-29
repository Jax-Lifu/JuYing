package com.flytech.juying

import android.app.Application
import android.content.pm.ApplicationInfo
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.memory.MemoryCache
import com.flytech.juying.core.model.DeviceProfile
import com.flytech.juying.core.model.PerformanceTier
import dagger.Lazy
import dagger.hilt.android.HiltAndroidApp
import okhttp3.OkHttpClient
import timber.log.Timber
import javax.inject.Inject

/** 聚映全局 Application 宿主，按需懒加载并初始化轻量基础组件。 */
@HiltAndroidApp
class JuyingApplication : Application(), ImageLoaderFactory {

    // 使用 dagger.Lazy 确保 Application.onCreate 零阻塞，仅在首次加载图片时才按需初始化 OkHttp 与 ImageLoader。
    @Inject lateinit var okHttpClient: Lazy<OkHttpClient>
    @Inject lateinit var deviceProfile: Lazy<DeviceProfile>

    override fun onCreate() {
        super.onCreate()
        // 冷启动原则：这里只做零 I/O 的 Timber 日志树挂载；数据库、OkHttp、爬虫与播放器全部懒加载。
        val isDebug = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (isDebug) {
            Timber.plant(Timber.DebugTree())
        }
    }

    override fun newImageLoader(): ImageLoader {
        val profile = deviceProfile.get()
        val memPercent = when (profile.tier) {
            PerformanceTier.LOW -> 0.08
            PerformanceTier.MID -> 0.15
            PerformanceTier.HIGH -> 0.20
        }
        Timber.d("Initializing Coil ImageLoader for tier=%s (memPercent=%.2f)", profile.tier, memPercent)
        return ImageLoader.Builder(this)
            .okHttpClient { okHttpClient.get() }
            // 局域网和本机封面不依赖外网能力，由实际 HTTP 请求判断是否可达。
            .networkObserverEnabled(false)
            .memoryCache {
                MemoryCache.Builder(this)
                    .maxSizePercent(memPercent)
                    .build()
            }
            .allowRgb565(profile.tier == PerformanceTier.LOW)
            .crossfade(false)
            .build()
    }
}
