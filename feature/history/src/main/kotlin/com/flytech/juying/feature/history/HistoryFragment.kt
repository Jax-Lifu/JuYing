package com.flytech.juying.feature.history

import android.os.Bundle
import android.view.View
import androidx.core.view.isVisible
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.GridLayoutManager
import com.flytech.juying.core.data.FavoriteRepository
import com.flytech.juying.core.data.HistoryRepository
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.ui.CoverCard
import com.flytech.juying.core.ui.CoverCardAdapter
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.feature.history.databinding.FragmentHistoryBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date
import com.flytech.juying.core.designsystem.R as D

/** 播放历史与继续观看列表 Fragment。 */
@AndroidEntryPoint
class HistoryFragment : ViewBindingFragment<FragmentHistoryBinding>(FragmentHistoryBinding::inflate) {
    @Inject lateinit var history: HistoryRepository
    @Inject lateinit var favorites: FavoriteRepository
    @Inject lateinit var sources: SourceRepository
    @Inject lateinit var navigator: Navigator
    private val showFavorites = MutableStateFlow(false)
    private var requests = emptyMap<String, PlayRequest>()
    private var available = emptySet<String>()
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        showFavorites.value = savedInstanceState?.getBoolean("favorites") ?: false
        val rows = CoverCardAdapter(onClick = { row -> requests[row.id]?.let {
            if (it.sourceId in available) {
                if (showFavorites.value && it.kind == PlayKind.VOD) navigator.openVodDetail(this, it.sourceId, it.ref)
                else navigator.openPlayer(requireContext(), it)
            } else MaterialAlertDialogBuilder(requireContext()).setMessage(D.string.ui_source_missing)
                .setPositiveButton(D.string.ui_manage) { _, _ -> navigator.openSourceSettings(this) }.setNegativeButton(D.string.ui_close, null).show()
        } }, onLongClick = { row ->
            MaterialAlertDialogBuilder(requireContext()).setTitle(row.title).setMessage(D.string.ui_remove_record)
                .setPositiveButton(D.string.ui_remove) { _, _ -> viewLifecycleOwner.lifecycleScope.launch {
                    if (showFavorites.value) favorites.delete(row.id) else history.delete(row.id)
                } }.setNegativeButton(D.string.ui_cancel, null).show()
        })
        binding.entries.apply { layoutManager = GridLayoutManager(context, if (resources.getBoolean(D.bool.jy_wide)) 3 else 1); adapter = rows; itemAnimator = null }
        binding.back.setOnClickListener { findNavController().popBackStack() }
        binding.recent.setOnClickListener { showFavorites.value = false }
        binding.favorites.setOnClickListener { showFavorites.value = true }
        binding.clear.setOnClickListener { MaterialAlertDialogBuilder(requireContext()).setMessage(D.string.ui_clear_confirm)
            .setPositiveButton(D.string.ui_clear) { _, _ -> viewLifecycleOwner.lifecycleScope.launch { history.clear() } }.setNegativeButton(D.string.ui_cancel, null).show() }
        launchOnStarted {
            combine(history.observeRecent(200), favorites.observeAll(), sources.observeSources(), showFavorites) { recent, saved, configs, favorite ->
                available = configs.filter { it.enabled }.map { it.id }.toSet()
                val names = configs.associate { it.id to it.name }
                requests = if (favorite) saved.associate { it.id to PlayRequest(it.kind, it.sourceId, it.ref, it.title) }
                    else recent.associate { it.id to PlayRequest(it.kind, it.sourceId, it.ref, it.title, it.extra) }
                if (favorite) saved.map { CoverCard(it.id, it.title, names[it.sourceId] ?: getString(D.string.ui_source_missing), it.cover, isLogo = it.kind == PlayKind.LIVE) }
                else recent.map { CoverCard(it.id, it.title,
                    (names[it.sourceId] ?: getString(D.string.ui_source_missing)) + " · " +
                        if (it.kind == PlayKind.LIVE) getString(D.string.ui_live_return) else DateFormat.getDateInstance().format(Date(it.updatedAt)), it.cover,
                    if (it.kind != PlayKind.LIVE && it.durationMs > 0) (it.positionMs * 1000 / it.durationMs).toInt().coerceIn(0, 1000) else null,
                    isLogo = it.kind == PlayKind.LIVE) }
            }.collect { cards ->
                rows.submitList(cards)
                binding.empty.isVisible = cards.isEmpty()
                binding.empty.setText(if (showFavorites.value) D.string.ui_no_favorites else D.string.ui_no_history)
                binding.clear.isVisible = !showFavorites.value; binding.clear.isEnabled = cards.isNotEmpty()
                binding.recent.isSelected = !showFavorites.value; binding.favorites.isSelected = showFavorites.value
            }
        }
    }
    override fun onSaveInstanceState(outState: Bundle) { outState.putBoolean("favorites", showFavorites.value); super.onSaveInstanceState(outState) }
    override fun onDestroyView() { binding.entries.adapter = null; super.onDestroyView() }
}
