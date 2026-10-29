package com.flytech.juying.feature.settings

import android.os.Bundle
import android.view.View
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.navigation.fragment.findNavController
import androidx.activity.OnBackPressedCallback
import com.flytech.juying.core.ui.NavigationGuard
import com.flytech.juying.core.designsystem.R as D
import androidx.core.view.isVisible
import androidx.core.widget.doAfterTextChanged
import androidx.fragment.app.viewModels
import androidx.recyclerview.widget.LinearLayoutManager
import com.flytech.juying.core.ui.TextChoice
import com.flytech.juying.core.ui.TextChoiceAdapter
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.feature.settings.databinding.FragmentSettingsBinding
import dagger.hilt.android.AndroidEntryPoint

/** 播放源管理与系统设置 Fragment。 */
@AndroidEntryPoint
class SettingsFragment : ViewBindingFragment<FragmentSettingsBinding>(FragmentSettingsBinding::inflate), NavigationGuard {
    private val vm: SettingsViewModel by viewModels()
    private var rendering = false
    private var openedConnection = false
    private val openFile = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) viewLifecycleOwner.lifecycleScope.launch {
            try {
                val name = withContext(Dispatchers.IO) {
                    requireContext().contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                        if (it.moveToFirst()) it.getString(0) else null
                    } ?: uri.lastPathSegment.orEmpty()
                }
                vm.selectFile(uri.toString(), name)
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (_: Exception) { vm.fileFailed() }
        }
    }
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val sources = TextChoiceAdapter { row ->
            val config = vm.ui.value.sources.firstOrNull { it.id == row.id }
            if (config != null && !config.isReadOnly && vm.setups.none { it.type == config.type }) {
                MaterialAlertDialogBuilder(requireContext()).setTitle(config.name)
                    .setItems(arrayOf(getString(if (config.enabled) R.string.sources_disable else R.string.sources_enable), getString(D.string.ui_delete))) { _, index ->
                        if (index == 0) vm.toggleSource(config) else MaterialAlertDialogBuilder(requireContext())
                            .setMessage(D.string.ui_delete_confirm).setPositiveButton(D.string.ui_delete) { _, _ -> vm.removeSource(config.id) }
                            .setNegativeButton(D.string.ui_cancel, null).show()
                    }.show()
            } else if (config?.isReadOnly == true || vm.setups.none { it.type == config?.type })
                MaterialAlertDialogBuilder(requireContext()).setTitle(config?.name).setMessage(if (config?.isReadOnly == true) D.string.ui_builtin else D.string.ui_unsupported)
                    .setPositiveButton(D.string.ui_close, null).show()
            else vm.edit(row.id)
        }
        val back = object : OnBackPressedCallback(false) { override fun handleOnBackPressed() { confirmLeave { vm.cancel() } } }
        requireActivity().onBackPressedDispatcher.addCallback(viewLifecycleOwner, back)
        binding.back.setOnClickListener { confirmLeave { findNavController().popBackStack() } }
        binding.sources.apply {
            layoutManager = LinearLayoutManager(context)
            adapter = sources
            itemAnimator = null
        }
        binding.add.setOnClickListener {
            if (vm.setups.size == 1) vm.add(vm.setups.single()) else
                MaterialAlertDialogBuilder(requireContext()).setTitle(R.string.sources_add)
                    .setItems(vm.setups.map { it.name }.toTypedArray()) { _, index -> vm.add(vm.setups[index]) }.show()
        }
        binding.name.doAfterTextChanged { change() }
        binding.url.doAfterTextChanged { change() }
        binding.username.doAfterTextChanged { change() }
        binding.password.doAfterTextChanged { change() }
        binding.epgUrl.doAfterTextChanged { change() }
        binding.userAgent.doAfterTextChanged { change() }
        binding.referer.doAfterTextChanged { change() }
        binding.importFile.setOnClickListener {
            try { openFile.launch(vm.ui.value.editor?.setup?.fileMimeTypes.orEmpty().toTypedArray()) }
            catch (_: android.content.ActivityNotFoundException) { vm.fileFailed() }
        }
        binding.check.setOnClickListener { vm.check() }
        binding.enabled.setOnCheckedChangeListener { _, _ -> change() }
        binding.save.setOnClickListener { vm.save() }
        binding.cancel.setOnClickListener { confirmLeave { vm.cancel() } }
        binding.delete.setOnClickListener { MaterialAlertDialogBuilder(requireContext()).setMessage(D.string.ui_delete_confirm)
            .setPositiveButton(D.string.ui_delete) { _, _ -> vm.delete() }.setNegativeButton(D.string.ui_cancel, null).show() }
        launchOnStarted { vm.ui.collect { state ->
            val editId = arguments?.getString("editSourceId")
            if (editId != null && !openedConnection && state.sources.any { it.id == editId }) {
                openedConnection = true
                if (vm.setups.any { it.type == state.sources.first { source -> source.id == editId }.type }) {
                    vm.edit(editId); return@collect
                }
            }
            if (editId != null && state.message == SourceFormMessage.SAVED) {
                findNavController().popBackStack(); return@collect
            }
            rendering = true
            val busy = state.saving || state.checking
            back.isEnabled = state.editor != null
            binding.add.isEnabled = vm.setups.isNotEmpty() && !busy && state.editor == null
            binding.delete.isVisible = state.editor?.existing != null
            binding.delete.isEnabled = !busy
            binding.username.isVisible = state.editor?.setup?.credentials == true
            binding.password.isVisible = state.editor?.setup?.credentials == true
            binding.username.isEnabled = !busy; binding.password.isEnabled = !busy
            binding.importFile.isVisible = state.editor?.setup?.fileMimeTypes?.isNotEmpty() == true
            binding.importFile.isEnabled = !busy
            binding.check.isEnabled = !busy
            binding.epgUrl.isVisible = state.editor?.setup?.epg == true
            binding.userAgent.isVisible = state.editor?.setup?.epg == true
            binding.referer.isVisible = state.editor?.setup?.epg == true
            binding.epgUrl.isEnabled = !busy; binding.userAgent.isEnabled = !busy; binding.referer.isEnabled = !busy
            binding.sources.isVisible = state.editor == null
            binding.editor.isVisible = state.editor != null
            state.editor?.let { editor ->
                binding.description.text = editor.setup.description
                if (binding.name.text.toString() != editor.name) binding.name.setText(editor.name)
                if (binding.url.text.toString() != editor.url) binding.url.setText(editor.url)
                binding.enabled.isChecked = editor.enabled
                if (binding.username.text.toString() != editor.username) binding.username.setText(editor.username)
                if (binding.password.text.toString() != editor.password) binding.password.setText(editor.password)
                if (binding.epgUrl.text.toString() != editor.epgUrl) binding.epgUrl.setText(editor.epgUrl)
                if (binding.userAgent.text.toString() != editor.userAgent) binding.userAgent.setText(editor.userAgent)
                if (binding.referer.text.toString() != editor.referer) binding.referer.setText(editor.referer)
            }
            binding.save.isEnabled = !busy
            binding.cancel.isEnabled = !state.saving
            binding.name.isEnabled = !busy
            binding.url.isEnabled = !busy
            binding.enabled.isEnabled = !busy
            binding.status.isVisible = state.message != SourceFormMessage.NONE || busy
            binding.status.text = if (state.checking) getString(R.string.sources_checking) else if (state.saving) getString(D.string.ui_loading) else when (state.message) {
                SourceFormMessage.NONE -> ""
                SourceFormMessage.INVALID_NAME -> getString(R.string.sources_invalid_name)
                SourceFormMessage.INVALID_URL -> getString(R.string.sources_invalid_url)
                SourceFormMessage.SAVED -> getString(R.string.sources_saved)
                SourceFormMessage.FAILED -> getString(R.string.sources_failed)
                SourceFormMessage.INVALID_EPG -> getString(R.string.sources_invalid_epg)
                SourceFormMessage.CHECKED -> getString(R.string.sources_checked, state.checkedCount)
                SourceFormMessage.CHECK_EMPTY -> getString(R.string.sources_check_empty)
                SourceFormMessage.CHECK_FAILED -> getString(R.string.sources_check_failed)
                SourceFormMessage.CHECK_TIMEOUT -> getString(R.string.sources_check_timeout)
                SourceFormMessage.FILE_FAILED -> getString(R.string.sources_file_failed)
            }
            sources.submitList(state.sources.map { config -> TextChoice(config.id, when {
                config.isReadOnly -> getString(R.string.sources_builtin, config.name)
                !config.enabled -> getString(R.string.sources_disabled, config.name)
                else -> config.name
            }) })
            rendering = false
        } }
    }
    private fun change() {
        if (!rendering) vm.change(binding.name.text.toString(), binding.url.text.toString(), binding.enabled.isChecked, binding.username.text.toString(), binding.password.text.toString(),
            binding.epgUrl.text.toString(), binding.userAgent.text.toString(), binding.referer.text.toString())
    }
    override fun confirmLeave(proceed: () -> Unit) {
        if (vm.ui.value.saving) return
        if (vm.ui.value.editor?.dirty != true) { proceed(); return }
        MaterialAlertDialogBuilder(requireContext()).setTitle(D.string.ui_unsaved)
            .setNegativeButton(D.string.ui_discard) { _, _ -> vm.cancel(); proceed() }
            .setPositiveButton(D.string.ui_keep_editing, null).show().getButton(android.app.AlertDialog.BUTTON_POSITIVE).requestFocus()
    }
    override fun onDestroyView() {
        binding.sources.adapter = null
        super.onDestroyView()
    }
}
