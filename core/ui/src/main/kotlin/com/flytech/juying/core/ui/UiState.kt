package com.flytech.juying.core.ui

/** 通用 UI 页面状态包装契约，收敛加载中、成功与失败。 */
sealed interface UiState<out T> {
    /** 数据加载中状态。 */
    data object Loading : UiState<Nothing>
    /** 数据加载成功状态。 */
    data class Success<T>(val data: T) : UiState<T>
    /** 数据加载失败状态。 */
    data class Error(val message: String) : UiState<Nothing>
}
