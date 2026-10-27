package com.flytech.juying.core.ui

import android.view.View

/** 遥控器焦点放大效果。低配机传 animate=false 直接设置，不跑动画。 */
fun View.enableFocusScale(scale: Float = 1.06f, animate: Boolean = true) {
    onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
        val target = if (hasFocus) scale else 1f
        if (animate) v.animate().scaleX(target).scaleY(target).setDuration(120).start()
        else { v.scaleX = target; v.scaleY = target }
    }
}
