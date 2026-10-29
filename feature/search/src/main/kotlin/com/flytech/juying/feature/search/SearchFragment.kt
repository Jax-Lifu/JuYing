package com.flytech.juying.feature.search

import android.os.Bundle
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.core.content.getSystemService
import androidx.core.view.isVisible
import androidx.fragment.app.viewModels
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.GridLayoutManager
import com.flytech.juying.core.model.SearchOutcome
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.core.ui.VodPosterAdapter
import javax.inject.Inject
import com.flytech.juying.core.designsystem.R as DesignR
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.feature.search.databinding.FragmentSearchBinding
import dagger.hilt.android.AndroidEntryPoint

/** 全源聚合搜索界面 Fragment，支持增量加载与快速检索。 */
@AndroidEntryPoint
class SearchFragment : ViewBindingFragment<FragmentSearchBinding>(FragmentSearchBinding::inflate) {
    private val vm: SearchViewModel by viewModels()
    @Inject lateinit var navigator: Navigator
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val posters = VodPosterAdapter { navigator.openVodDetail(this, it.sourceId, it.id) }
        binding.posters.apply {
            layoutManager = GridLayoutManager(context, resources.getInteger(DesignR.integer.jy_vod_columns))
            adapter = posters
            itemAnimator = null
        }
        binding.query.setText(vm.ui.value.keyword)
        binding.back.setOnClickListener { findNavController().popBackStack() }
        binding.submit.setOnClickListener { submit() }
        binding.query.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_SEARCH) { submit(); true } else false
        }
        binding.retry.setOnClickListener { vm.retry() }
        binding.more.setOnClickListener { vm.more() }
        launchOnStarted { vm.ui.collect { state ->
            binding.progress.isVisible = state.loading
            binding.status.isVisible = state.keyword.isNotEmpty()
            binding.status.text = if (state.keyword.isEmpty()) ""
                else getString(R.string.search_progress, state.targets.values.count { it != null }, state.targets.size, state.posters.size)
            val failures = state.targets.filterValues { it == SearchOutcome.FAILED || it == SearchOutcome.TIMED_OUT }
            binding.failures.isVisible = state.failed || failures.isNotEmpty()
            binding.failures.text = if (failures.isEmpty()) getString(DesignR.string.content_failed) else
                getString(R.string.search_failures, failures.entries.joinToString("；") { (target, result) ->
                    target.label + "（" + getString(if (result == SearchOutcome.TIMED_OUT) R.string.search_timeout_label else R.string.search_failed_label) + "）"
                })
            binding.retry.isVisible = state.failed && !state.loading
            binding.more.isVisible = state.hasMore
            binding.more.isEnabled = !state.loading
            posters.submitList(state.posters)
        } }
    }
    private fun submit() {
        vm.search(binding.query.text.toString())
        requireContext().getSystemService<InputMethodManager>()?.hideSoftInputFromWindow(binding.query.windowToken, 0)
        binding.submit.requestFocus()
    }
    override fun onDestroyView() {
        binding.posters.adapter = null
        super.onDestroyView()
    }
}
