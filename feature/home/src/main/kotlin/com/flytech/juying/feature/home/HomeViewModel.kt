package com.flytech.juying.feature.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.model.HistoryEntry
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.VodItem
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 主页 ViewModel，负责推荐内容推荐算法、去重及继续观看合流。 */
@HiltViewModel
class HomeViewModel @Inject constructor(private val vod: VodRepository) : ViewModel() {
    private val items = MutableStateFlow<List<VodItem>>(emptyList())
    val recommendations = items.asStateFlow()
    private var source: SourceConfig? = null
    private var loaded = false
    private var request: Job? = null

    fun load(config: SourceConfig?) {
        if (source == config && (loaded || request?.isActive == true)) return
        source = config
        loaded = false
        request?.cancel()
        items.value = emptyList()
        if (config == null) return
        request = viewModelScope.launch {
            try {
                val category = vod.categories(config.id).firstOrNull()
                val result = category?.let { vod.list(config.id, it.id, RECOMMENDATION_PAGE) }.orEmpty()
                ensureActive()
                if (source == config) {
                    items.value = result.take(MAX_RECOMMENDATIONS)
                    loaded = true
                }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                // 推荐不可用时保留浏览入口，不影响继续观看或触发额外全源请求。
            }
        }
    }

    internal companion object {
        const val RECOMMENDATION_PAGE = 1
        const val MAX_RECOMMENDATIONS = 24

        fun recommendationsFor(items: List<VodItem>, history: List<HistoryEntry>): List<VodItem> = items.filter { item ->
            history.none { it.sourceId == item.sourceId && (it.extra["itemId"] == item.id || it.ref == item.id) }
        }
    }
}
