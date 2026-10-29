package com.flytech.juying.feature.live

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.LiveRepository
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.SourceCapability
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/** 直播页面 UI 状态实体。 */
data class LiveUiState(
    val sourceId: String? = null,
    val groups: List<ChannelGroup> = emptyList(),
    val selectedGroup: Int = 0,
    val loading: Boolean = true,
    val error: String? = null,
)

@HiltViewModel
/**
 * 直播页面 ViewModel。
 *
 * **What**: 负责多源分组与频道展示、当前选中分组状态驱动以及响应外部切源通知。
 *
 * **Why**: 遵循响应式状态流，优先呈现已缓存的频道列表，并在换源时自动取消未完成的后台加载任务。
 */
class LiveViewModel @Inject constructor(
    private val sources: SourceRepository,
    private val live: LiveRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(LiveUiState())
    val uiState: StateFlow<LiveUiState> = _uiState.asStateFlow()

    private var job: Job? = null

    init {
        viewModelScope.launch {
            val first = sources.observeSources(SourceCapability.LIVE).first().firstOrNull()
            if (first != null) load(first.id) else _uiState.update { it.copy(loading = false, error = "请先添加直播源") }
        }
    }

    fun load(sourceId: String, selectedGroup: Int = 0) {
        job?.cancel()
        _uiState.value = LiveUiState(sourceId = sourceId, selectedGroup = selectedGroup)
        job = viewModelScope.launch {
            live.channelGroups(sourceId)
                .onStart { _uiState.update { it.copy(sourceId = sourceId, loading = true, error = null) } }
                .catch { e -> _uiState.update { it.copy(loading = false, error = e.message ?: "加载失败") } }
                .collect { groups ->
                    _uiState.update {
                        it.copy(
                            groups = groups,
                            loading = false,
                            selectedGroup = it.selectedGroup.coerceIn(0, (groups.size - 1).coerceAtLeast(0)),
                        )
                    }
                }
        }
    }

    fun selectGroup(index: Int) = _uiState.update { it.copy(selectedGroup = index) }
}
