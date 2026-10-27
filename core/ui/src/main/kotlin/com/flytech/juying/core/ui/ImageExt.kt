package com.flytech.juying.core.ui

import android.widget.ImageView
import coil.load

/** 限制解码尺寸，防止大图撑爆低内存设备。 */
fun ImageView.loadImage(url: String?, maxSizePx: Int = 256,
    @androidx.annotation.DrawableRes fallbackRes: Int = com.flytech.juying.core.designsystem.R.drawable.bg_poster_placeholder) {
    // null 也交给 Coil，取消复用 View 上一张封面的未完成请求。
    load(url) {
        size(maxSizePx)
        crossfade(false)
        allowHardware(true)
        placeholder(fallbackRes)
        error(fallbackRes)
        fallback(fallbackRes)
    }
}
