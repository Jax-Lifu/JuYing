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
import kotlinx.coroutines.yield

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
    private var pageStartIds = emptySet<Pair<String, String>>()

    fun queryChanged(text: String) {
        val q = text.trim()
        suggestJob?.cancel()
        if (q.length >= 2) {
            suggestJob = viewModelScope.launch {
                delay(200) // 防抖
                val list = try { vod.suggestions(q) }
                    catch (error: Exception) { if (error is CancellationException) throw error else emptyList() }
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
        lastRequestPage = 0
        if (state.value.keyword.isNotEmpty()) loadPage(1)
    }

    fun more() { if (!state.value.loading && !state.value.failed && state.value.hasMore) loadPage(state.value.page + 1) }
    fun retry() { if (!state.value.loading && state.value.keyword.isNotEmpty()) loadPage(lastRequestPage) }

    private fun loadPage(page: Int) {
        request?.cancel()
        state.update { it.copy(loading = true, failed = false, targets = emptyMap(), suggestions = emptyList()) }
        request = viewModelScope.launch {
            try {
                var currentPage = page
                while (true) {
                    val before = state.value
                    if (currentPage != lastRequestPage) pageStartIds = before.posters.map { it.item.sourceId to it.item.id }.toSet()
                    lastRequestPage = currentPage
                    var hasMore = false
                    vod.searchUpdates(before.keyword, currentPage).collect { update ->
                        if (update is SearchUpdate.Finished && update.outcome == SearchOutcome.SUCCESS) {
                            hasMore = hasMore || (update.hasMore ?: update.items.any { (it.sourceId to it.id) !in pageStartIds })
                        }
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
                    val continueEmptySearch = succeeded && !failed && hasMore && state.value.posters.isEmpty()
                    state.update { it.copy(loading = continueEmptySearch, failed = failed,
                        page = if (succeeded) currentPage else before.page,
                        hasMore = hasMore) }
                    if (!continueEmptySearch) break
                    currentPage++
                    state.update { it.copy(targets = emptyMap()) }
                    // 缓存源也可能同步返回空页；让新查询有机会取消本次搜索。
                    yield()
                }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                state.update { it.copy(loading = false, failed = true) }
            }
        }
    }
}
