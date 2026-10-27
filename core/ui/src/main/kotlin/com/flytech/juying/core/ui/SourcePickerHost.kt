package com.flytech.juying.core.ui

import com.flytech.juying.core.model.PlayRequest

/** The owning Activity decides whether a recent item replaces or opens its player. */
interface SourcePickerHost {
    fun playFromPicker(request: PlayRequest)
}
