package com.flytech.juying.core.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.viewbinding.ViewBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** 统一在 onDestroyView 释放 binding，避免 Fragment 持有整棵 View 树造成内存泄漏（低配机重点）。 */
abstract class ViewBindingFragment<VB : ViewBinding>(
    private val inflate: (LayoutInflater, ViewGroup?, Boolean) -> VB,
) : Fragment() {

    private var _binding: VB? = null
    protected val binding: VB get() = checkNotNull(_binding) { "binding 仅在 onCreateView~onDestroyView 间可用" }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View =
        inflate(inflater, container, false).also { _binding = it }.root

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
    }

    /** 仅在界面可见（STARTED）时收集 Flow，后台自动停止。 */
    protected fun launchOnStarted(block: suspend CoroutineScope.() -> Unit) {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED, block)
        }
    }
}
