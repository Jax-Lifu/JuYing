package com.flytech.juying.core.model

enum class DecoderMode { HARDWARE_FIRST, SOFTWARE_FIRST }

data class AppSettings(
    val decoderMode: DecoderMode = DecoderMode.HARDWARE_FIRST,
    /** 电视端：自动匹配片源帧率（仅在可无缝切换时）。 */
    val autoFrameRate: Boolean = false,
)
