package com.flytech.juying.core.ui

import android.content.Context
import com.flytech.juying.core.model.PlayRequest

/**
 * 跨 feature 跳转的唯一出口。feature 之间互不依赖，需要打开别的页面时调用这里，
 * 由 app 模块实现。以后真要拆 api/impl，只需把这里迁出去。
 */
interface Navigator {
    fun openPlayer(context: Context, request: PlayRequest)
    fun openVodDetail(from: androidx.fragment.app.Fragment, sourceId: String, itemId: String)
    fun openSearch(from: androidx.fragment.app.Fragment)
    fun openSourceSettings(from: androidx.fragment.app.Fragment, sourceId: String? = null)
    fun openNetworkStorage(from: androidx.fragment.app.Fragment)
    /** 仅申请本机文件访问权限；授权后的目录仍由应用内浏览页展示。 */
    fun requestStorageAccess(from: androidx.fragment.app.Fragment)
    fun openHistory(from: androidx.fragment.app.Fragment)
    fun openSources(from: androidx.fragment.app.Fragment)
    fun openSource(activity: androidx.fragment.app.FragmentActivity, sourceId: String, capability: com.flytech.juying.core.model.SourceCapability? = null)
    fun showSourcePicker(activity: androidx.fragment.app.FragmentActivity, currentSourceId: String? = null)
    companion object { const val STORAGE_ACCESS_RESULT = "storage_access_result" }
}
