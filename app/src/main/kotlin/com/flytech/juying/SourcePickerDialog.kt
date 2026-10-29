package com.flytech.juying

import android.app.Dialog
import android.content.res.Configuration
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.core.os.bundleOf
import androidx.core.view.isVisible
import androidx.core.view.doOnNextLayout
import androidx.core.widget.doAfterTextChanged
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.flytech.juying.core.data.*
import com.flytech.juying.core.model.*
import com.flytech.juying.core.ui.*
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import com.flytech.juying.core.designsystem.R as D

/** 全屏/浮层数据源切换选择弹窗，支持按能力筛选、状态显示与无感快速切源。 */
@AndroidEntryPoint
class SourcePickerDialog : BottomSheetDialogFragment() {
    @Inject lateinit var sources: SourceRepository
    @Inject lateinit var history: HistoryRepository
    @Inject lateinit var memory: SourceBrowseMemory
    @Inject lateinit var navigator: Navigator
    private var available = emptyList<SourceConfig>()
    private var recent = emptyList<HistoryEntry>()
    private var showRecent = false
    private var query = ""
    private var list: RecyclerView? = null
    private var empty: TextView? = null
    private var trigger: android.view.View? = null
    private val rows = MediaRowAdapter({ row ->
        if (showRecent) {
            val entry = recent.firstOrNull { it.id == row.id } ?: return@MediaRowAdapter
            if (available.none { it.id == entry.sourceId }) {
                empty?.setText(D.string.ui_source_missing)
                empty?.isVisible = true
            } else {
                dismiss()
                (activity as? SourcePickerHost)?.playFromPicker(PlayRequest(entry.kind, entry.sourceId, entry.ref,
                    entry.title, entry.extra))
            }
        } else {
            dismiss()
            navigator.openSource(requireActivity(), row.id)
        }
    })

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        trigger = requireActivity().currentFocus
        val dialog = BottomSheetDialog(requireContext(), theme)
        dialog.window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN or
            android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_PAN)
        val view = layoutInflater.inflate(R.layout.dialog_source_picker, null)
        dialog.setContentView(view)
        list = view.findViewById<RecyclerView>(R.id.source_list).apply {
            layoutManager = GridLayoutManager(context, resources.getInteger(D.integer.jy_source_columns))
            adapter = rows
            itemAnimator = null
        }
        empty = view.findViewById(R.id.empty)
        val all = view.findViewById<Button>(R.id.all)
        val recentTab = view.findViewById<Button>(R.id.recent)
        all.isSelected = true
        all.setOnClickListener { showRecent = false; all.isSelected = true; recentTab.isSelected = false; render() }
        recentTab.setOnClickListener { showRecent = true; all.isSelected = false; recentTab.isSelected = true; render() }
        view.findViewById<EditText>(R.id.query).doAfterTextChanged { query = it.toString(); render() }
        view.findViewById<android.view.View>(R.id.close).setOnClickListener { dismiss() }
        view.findViewById<android.view.View>(R.id.manage).setOnClickListener {
            dismiss()
            requireActivity().startActivity(MainActivity.sourcesIntent(requireContext()))
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(sources.observeSources(), history.observeRecent(30)) { configs, entries -> configs to entries }
                    .collect { (configs, entries) -> available = configs.filter { it.enabled }; recent = entries; render() }
            }
        }
        dialog.setOnShowListener {
            val sheet = dialog.findViewById<android.widget.FrameLayout>(com.google.android.material.R.id.design_bottom_sheet)!!
            sheet.layoutParams = sheet.layoutParams.apply { height = (resources.displayMetrics.heightPixels * .9f).toInt() }
            // 展开位置依赖新高度，必须等 BottomSheet 完成测量。
            sheet.doOnNextLayout { dialog.behavior.state = BottomSheetBehavior.STATE_EXPANDED }
            dialog.behavior.skipCollapsed = true
            val tv = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK == Configuration.UI_MODE_TYPE_TELEVISION
            if (tv) dialog.behavior.isDraggable = false
            if (resources.getBoolean(D.bool.jy_wide)) {
                dialog.window?.setLayout((resources.displayMetrics.widthPixels * .85f).toInt(), ViewGroup.LayoutParams.MATCH_PARENT)
                dialog.window?.setGravity(Gravity.CENTER)
            }
        }
        return dialog
    }

    private fun render() {
        val sourceNames = available.associate { it.id to it.name }
        val items = if (showRecent) recent.map { entry ->
            MediaRow(entry.id, entry.title, sourceNames[entry.sourceId] ?: getString(D.string.ui_source_missing),
                if (entry.kind == PlayKind.LIVE) D.drawable.ic_live else D.drawable.ic_play,
                progress = if (entry.kind != PlayKind.LIVE && entry.durationMs > 0) (entry.positionMs * 1000 / entry.durationMs).toInt() else null)
        } else available.map { config ->
            val caps = sources.capabilities(config)
            val caption = caps.filter { it != SourceCapability.SEARCH }.joinToString(" · ") { getString(when (it) {
                SourceCapability.LIVE -> D.string.ui_live
                SourceCapability.VOD -> D.string.ui_vod
                else -> D.string.ui_files
            }) }.ifEmpty { getString(D.string.ui_unsupported) }
            val icon = when (config.type) {
                SourceType.CCTV -> D.drawable.ic_tv_tower
                SourceType.LOCAL -> D.drawable.ic_storage
                SourceType.SMB -> D.drawable.ic_server
                SourceType.TVBOX -> D.drawable.ic_cloud_stream
                SourceType.IPTV -> D.drawable.ic_live
                else -> when {
                    SourceCapability.LIVE in caps -> D.drawable.ic_live
                    SourceCapability.VOD in caps -> D.drawable.ic_vod
                    else -> D.drawable.ic_files
                }
            }
            MediaRow(config.id, config.name, listOf(caption, config.type.name, memory.get(config.id, "location"))
                .filter { it.isNotEmpty() }.joinToString(" · "), icon,
                selected = config.id == arguments?.getString("current"))
        }
        val filtered = items.filter { query.isBlank() || "${it.title} ${it.subtitle}".contains(query, true) }
        empty?.isVisible = filtered.isEmpty()
        empty?.setText(if (showRecent) D.string.ui_no_history else D.string.ui_no_sources)
        val initial = rows.currentList.isEmpty()
        rows.submitList(filtered) {
            if (initial && filtered.isNotEmpty()) {
                val index = filtered.indexOfFirst { it.selected }.coerceAtLeast(0)
                list?.scrollToPosition(index)
                list?.post { list?.findViewHolderForAdapterPosition(index)?.itemView?.requestFocus() }
            }
        }
    }

    override fun onDismiss(dialog: android.content.DialogInterface) {
        super.onDismiss(dialog); trigger?.requestFocus(); trigger = null
    }

    override fun onDestroyView() {
        list?.adapter = null
        list = null
        empty = null
        super.onDestroyView()
    }

    companion object {
        fun create(current: String?) = SourcePickerDialog().apply { arguments = bundleOf("current" to current) }
    }
}
