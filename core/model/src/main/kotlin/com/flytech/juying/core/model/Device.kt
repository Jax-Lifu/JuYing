package com.flytech.juying.core.model

enum class DeviceForm { TV, TABLET, PHONE }

/** 性能档位，驱动缓冲区、缓存、动画等一切「按设备降级」的策略。 */
enum class PerformanceTier { LOW, MID, HIGH }

/** 当前设备的运行概况：包括硬件形态（TV/手机/平板）、性能档位与物理内存大小。 */
data class DeviceProfile(
    val form: DeviceForm,
    val tier: PerformanceTier,
    val totalMemMb: Int,
) {
    val isTv get() = form == DeviceForm.TV
    val enableAnimations get() = tier != PerformanceTier.LOW
}
