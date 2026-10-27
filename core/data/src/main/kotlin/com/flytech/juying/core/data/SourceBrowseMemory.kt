package com.flytech.juying.core.data

import android.content.Context
import com.flytech.juying.core.model.SourceCapability
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/** Source IDs, never display names, own each browsing position and category selection. */
@Singleton
class SourceBrowseMemory @Inject constructor(@ApplicationContext context: Context) {
    private val prefs by lazy { context.getSharedPreferences("source_browse", Context.MODE_PRIVATE) }
    private val changes = MutableStateFlow(0L)
    val updates = changes.asStateFlow()
    fun selected(capability: SourceCapability): String? = prefs.getString("selected.${capability.name}", null)
    fun lastCapability(sourceId: String): SourceCapability? = prefs.getString("$sourceId.capability", null)
        ?.let { runCatching { SourceCapability.valueOf(it) }.getOrNull() }
    fun select(sourceId: String, capability: SourceCapability) {
        if (selected(capability) == sourceId && lastCapability(sourceId) == capability) return
        prefs.edit().putString("selected.${capability.name}", sourceId)
            .putString("$sourceId.capability", capability.name).apply()
        changes.value++
    }
    fun get(sourceId: String, key: String): String = prefs.getString("$sourceId.$key", "").orEmpty()
    fun put(sourceId: String, key: String, value: String) { prefs.edit().putString("$sourceId.$key", value).apply() }
}
