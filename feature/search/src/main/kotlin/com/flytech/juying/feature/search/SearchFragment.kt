package com.flytech.juying.feature.search

import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatButton
import androidx.core.content.getSystemService
import androidx.core.view.isVisible
import androidx.core.widget.doAfterTextChanged
import androidx.fragment.app.viewModels
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.flytech.juying.core.model.SearchOutcome
import com.flytech.juying.core.ui.FocusTarget
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.core.ui.VodPosterAdapter
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.feature.search.databinding.FragmentSearchBinding
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import com.flytech.juying.core.designsystem.R as DesignR

/** 全源聚合搜索界面 Fragment，支持拼音首字母模糊联想与跨源增量检索，深度优化 TV 遥控体验。 */
@AndroidEntryPoint
class SearchFragment : ViewBindingFragment<FragmentSearchBinding>(FragmentSearchBinding::inflate), FocusTarget {
    private val vm: SearchViewModel by viewModels()
    @Inject lateinit var navigator: Navigator

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val posters = VodPosterAdapter { navigator.openVodDetail(this, it.sourceId, it.id) }
        binding.posters.apply {
            layoutManager = GridLayoutManager(context, resources.getInteger(DesignR.integer.jy_vod_columns))
            adapter = posters
            itemAnimator = null
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    val grid = recyclerView.layoutManager as GridLayoutManager
                    // 只随用户向下滚动追加，避免布局刷新触发连续翻页。
                    if (dy > 0 && grid.findLastVisibleItemPosition() >= grid.itemCount - grid.spanCount * 2) vm.more()
                }
            })
        }

        binding.query.setText(vm.ui.value.keyword)
        binding.back.setOnClickListener { findNavController().popBackStack() }
        binding.submit.setOnClickListener { submit() }
        binding.query.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_SEARCH) {
                submit()
                true
            } else false
        }

        // 监听输入框文字变化触发拼音首字母/简拼（如 wwd -> 汪汪队立大功）与关键词实时联想
        binding.query.doAfterTextChanged { text ->
            vm.queryChanged(text?.toString().orEmpty())
        }

        // TV 遥控器方向键支持：向下优先进入联想词条，没有联想词条直达海报结果区或重试区
        binding.query.setOnKeyListener { _, keyCode, event ->
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_DOWN -> {
                        if (binding.suggestScroll.isVisible && binding.suggestContainer.childCount > 0) {
                            binding.suggestContainer.getChildAt(0).requestFocus()
                            true
                        } else if (binding.retry.isVisible) {
                            binding.retry.requestFocus()
                            true
                        } else {
                            val first = binding.posters.findViewHolderForAdapterPosition(0)?.itemView
                                ?: binding.posters.getChildAt(0)
                            if (first != null) {
                                first.requestFocus()
                                true
                            } else false
                        }
                    }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        if (binding.query.selectionEnd == binding.query.text?.length) {
                            binding.submit.requestFocus()
                            true
                        } else false
                    }
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        if (binding.query.selectionStart == 0) {
                            binding.back.requestFocus()
                            true
                        } else false
                    }
                    else -> false
                }
            } else false
        }

        binding.retry.setOnClickListener { vm.retry() }
        binding.more.setOnClickListener { vm.more() }

        launchOnStarted {
            vm.ui.collect { state ->
                val hasKeyword = state.keyword.isNotEmpty()
                val hasPosters = state.posters.isNotEmpty()
                val isSearching = state.loading

                binding.progress.isVisible = isSearching
                binding.status.isVisible = hasKeyword
                binding.status.text = if (!hasKeyword) ""
                else {
                    val failures = state.targets.mapNotNull { (target, outcome) ->
                        val label = when (outcome) {
                            SearchOutcome.FAILED -> R.string.search_failed_label
                            SearchOutcome.TIMED_OUT -> R.string.search_timeout_label
                            else -> return@mapNotNull null
                        }
                        "${target.label} (${getString(label)})"
                    }
                    listOfNotNull(
                        getString(R.string.search_progress, state.targets.values.count { it != null }, state.targets.size, state.posters.size),
                        failures.takeIf { it.isNotEmpty() }?.let { getString(R.string.search_failures, it.joinToString("、")) },
                    ).joinToString("\n")
                }
                binding.retry.isVisible = state.failed && !isSearching
                binding.more.isVisible = hasPosters && state.hasMore && !state.failed
                binding.more.isEnabled = !isSearching
                binding.retry.nextFocusUpId = if (hasPosters) binding.posters.id else binding.query.id
                binding.more.nextFocusUpId = binding.retry.nextFocusUpId

                renderSuggestions(state.suggestions)

                if (hasPosters) {
                    binding.posters.isVisible = true
                    binding.emptyContainer.isVisible = false
                } else if (!isSearching && hasKeyword) {
                    binding.posters.isVisible = false
                    binding.emptyContainer.isVisible = true
                    val someFailed = state.targets.values.any { it == SearchOutcome.FAILED || it == SearchOutcome.TIMED_OUT }
                    if (someFailed) {
                        binding.emptyTitle.text = getString(R.string.search_empty)
                        binding.emptySubtext.text = getString(R.string.search_empty_failed)
                    } else {
                        binding.emptyTitle.text = getString(R.string.search_empty)
                        binding.emptySubtext.text = getString(R.string.search_empty_hint)
                    }
                } else {
                    binding.posters.isVisible = true
                    binding.emptyContainer.isVisible = false
                }

                posters.submitList(state.posters) {
                    if (isResumed && !binding.root.hasFocus()) {
                        requestPrimaryFocus()
                    }
                }
            }
        }

        view.post {
            if (isResumed && !binding.root.hasFocus()) {
                requestPrimaryFocus()
            }
        }
    }

    private fun renderSuggestions(suggestions: List<String>) {
        val show = suggestions.isNotEmpty()
        binding.suggestScroll.isVisible = show
        binding.suggestContainer.removeAllViews()
        if (!show) return

        val dp8 = (8 * resources.displayMetrics.density).toInt()
        val dp12 = (12 * resources.displayMetrics.density).toInt()
        val dp16 = (16 * resources.displayMetrics.density).toInt()

        for (word in suggestions) {
            val btn = AppCompatButton(requireContext()).apply {
                text = word
                setTextAppearance(DesignR.style.JyAction)
                setBackgroundResource(DesignR.drawable.bg_toolbar_action)
                setPadding(dp16, dp8, dp16, dp8)
                isFocusable = true
                isClickable = true
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    marginEnd = dp12
                }
                setOnClickListener {
                    binding.query.setText(word)
                    submit()
                }
                setOnKeyListener { _, keyCode, event ->
                    if (event.action == KeyEvent.ACTION_DOWN) {
                        when (keyCode) {
                            KeyEvent.KEYCODE_DPAD_UP -> {
                                binding.query.requestFocus()
                                true
                            }
                            KeyEvent.KEYCODE_DPAD_DOWN -> {
                                val first = binding.posters.findViewHolderForAdapterPosition(0)?.itemView
                                    ?: binding.posters.getChildAt(0)
                                if (first != null) {
                                    first.requestFocus()
                                    true
                                } else false
                            }
                            else -> false
                        }
                    } else false
                }
            }
            binding.suggestContainer.addView(btn)
        }
    }

    override fun requestPrimaryFocus(): Boolean {
        return if (binding.query.text.isNullOrBlank()) {
            binding.query.requestFocus()
        } else if (binding.retry.isVisible) {
            binding.retry.requestFocus()
        } else {
            val first = binding.posters.findViewHolderForAdapterPosition(0)?.itemView
                ?: binding.posters.getChildAt(0)
            first?.requestFocus() ?: binding.query.requestFocus()
        }
    }

    private fun submit() {
        val kw = binding.query.text?.toString()?.trim().orEmpty()
        if (kw.isEmpty()) return
        vm.search(kw)
        requireContext().getSystemService<InputMethodManager>()?.hideSoftInputFromWindow(binding.query.windowToken, 0)
        binding.submit.requestFocus()
    }

    override fun onDestroyView() {
        binding.posters.adapter = null
        super.onDestroyView()
    }
}
