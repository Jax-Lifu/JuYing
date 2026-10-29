package com.flytech.juying.core.ui

import android.content.Context
import com.flytech.juying.core.model.PlayRequest

/**
 * 跨 Feature 页面导航路由抽象契约。
 *
 * **What**: 提供页面间解耦跳转的标准 API。
 *
 * **Why**: 遵循 Now in Android 架构铁律，`feature:*` 模块之间严禁直接相互依赖；
 * 所有跨页面跳转（如从搜索进点播详情、从浏览页调起播放器）一律通过此接口由 `app` 模块装配转发。
 */
interface Navigator {

    /** 打开统一全屏播放页。 */
    fun openPlayer(context: Context, request: PlayRequest)

    /** 打开影片详情页。 */
    fun openVodDetail(from: androidx.fragment.app.Fragment, sourceId: String, itemId: String)

    /** 打开全源聚合搜索页。 */
    fun openSearch(from: androidx.fragment.app.Fragment)

    /** 打开指定数据源的编辑/配置页（传 null 表示打开源列表管理）。 */
    fun openSourceSettings(from: androidx.fragment.app.Fragment, sourceId: String? = null)

    /** 打开网络存储设备（SMB/NAS）添加与发现向导。 */
    fun openNetworkStorage(from: androidx.fragment.app.Fragment)

    /** 仅申请本机文件访问权限；授权后的目录仍由应用内浏览页展示。 */
    fun requestStorageAccess(from: androidx.fragment.app.Fragment)

    /** 打开播放历史记录页。 */
    fun openHistory(from: androidx.fragment.app.Fragment)

    /** 打开数据源管理页。 */
    fun openSources(from: androidx.fragment.app.Fragment)

    /** 激活并切换至指定数据源对应的业务页面。 */
    fun openSource(activity: androidx.fragment.app.FragmentActivity, sourceId: String, capability: com.flytech.juying.core.model.SourceCapability? = null)

    /** 弹出全屏/浮层切源面板。 */
    fun showSourcePicker(activity: androidx.fragment.app.FragmentActivity, currentSourceId: String? = null)

    companion object {
        const val STORAGE_ACCESS_RESULT = "storage_access_result"
    }
}
