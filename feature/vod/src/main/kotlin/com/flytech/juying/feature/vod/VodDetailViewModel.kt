package com.flytech.juying.feature.vod

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.model.VodDetail
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** 点播详情页面 UI 状态实体。 */
data class VodDetailUiState(val detail: VodDetail? = null, val group: Int = 0,
    val loading: Boolean = true, val failed: Boolean = false)

@HiltViewModel
/**
 * 影片详情页面 ViewModel。
 *
 * **What**: 异步加载指定数据源与节目 ID 的影片详情、播放线路组及分集列表。
 */
class VodDetailViewModel @Inject constructor(saved: SavedStateHandle, private val vod: VodRepository) : ViewModel() {
    val sourceId: String = checkNotNull(saved[VodDetailFragment.SOURCE_ID])
    private val itemId: String = checkNotNull(saved[VodDetailFragment.ITEM_ID])
    private val state = MutableStateFlow(VodDetailUiState())
    val ui = state.asStateFlow()
    private var request: Job? = null
    init { reload() }
    fun reload() {
        request?.cancel()
        state.value = VodDetailUiState()
        request = viewModelScope.launch {
            try { state.value = VodDetailUiState(detail = vod.detail(sourceId, itemId), loading = false) }
            catch (error: Exception) {
                if (error is CancellationException) throw error
                state.value = VodDetailUiState(loading = false, failed = true)
            }
        }
    }
    fun selectGroup(index: Int) {
        if (index in state.value.detail?.playGroups.orEmpty().indices) state.update { it.copy(group = index) }
    }
}
