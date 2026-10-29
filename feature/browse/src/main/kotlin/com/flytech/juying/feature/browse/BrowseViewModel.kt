package com.flytech.juying.feature.browse

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.BrowseRepository
import com.flytech.juying.core.data.SourceBrowseMemory
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.FileEntry
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.StorageAccessRequiredException
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import org.json.JSONArray
import java.io.FileNotFoundException

/** 文件浏览面包屑路径导航条目。 */
data class BrowseCrumb(val path: String, val label: String)

/** 文件浏览页面 UI 状态。 */
data class BrowseUiState(val source: SourceConfig? = null, val path: String = "", val canGoUp: Boolean = false,
    val files: List<FileEntry> = emptyList(), val loading: Boolean = true, val failed: Boolean = false,
    val accessDenied: Boolean = false, val recovered: Boolean = false,
    val sources: List<SourceConfig> = emptyList(), val showRoots: Boolean = true,
    val breadcrumbs: List<BrowseCrumb> = emptyList(), val canRequestStorageAccess: Boolean = false)

/** 文件与存储浏览页面 ViewModel。 */
@HiltViewModel
class BrowseViewModel @Inject constructor(private val sources: SourceRepository,
    private val browse: BrowseRepository, private val memory: SourceBrowseMemory) : ViewModel() {
    private val state = MutableStateFlow(BrowseUiState())
    val ui = state.asStateFlow()
    private var job: Job? = null
    private val parents = mutableListOf<String>()
    private var selectedId: String? = null
    init {
        viewModelScope.launch {
            combine(sources.observeSources(SourceCapability.BROWSE), memory.updates) { configs, _ -> configs }.collect { configs ->
                val requestedId = memory.selected(SourceCapability.BROWSE)
                val changed = requestedId != selectedId
                val source = configs.firstOrNull { it.id == requestedId }
                state.value = state.value.copy(sources = configs)
                when {
                    source == null -> { selectedId = null; showRoots() }
                    changed || (!state.value.showRoots && source != state.value.source) -> selectSource(source.id)
                    state.value.showRoots -> state.value = state.value.copy(loading = false)
                }
            }
        }
    }
    fun showRoots() {
        job?.cancel(); parents.clear()
        state.value = BrowseUiState(sources = state.value.sources, loading = false)
    }
    fun selectSource(id: String) {
        val source = state.value.sources.firstOrNull { it.id == id } ?: return
        job?.cancel(); parents.clear()
        state.value = BrowseUiState(source = source, sources = state.value.sources, showRoots = false)
        runCatching { JSONArray(memory.get(source.id, "parents")) }.getOrNull()?.let { array ->
            repeat(array.length()) { parents.add(array.getString(it)) }
        }
        selectedId = source.id
        memory.select(source.id, SourceCapability.BROWSE)
        load(memory.get(source.id, "path"))
    }
    fun enter(entry: FileEntry) { if (entry.isDirectory) {
        state.value.source?.let { memory.put(it.id, "label.${entry.path}", entry.name) }
        parents.add(state.value.path); load(entry.path)
    } }
    fun up() { if (parents.isNotEmpty()) load(parents.removeAt(parents.lastIndex)) else showRoots() }
    fun openCrumb(path: String) {
        if (path == state.value.path || state.value.breadcrumbs.none { it.path == path }) return
        val index = parents.indexOf(path)
        if (index < 0) parents.clear() else while (parents.size > index) parents.removeAt(parents.lastIndex)
        load(path)
    }
    fun retry() = load(state.value.path)
    private fun load(path: String) {
        val source = state.value.source ?: return
        job?.cancel()
        state.value = state.value.copy(path = path, canGoUp = parents.isNotEmpty(), files = emptyList(), loading = true,
            failed = false, accessDenied = false, recovered = false, canRequestStorageAccess = false,
            breadcrumbs = breadcrumbs(source, path))
        job = viewModelScope.launch {
            var currentPath = path
            while (true) {
                memory.put(source.id, "path", currentPath)
                memory.put(source.id, "location", memory.get(source.id, "label.$currentPath").ifEmpty { currentPath })
                memory.put(source.id, "parents", JSONArray(parents).toString())
                try {
                    val files = browse.list(source.id, currentPath).sortedWith(compareByDescending<FileEntry> { it.isDirectory }.thenBy { it.name.lowercase() })
                    ensureActive()
                    state.value = state.value.copy(files = files, loading = false)
                    break
                } catch (e: CancellationException) { throw e }
                catch (e: Exception) {
                    ensureActive()
                    if (e is FileNotFoundException && (parents.isNotEmpty() || currentPath.isNotEmpty())) {
                        currentPath = if (parents.isNotEmpty()) parents.removeAt(parents.lastIndex) else ""
                        state.value = state.value.copy(path = currentPath, canGoUp = parents.isNotEmpty(), recovered = true,
                            breadcrumbs = breadcrumbs(source, currentPath))
                    } else if (e is FileNotFoundException) {
                        parents.clear()
                        state.value = BrowseUiState(sources = state.value.sources, loading = false, failed = true)
                        break
                    } else {
                        state.value = state.value.copy(loading = false, failed = true, accessDenied = e is SecurityException,
                            canRequestStorageAccess = e is StorageAccessRequiredException)
                        break
                    }
                }
            }
        }
    }
    private fun breadcrumbs(source: SourceConfig, path: String): List<BrowseCrumb> =
        (listOf("") + parents + path).distinct().map { item ->
            BrowseCrumb(item, if (item.isEmpty()) source.name else memory.get(source.id, "label.$item").ifEmpty { item })
        }
}
