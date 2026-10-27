package com.flytech.juying.core.model

enum class DeviceForm { TV, TABLET, PHONE }

/** 性能档位，驱动缓冲区、缓存、动画等一切「按设备降级」的策略。 */
enum class PerformanceTier { LOW, MID, HIGH }

data class DeviceProfile(
    val form: DeviceForm,
    val tier: PerformanceTier,
    val totalMemMb: Int,
) {
    val isTv get() = form == DeviceForm.TV
    val enableAnimations get() = tier != PerformanceTier.LOW
}
