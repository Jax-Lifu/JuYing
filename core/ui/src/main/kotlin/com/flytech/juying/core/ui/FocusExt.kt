package com.flytech.juying.core.ui

import android.view.View
import android.view.ViewGroup
import androidx.core.view.isVisible

/** 遥控器焦点放大效果。低配机传 animate=false 直接设置，不跑动画。 */
fun View.enableFocusScale(scale: Float = 1.06f, animate: Boolean = true) {
    onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
        val target = if (hasFocus) scale else 1f
        if (animate) v.animate().scaleX(target).scaleY(target).setDuration(120).start()
        else { v.scaleX = target; v.scaleY = target }
    }
}

/** 页面提供进入时的首选焦点控件。在电视遥控器导航或切换栏目时直接聚焦，避免焦点滞留在导航条。 */
interface FocusTarget {
    fun requestPrimaryFocus(): Boolean
}

/** 递归查找可见且可聚焦的首个子视图 */
fun View.findFirstFocusable(): View? {
    if (isFocusable && isVisible && isAttachedToWindow) return this
    if (this is ViewGroup) {
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            val focusable = child.findFirstFocusable()
            if (focusable != null) return focusable
        }
    }
    return null
}
