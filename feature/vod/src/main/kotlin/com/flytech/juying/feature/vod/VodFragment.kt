package com.flytech.juying.feature.vod

import android.os.Bundle
import android.view.View
import com.flytech.juying.core.data.SourceBrowseMemory
import com.flytech.juying.core.model.SourceCapability
import androidx.core.view.isVisible
import androidx.core.view.doOnLayout
import androidx.fragment.app.viewModels
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.flytech.juying.core.ui.*
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import javax.inject.Inject
import com.flytech.juying.core.designsystem.R as DesignR
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.feature.vod.databinding.FragmentVodBinding
import dagger.hilt.android.AndroidEntryPoint

/** 点播分类与瀑布流推荐页面 Fragment。 */
@AndroidEntryPoint
class VodFragment : ViewBindingFragment<FragmentVodBinding>(FragmentVodBinding::inflate), FocusTarget {
    private val vm: VodViewModel by viewModels()
    @Inject lateinit var navigator: Navigator
    @Inject lateinit var memory: SourceBrowseMemory
    private var restoredSite: String? = null
    private var restoredCategory: String? = null
    private var restoredScroll: String? = null

    override fun requestPrimaryFocus(): Boolean {
        if (!isAdded || view == null) return false
        val candidate = binding.posters.takeIf { it.isVisible && (it.adapter?.itemCount ?: 0) > 0 }
            ?: binding.categories.takeIf { it.isVisible && (it.adapter?.itemCount ?: 0) > 0 }
            ?: binding.allCategories.takeIf { it.isVisible }
        if (candidate != null) {
            if (candidate is RecyclerView) {
                val first = candidate.findViewHolderForAdapterPosition(0)?.itemView ?: candidate.getChildAt(0)
                if (first != null && first.requestFocus()) return true
                candidate.scrollToPosition(0)
                candidate.post {
                    candidate.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus()
                        ?: candidate.getChildAt(0)?.requestFocus()
                }
                return true
            }
            if (candidate.requestFocus()) return true
        }
        return binding.root.findFirstFocusable()?.requestFocus() == true
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val posters = VodPosterAdapter { navigator.openVodDetail(this, it.sourceId, it.id) }
        val posterList = binding.posters
        val categoryList = binding.categories
        var displayedItems: List<com.flytech.juying.core.model.VodItem>? = null
        var selectedCategory: String? = null
        val categories = TextChoiceAdapter {
            vm.ui.value.source?.let { source -> memory.put(source.id, "category.${vm.ui.value.site?.id.orEmpty()}", it.id) }
            restoredScroll = null
            vm.selectCategory(it.id)
        }
        binding.posters.apply {
            val columns = resources.getInteger(DesignR.integer.jy_vod_columns)
            // 列表尺寸由父布局决定；追加页不重测外壳，两行回收池避免快速滚动时反复创建海报。
            setHasFixedSize(true)
            recycledViewPool.setMaxRecycledViews(0, columns * RECYCLED_POSTER_ROWS)
            layoutManager = object : GridLayoutManager(context, columns) {
                private var scrollingDown = true
                override fun scrollVerticallyBy(dy: Int, recycler: RecyclerView.Recycler, state: RecyclerView.State): Int {
                    if (dy != 0) scrollingDown = dy > 0
                    return super.scrollVerticallyBy(dy, recycler, state)
                }
                override fun calculateExtraLayoutSpace(state: RecyclerView.State, extraLayoutSpace: IntArray) {
                    super.calculateExtraLayoutSpace(state, extraLayoutSpace)
                    if (state.hasTargetScrollPosition()) return
                    // 只沿滚动方向多绑定一屏，复用 Coil 的小图缓存与回收取消，避免整页封面挤占低配机内存。
                    val screen = (height - paddingTop - paddingBottom).coerceAtLeast(0)
                    val down = scrollingDown || findFirstVisibleItemPosition() <= 0
                    extraLayoutSpace[0] = if (down) 0 else screen
                    extraLayoutSpace[1] = if (down) screen else 0
                }
            }
            adapter = posters
            itemAnimator = null
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    preloadNextPage(recyclerView)
                    updatePageStatus(recyclerView)
                }
            })
        }
        binding.categories.apply {
            layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
            adapter = categories
            itemAnimator = null
        }
        binding.source.setOnClickListener { navigator.showSourcePicker(requireActivity(), vm.ui.value.source?.id) }
        binding.allCategories.setOnClickListener {
            val state = vm.ui.value
            val selected = state.categories.indexOf(state.category)
            MaterialAlertDialogBuilder(requireContext()).setTitle(R.string.vod_categories)
                .setSingleChoiceItems(state.categories.map { it.name }.toTypedArray(), selected) { dialog, index ->
                    val category = state.categories[index]
                    state.source?.let { memory.put(it.id, "category.${state.site?.id.orEmpty()}", category.id) }
                    restoredScroll = null
                    vm.selectCategory(category.id)
                    dialog.dismiss()
                }.show().listView.apply { post { setSelection(selected.coerceAtLeast(0)) } }
        }
        binding.site.setOnClickListener {
            val sites = vm.ui.value.sites
            MaterialAlertDialogBuilder(requireContext()).setTitle(DesignR.string.content_select_site)
                .setItems(sites.map { it.name }.toTypedArray()) { _, index ->
                    vm.ui.value.source?.let { memory.put(it.id, "site", sites[index].id) }
                    vm.selectSite(sites[index])
                }.show()
        }
        binding.retry.setOnClickListener { vm.retry() }
        launchOnStarted { memory.updates.collect {
            val desired = memory.selected(SourceCapability.VOD)
            vm.ui.value.sources.firstOrNull { it.id == desired && it.id != vm.ui.value.source?.id }?.let(vm::selectSource)
        } }
        launchOnStarted { vm.ui.collect { state ->
            val desired = memory.selected(SourceCapability.VOD)
            state.sources.firstOrNull { it.id == desired && it.id != state.source?.id }?.let {
                vm.selectSource(it); return@collect
            }
            state.source?.let { source ->
                memory.select(source.id, SourceCapability.VOD)
                if (restoredSite != source.id && state.sites.isNotEmpty()) {
                    restoredSite = source.id
                    state.sites.firstOrNull { it.id == memory.get(source.id, "site") && it.id != state.site?.id }?.let {
                        vm.selectSite(it); return@collect
                    }
                }
                val key = "${source.id}:${state.site?.id}"
                if (restoredCategory != key && state.categories.isNotEmpty()) {
                    restoredCategory = key
                    state.categories.firstOrNull { it.id == memory.get(source.id, "category.${state.site?.id.orEmpty()}") && it.id != state.category?.id }?.let {
                        vm.selectCategory(it.id); return@collect
                    }
                }
            }
            binding.source.text = state.source?.name ?: getString(DesignR.string.content_select_source)
            binding.source.isVisible = state.source == null
            binding.source.isEnabled = state.sources.isNotEmpty()
            binding.site.text = state.site?.name
            binding.site.isVisible = state.sites.size > 1
            binding.sourceRow.isVisible = state.source == null || state.sites.size > 1
            binding.allCategories.isEnabled = state.categories.isNotEmpty()
            binding.progress.isVisible = state.loading && state.items.isEmpty()
            binding.retry.isVisible = state.failed && !state.loading
            binding.status.isVisible = state.failed || state.items.isEmpty()
            binding.status.setText(when {
                state.loading -> DesignR.string.content_loading
                state.failed -> DesignR.string.content_failed
                state.sources.isEmpty() -> R.string.vod_no_sources
                else -> DesignR.string.content_empty
            })
            categories.submitList(state.categories.map { TextChoice(it.id, it.name, it.id == state.category?.id) }) {
                if (!categoryList.isAttachedToWindow) return@submitList
                if (selectedCategory != state.category?.id) {
                    selectedCategory = state.category?.id
                    categoryList.scrollToPosition(state.categories.indexOf(state.category).coerceAtLeast(0))
                }
            }
            updatePageStatus(posterList)
            if (displayedItems !== state.items) {
              displayedItems = state.items
              posters.submitList(state.items.map { VodPoster(it) }) {
                if (!posterList.isAttachedToWindow || vm.ui.value.items !== state.items) return@submitList
                val key = "${state.source?.id}:${state.category?.id}"
                if (!state.loading && state.items.isNotEmpty() && restoredScroll != key) {
                    val position = state.source?.let { memory.get(it.id, "vod_scroll.${state.category?.id}").toIntOrNull() } ?: 0
                    if (position >= state.items.size && state.hasMore) vm.more() else {
                        restoredScroll = key
                        posterList.scrollToPosition(position.coerceIn(0, state.items.lastIndex))
                    }
                }
                posterList.doOnLayout { preloadNextPage(posterList) }
                if (isResumed && !binding.root.hasFocus()) {
                    requestPrimaryFocus()
                }
              }
            }
            if (state.items.isEmpty() && !state.loading && !state.failed && state.hasMore) {
                posterList.post { preloadNextPage(posterList) }
            }
        } }
    }
    private fun updatePageStatus(list: RecyclerView) {
        val state = vm.ui.value
        val grid = list.layoutManager as GridLayoutManager
        val atEnd = state.items.isNotEmpty() && grid.itemCount == state.items.size &&
            grid.findLastVisibleItemPosition() >= grid.itemCount - grid.spanCount
        val message = when {
            !atEnd -> ""
            state.loading -> getString(R.string.vod_loading_more)
            state.failed -> getString(DesignR.string.content_failed)
            !state.hasMore -> getString(R.string.vod_end)
            else -> ""
        }
        if (binding.pageStatus.text.toString() != message) binding.pageStatus.text = message
    }
    private fun preloadNextPage(list: RecyclerView) {
        if (!list.isAttachedToWindow) return
        val grid = list.layoutManager as GridLayoutManager
        if (grid.itemCount == 0) { vm.more(); return }
        val first = grid.findViewByPosition(grid.findFirstVisibleItemPosition()) ?: return
        val margins = first.layoutParams as RecyclerView.LayoutParams
        val rowHeight = grid.getDecoratedMeasuredHeight(first) + margins.topMargin + margins.bottomMargin
        if (rowHeight <= 0) return
        // 按实际视口预留一屏，手机、平板和 TV 共用；短分页追加后继续补足。
        val rows = (list.height - list.paddingTop - list.paddingBottom + rowHeight - 1) / rowHeight
        if (grid.itemCount - grid.findLastVisibleItemPosition() - 1 <= rows * grid.spanCount) vm.more()
    }
    override fun onDestroyView() {
        vm.ui.value.source?.let { source ->
            memory.put(source.id, "vod_scroll.${vm.ui.value.category?.id}",
                (binding.posters.layoutManager as GridLayoutManager).findFirstVisibleItemPosition().toString())
        }
        restoredScroll = null
        binding.posters.clearOnScrollListeners()
        binding.posters.adapter = null
        binding.categories.adapter = null
        super.onDestroyView()
    }
    private companion object { const val RECYCLED_POSTER_ROWS = 2 }
}
