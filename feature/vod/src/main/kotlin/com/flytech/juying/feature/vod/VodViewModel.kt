package com.flytech.juying.feature.vod

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.model.*
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class VodUiState(
    val sources: List<SourceConfig> = emptyList(), val source: SourceConfig? = null,
    val sites: List<SubSource> = emptyList(), val site: SubSource? = null,
    val categories: List<VodCategory> = emptyList(), val category: VodCategory? = null,
    val items: List<VodItem> = emptyList(), val page: Int = 0,
    val loading: Boolean = false, val failed: Boolean = false, val hasMore: Boolean = false,
)

@HiltViewModel
class VodViewModel @Inject constructor(sources: SourceRepository, private val vod: VodRepository) : ViewModel() {
    private val state = MutableStateFlow(VodUiState())
    val ui = state.asStateFlow()
    private var request: Job? = null
    private var unchangedPages = 0

    init {
        viewModelScope.launch {
            sources.observeSources(SourceCapability.VOD).collect { available ->
                val selected = available.firstOrNull { it.id == state.value.source?.id } ?: available.firstOrNull()
                val changed = selected != state.value.source
                state.update { it.copy(sources = available) }
                if (changed) selectSource(selected)
            }
        }
    }

    fun selectSource(source: SourceConfig?) {
        request?.cancel()
        unchangedPages = 0
        state.value = VodUiState(sources = state.value.sources, source = source, loading = source != null)
        if (source == null) return
        request = viewModelScope.launch {
            try {
                val sites = vod.subSources(source.id)
                currentCoroutineContext().ensureActive()
                val site = sites.firstOrNull()
                state.update { it.copy(sites = sites, site = site) }
                loadCategories(source.id, site?.id)
            } catch (error: Exception) { fail(error) }
        }
    }

    fun selectSite(site: SubSource) {
        val source = state.value.source ?: return
        request?.cancel()
        unchangedPages = 0
        state.update { it.copy(site = site, categories = emptyList(), category = null,
            items = emptyList(), page = 0, loading = true, failed = false, hasMore = false) }
        request = viewModelScope.launch {
            try { loadCategories(source.id, site.id) } catch (error: Exception) { fail(error) }
        }
    }

    private suspend fun loadCategories(sourceId: String, siteId: String?) {
        val categories = vod.categories(sourceId, siteId)
        currentCoroutineContext().ensureActive()
        state.update { it.copy(categories = categories, category = categories.firstOrNull()) }
        if (categories.isEmpty()) state.update { it.copy(loading = false) } else loadPage(1)
    }

    fun selectCategory(id: String) {
        val category = state.value.categories.firstOrNull { it.id == id } ?: return
        request?.cancel()
        unchangedPages = 0
        state.update { it.copy(category = category, items = emptyList(), page = 0, hasMore = false) }
        requestPage(1)
    }

    fun more() { if (!state.value.loading && !state.value.failed && state.value.hasMore) requestPage(state.value.page + 1) }
    fun retry() {
        unchangedPages = 0
        val current = state.value
        if (current.category != null) requestPage(current.page + 1)
        else if (current.site != null) selectSite(current.site) else selectSource(current.source)
    }

    private fun requestPage(page: Int) {
        request?.cancel()
        state.update { it.copy(loading = true, failed = false) }
        request = viewModelScope.launch { try { loadPage(page) } catch (error: Exception) { fail(error) } }
    }

    private suspend fun loadPage(page: Int) {
        val current = state.value
        val source = current.source ?: return
        val category = current.category ?: return
        val result = vod.listPage(source.id, category.id, page)
        // Some source runtimes finish after cancellation; only the current request may publish.
        currentCoroutineContext().ensureActive()
        val combined = (current.items + result.items).distinctBy { it.sourceId to it.id }
        val grew = combined.size > current.items.size
        unchangedPages = if (grew) 0 else unchangedPages + 1
        // 错误的上游页数不能触发无界后台请求；保留“仍有下一页”并允许手动重试。
        state.update { it.copy(items = combined, page = page, loading = false,
            failed = result.hasMore == true && unchangedPages >= MAX_UNCHANGED_PAGES,
            hasMore = result.hasMore ?: grew) }
    }

    private suspend fun fail(error: Exception) {
        currentCoroutineContext().ensureActive()
        if (error is CancellationException) throw error
        state.update { it.copy(loading = false, failed = true) }
    }
    private companion object { const val MAX_UNCHANGED_PAGES = 3 }
}
