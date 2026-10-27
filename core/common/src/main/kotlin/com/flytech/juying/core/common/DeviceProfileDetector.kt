package com.flytech.juying.core.common

import android.app.ActivityManager
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import com.flytech.juying.core.model.DeviceForm
import com.flytech.juying.core.model.DeviceProfile
import com.flytech.juying.core.model.PerformanceTier
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

object DeviceProfileDetector {

    fun detect(context: Context): DeviceProfile {
        val am = context.getSystemService(ActivityManager::class.java)
        val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val totalMb = (info.totalMem / (1024 * 1024)).toInt()

        val uiMode = context.getSystemService(UiModeManager::class.java)
        val pm = context.packageManager
        // 兼容国产 AOSP 改制机顶盒（如 RK3568/H618 固件未设置 UI_MODE_TYPE_TELEVISION 但无触摸屏）
        val isTv = uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
        val isTablet = context.resources.configuration.smallestScreenWidthDp >= 600

        val form = when {
            isTv -> DeviceForm.TV
            isTablet -> DeviceForm.TABLET
            else -> DeviceForm.PHONE
        }
        // 标称 2GB/4GB 的设备实际 totalMem 会略小，阈值据此放宽。
        val tier = when {
            am.isLowRamDevice || totalMb < 2300 -> PerformanceTier.LOW
            totalMb < 4600 -> PerformanceTier.MID
            else -> PerformanceTier.HIGH
        }
        return DeviceProfile(form, tier, totalMb)
    }
}

@Module
@InstallIn(SingletonComponent::class)
object DeviceModule {
    @Provides
    @Singleton
    fun deviceProfile(@ApplicationContext context: Context): DeviceProfile =
        DeviceProfileDetector.detect(context)
}
