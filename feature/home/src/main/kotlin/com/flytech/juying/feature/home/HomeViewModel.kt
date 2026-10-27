package com.flytech.juying.feature.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.model.HistoryEntry
import com.flytech.juying.core.model.VodItem
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class HomeViewModel @Inject constructor(private val vod: VodRepository) : ViewModel() {
    private val items = MutableStateFlow<List<VodItem>>(emptyList())
    val recommendations = items.asStateFlow()
    private var sourceId: String? = null
    private var request: Job? = null

    fun load(source: String?) {
        if (sourceId == source) return
        sourceId = source
        request?.cancel()
        items.value = emptyList()
        if (source == null) return
        request = viewModelScope.launch {
            try {
                val category = vod.categories(source).firstOrNull() ?: return@launch
                val result = vod.list(source, category.id, RECOMMENDATION_PAGE)
                ensureActive()
                if (sourceId == source) items.value = result.take(MAX_RECOMMENDATIONS)
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
