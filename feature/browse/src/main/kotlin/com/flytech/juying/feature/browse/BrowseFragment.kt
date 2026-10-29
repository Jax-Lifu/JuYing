package com.flytech.juying.feature.browse

import android.os.Bundle
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.view.View
import android.text.format.Formatter
import androidx.activity.OnBackPressedCallback
import androidx.core.view.isVisible
import androidx.core.content.ContextCompat
import androidx.fragment.app.viewModels
import androidx.recyclerview.widget.LinearLayoutManager
import com.flytech.juying.core.data.SourceBrowseMemory
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.ui.MediaRow
import com.flytech.juying.core.ui.MediaRowAdapter
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.core.ui.TextChoice
import com.flytech.juying.core.ui.TextChoiceAdapter
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.feature.browse.databinding.FragmentBrowseBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import com.flytech.juying.core.designsystem.R as D

/** 文件与存储目录树浏览 Fragment。 */
@AndroidEntryPoint
class BrowseFragment : ViewBindingFragment<FragmentBrowseBinding>(FragmentBrowseBinding::inflate) {
    private val vm: BrowseViewModel by viewModels()
    @Inject lateinit var navigator: Navigator
    @Inject lateinit var memory: SourceBrowseMemory
    private val storageChanges = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { vm.retry() }
    }
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        parentFragmentManager.setFragmentResultListener(Navigator.STORAGE_ACCESS_RESULT, viewLifecycleOwner) { _, _ ->
            if (vm.ui.value.canRequestStorageAccess) vm.retry()
        }
        val manager = LinearLayoutManager(context)
        val rows = MediaRowAdapter({ row ->
            if (vm.ui.value.showRoots) vm.selectSource(row.id)
            else vm.ui.value.files.firstOrNull { it.path == row.id }?.let { entry ->
                val source = vm.ui.value.source ?: return@let
                memory.put(source.id, "scroll.${vm.ui.value.path}", manager.findFirstVisibleItemPosition().toString())
                when {
                    entry.isDirectory -> vm.enter(entry)
                    entry.isVideo -> navigator.openPlayer(requireContext(), PlayRequest(PlayKind.FILE, source.id, entry.path, entry.name,
                        entry.uri?.let { mapOf("uri" to it) }.orEmpty()))
                    else -> MaterialAlertDialogBuilder(requireContext()).setTitle(entry.name)
                        .setMessage(entry.mimeType ?: entry.extension).setPositiveButton(D.string.ui_close, null).show()
                }
            }
        })
        binding.files.apply { layoutManager = manager; adapter = rows; itemAnimator = null }
        val navigation = binding.directoryNavigation
        val crumbs = TextChoiceAdapter { vm.openCrumb(it.id) }
        navigation.breadcrumbs.apply {
            layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
            adapter = crumbs; itemAnimator = null
        }
        navigation.parent.setOnClickListener { vm.up() }
        binding.retry.setOnClickListener { vm.retry() }
        navigation.manage.setOnClickListener { navigator.openSourceSettings(this, vm.ui.value.source?.id) }
        navigation.addStorage.setOnClickListener { vm.showRoots() }
        binding.grantStorage.setOnClickListener { navigator.requestStorageAccess(this) }
        binding.addNas.setOnClickListener { navigator.openNetworkStorage(this) }
        val back = object : OnBackPressedCallback(false) { override fun handleOnBackPressed() = vm.up() }
        requireActivity().onBackPressedDispatcher.addCallback(viewLifecycleOwner, back)
        launchOnStarted { vm.ui.collect { state ->
            binding.storageToolbar.isVisible = state.showRoots
            navigation.root.isVisible = !state.showRoots
            navigation.parent.isEnabled = state.canGoUp
            back.isEnabled = state.source != null
            crumbs.submitList(state.breadcrumbs.map { TextChoice(it.path, it.label, it.path == state.path) }) {
                if (navigation.breadcrumbs.isAttachedToWindow && !state.showRoots && state.breadcrumbs.isNotEmpty() &&
                    vm.ui.value.source == state.source && vm.ui.value.path == state.path) {
                    navigation.breadcrumbs.scrollToPosition(state.breadcrumbs.lastIndex)
                }
            }
            binding.progress.isVisible = state.loading
            binding.retry.isVisible = state.failed && state.source != null && !state.canRequestStorageAccess
            binding.grantStorage.isVisible = state.canRequestStorageAccess
            binding.actions.isVisible = binding.retry.isVisible || binding.grantStorage.isVisible
            navigation.manage.isVisible = state.source?.isReadOnly == false
            binding.status.isVisible = state.failed || state.recovered || if (state.showRoots) state.sources.isEmpty() else state.files.isEmpty()
            binding.status.setText(when { state.loading -> D.string.ui_loading; state.canRequestStorageAccess -> R.string.browse_file_permission;
                state.accessDenied -> R.string.browse_access_required;
                state.failed -> R.string.browse_unavailable; state.recovered -> D.string.ui_directory_recovered;
                state.source == null -> R.string.browse_no_storage; else -> D.string.ui_empty })
            val fileList = binding.files
            rows.submitList(if (state.showRoots) state.sources.map {
                val icon = when (it.type) {
                    com.flytech.juying.core.model.SourceType.LOCAL -> D.drawable.ic_storage
                    com.flytech.juying.core.model.SourceType.SMB -> D.drawable.ic_server
                    else -> D.drawable.ic_files
                }
                MediaRow(it.id, it.name, getString(R.string.browse_open_storage), icon)
            }
            else state.files.map { MediaRow(it.path, it.name,
                if (it.isDirectory) getString(R.string.browse_open_folder) else if (it.isVideo) getString(R.string.browse_play_file,
                    if (it.size > 0) Formatter.formatFileSize(requireContext(), it.size) else getString(D.string.ui_file_unknown))
                else getString(R.string.browse_file_info),
                if (it.isDirectory) D.drawable.ic_files else if (it.isVideo) D.drawable.ic_film else R.drawable.ic_document) }) {
                if (!fileList.isAttachedToWindow || vm.ui.value.source != state.source || vm.ui.value.path != state.path || vm.ui.value.showRoots != state.showRoots) return@submitList
                if (!state.loading) state.source?.let { source ->
                    val index = memory.get(source.id, "scroll.${state.path}").toIntOrNull() ?: 0
                    manager.scrollToPosition(index.coerceIn(0, (state.files.size - 1).coerceAtLeast(0)))
                }
            }
        } }
    }
    override fun onResume() {
        super.onResume()
        if (vm.ui.value.canRequestStorageAccess) vm.retry()
    }
    override fun onStart() {
        super.onStart()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_MEDIA_MOUNTED)
            addAction(Intent.ACTION_MEDIA_UNMOUNTED)
            addAction(Intent.ACTION_MEDIA_REMOVED)
            addAction(Intent.ACTION_MEDIA_BAD_REMOVAL)
            addDataScheme("file")
        }
        ContextCompat.registerReceiver(requireContext(), storageChanges, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
    }
    override fun onStop() {
        requireContext().unregisterReceiver(storageChanges)
        super.onStop()
    }
    override fun onDestroyView() {
        vm.ui.value.source?.let { source ->
            memory.put(source.id, "scroll.${vm.ui.value.path}", (binding.files.layoutManager as LinearLayoutManager).findFirstVisibleItemPosition().toString())
        }
        binding.files.adapter = null; binding.directoryNavigation.breadcrumbs.adapter = null; super.onDestroyView()
    }
}
