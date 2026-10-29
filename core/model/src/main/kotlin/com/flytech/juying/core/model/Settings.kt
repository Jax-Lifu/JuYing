package com.flytech.juying.core.model

enum class DecoderMode { HARDWARE_FIRST, SOFTWARE_FIRST }

/** 应用全局设置实体，包含解码器模式与自动帧率匹配开关。 */
data class AppSettings(
    val decoderMode: DecoderMode = DecoderMode.HARDWARE_FIRST,
    /** 电视端：自动匹配片源帧率（仅在可无缝切换时）。 */
    val autoFrameRate: Boolean = false,
)
