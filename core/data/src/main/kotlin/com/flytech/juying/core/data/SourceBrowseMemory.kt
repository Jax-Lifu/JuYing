package com.flytech.juying.core.data

import android.content.Context
import com.flytech.juying.core.model.SourceCapability
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 数据源浏览状态与导航记忆存储。
 *
 * **What**: 记录用户在各业务板块（直播、点播、文件浏览）最后激活的数据源 ID，
 * 以及该源最后停留的子站点、分类、路径与焦点位置。
 *
 * **Why**: 保证用户离开后再次进入时无感恢复上下文，且记忆严格绑定不可变的 [sourceId]，
 * 避免因数据源改名或重名产生路由错乱。
 */
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
