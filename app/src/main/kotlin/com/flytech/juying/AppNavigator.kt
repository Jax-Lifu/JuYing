package com.flytech.juying

import android.content.Context
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.lifecycleScope
import com.flytech.juying.core.data.SourceBrowseMemory
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.SourceCapability
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import kotlinx.coroutines.launch
import com.flytech.juying.core.designsystem.R as D
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.findNavController
import com.flytech.juying.feature.vod.VodDetailFragment
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.feature.player.PlayerActivity
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton

/** 应用层导航路由实现类，装配全局 NavigationController 与跨页面 Intent 跳转。 */
@Singleton
class AppNavigator @Inject constructor(private val sources: SourceRepository, private val memory: SourceBrowseMemory) : Navigator {
    override fun openPlayer(context: Context, request: PlayRequest) {
        context.startActivity(PlayerActivity.intent(context, request))
    }
    override fun openVodDetail(from: Fragment, sourceId: String, itemId: String) {
        from.findNavController().navigate(R.id.vod_detail, VodDetailFragment.arguments(sourceId, itemId))
    }
    override fun openSearch(from: Fragment) = from.findNavController().navigate(R.id.search)
    override fun openSourceSettings(from: Fragment, sourceId: String?) = from.findNavController().navigate(R.id.sources, androidx.core.os.bundleOf("editSourceId" to sourceId))
    override fun openNetworkStorage(from: Fragment) = from.findNavController().navigate(R.id.nas)
    override fun requestStorageAccess(from: Fragment) = (from.requireActivity() as MainActivity).requestStorageAccess()
    override fun openSources(from: Fragment) = showSourcePicker(from.requireActivity())
    override fun openHistory(from: Fragment) = from.findNavController().navigate(R.id.history)
    override fun showSourcePicker(activity: FragmentActivity, currentSourceId: String?) {
        if (activity.supportFragmentManager.findFragmentByTag("source-picker") == null)
            SourcePickerDialog.create(currentSourceId).show(activity.supportFragmentManager, "source-picker")
    }
    override fun openSource(activity: FragmentActivity, sourceId: String, capability: SourceCapability?) {
        activity.lifecycleScope.launch {
            val config = sources.get(sourceId)
            if (config == null || !config.enabled) {
                MaterialAlertDialogBuilder(activity).setMessage(D.string.ui_source_missing).setPositiveButton(D.string.ui_close, null).show()
                return@launch
            }
            val choices = sources.capabilities(config).filter { it != SourceCapability.SEARCH }
            // 当前页面决定浏览能力；首页等无上下文入口让用户选择，避免上次直播记录锁住点播入口。
            val selected = capability?.takeIf { it in choices }
                ?: (activity as? MainActivity)?.currentSourceCapability?.takeIf { it in choices }
                ?: choices.singleOrNull()
            fun route(cap: SourceCapability) {
                memory.select(sourceId, cap)
                if (activity is MainActivity) activity.openSource(cap) else {
                    activity.startActivity(MainActivity.sourceIntent(activity, cap))
                    activity.finish()
                }
            }
            when {
                selected != null -> route(selected)
                choices.isEmpty() -> MaterialAlertDialogBuilder(activity).setMessage(D.string.ui_unsupported)
                    .setPositiveButton(D.string.ui_close, null).show()
                else -> MaterialAlertDialogBuilder(activity).setTitle(config.name)
                    .setItems(choices.map { activity.getString(when (it) {
                        SourceCapability.LIVE -> D.string.ui_live
                        SourceCapability.VOD -> D.string.ui_vod
                        else -> D.string.ui_files
                    }) }.toTypedArray()) { _, index -> route(choices[index]) }.show()
            }
        }
    }
}

/** 全局导航接口 [Navigator] 的 Hilt 依赖注入绑定模块。 */
@Module
@InstallIn(SingletonComponent::class)
abstract class NavigationModule {
    @Binds abstract fun navigator(impl: AppNavigator): Navigator
}
