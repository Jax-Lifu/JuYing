package com.flytech.juying.core.ui

/** Editors protect dirty forms before shell navigation discards their view. */
interface NavigationGuard {
    fun confirmLeave(proceed: () -> Unit)
}
