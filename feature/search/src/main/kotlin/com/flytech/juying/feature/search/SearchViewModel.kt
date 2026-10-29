package com.flytech.juying.feature.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.model.SearchOutcome
import com.flytech.juying.core.model.SearchTarget
import com.flytech.juying.core.model.SearchUpdate
import com.flytech.juying.core.ui.VodPoster
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** 搜索页面 UI 状态实体。 */
data class SearchUiState(
    val keyword: String = "",
    val suggestions: List<String> = emptyList(),
    val posters: List<VodPoster> = emptyList(),
    val targets: Map<SearchTarget, SearchOutcome?> = emptyMap(),
    val page: Int = 0,
    val loading: Boolean = false,
    val failed: Boolean = false,
    val hasMore: Boolean = false,
)

@HiltViewModel
/**
 * 全源聚合搜索页面 ViewModel。
 *
 * **What**: 处理用户搜索词输入、拼音首字母实时联想推荐、触发跨源增量搜索请求、维护各站点完成状态并在用户发起新查询时中断旧任务。
 */
class SearchViewModel @Inject constructor(private val vod: VodRepository) : ViewModel() {
    private val state = MutableStateFlow(SearchUiState())
    val ui = state.asStateFlow()
    private var request: Job? = null
    private var suggestJob: Job? = null
    private var lastRequestPage = 1

    fun queryChanged(text: String) {
        val q = text.trim()
        suggestJob?.cancel()
        if (q.length >= 2) {
            suggestJob = viewModelScope.launch {
                delay(200) // 防抖
                val list = runCatching { vod.suggestions(q) }.getOrDefault(emptyList())
                state.update { it.copy(suggestions = list) }
            }
        } else {
            state.update { it.copy(suggestions = emptyList()) }
        }
    }

    fun search(keyword: String) {
        request?.cancel()
        suggestJob?.cancel()
        state.value = SearchUiState(keyword = keyword.trim(), suggestions = emptyList())
        if (state.value.keyword.isNotEmpty()) loadPage(1)
    }

    fun more() { if (!state.value.loading && state.value.hasMore) loadPage(state.value.page + 1) }
    fun retry() { if (!state.value.loading && state.value.keyword.isNotEmpty()) loadPage(lastRequestPage) }

    private fun loadPage(page: Int) {
        request?.cancel()
        lastRequestPage = page
        val before = state.value
        state.update { it.copy(loading = true, failed = false, targets = emptyMap(), suggestions = emptyList()) }
        request = viewModelScope.launch {
            try {
                vod.searchUpdates(before.keyword, page).collect { update ->
                    state.update { current -> when (update) {
                        is SearchUpdate.Discovered -> current.copy(targets = current.targets + update.targets.associateWith { null })
                        is SearchUpdate.Finished -> current.copy(
                            targets = current.targets + (update.target to update.outcome),
                            posters = (current.posters + update.items.map { VodPoster(it, update.target.label) })
                                .distinctBy { it.item.sourceId to it.item.id })
                    } }
                }
                val failed = state.value.targets.values.any { it == SearchOutcome.FAILED || it == SearchOutcome.TIMED_OUT }
                val succeeded = state.value.targets.values.any { it == SearchOutcome.SUCCESS }
                state.update { it.copy(loading = false, failed = failed,
                    page = if (succeeded) page else before.page,
                    hasMore = succeeded) }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                state.update { it.copy(loading = false, failed = true) }
            }
        }
    }
}
