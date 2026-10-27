package com.flytech.juying.feature.home

import android.os.Bundle
import android.view.View
import androidx.core.view.isVisible
import androidx.fragment.app.viewModels
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import com.flytech.juying.core.data.HistoryRepository
import com.flytech.juying.core.data.LiveRepository
import com.flytech.juying.core.data.SourceBrowseMemory
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.HistoryEntry
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.ui.MediaRow
import com.flytech.juying.core.ui.MediaRowAdapter
import com.flytech.juying.core.ui.CoverCard
import com.flytech.juying.core.ui.CoverCardAdapter
import com.flytech.juying.core.ui.VodPoster
import com.flytech.juying.core.ui.VodPosterAdapter
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.feature.home.databinding.FragmentHomeBinding
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.lastOrNull
import kotlinx.coroutines.CancellationException
import com.flytech.juying.core.designsystem.R as D

@AndroidEntryPoint
class HomeFragment : ViewBindingFragment<FragmentHomeBinding>(FragmentHomeBinding::inflate) {
    private val vm: HomeViewModel by viewModels()
    @Inject lateinit var history: HistoryRepository
    @Inject lateinit var live: LiveRepository
    @Inject lateinit var sources: SourceRepository
    @Inject lateinit var memory: SourceBrowseMemory
    @Inject lateinit var navigator: Navigator
    private var recent = emptyList<HistoryEntry>()
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val recommendationAdapter = VodPosterAdapter(carousel = true) { navigator.openVodDetail(this, it.sourceId, it.id) }
        val historyAdapter = CoverCardAdapter(carousel = true, onClick = { row -> recent.firstOrNull { it.id == row.id }?.let(::play) })
        val sourceAdapter = MediaRowAdapter({ navigator.openSource(requireActivity(), it.id) })
        binding.recommendations.apply { layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false); adapter = recommendationAdapter; itemAnimator = null }
        binding.recent.apply { layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false); adapter = historyAdapter; itemAnimator = null }
        binding.sources.apply { layoutManager = GridLayoutManager(context, resources.getInteger(D.integer.jy_source_columns)); adapter = sourceAdapter; itemAnimator = null }
        binding.allHistory.setOnClickListener { navigator.openHistory(this) }
        binding.addSource.setOnClickListener { navigator.openSourceSettings(this) }
        binding.explore.setOnClickListener { navigator.openSources(this) }
        launchOnStarted { combine(sources.observeSources(SourceCapability.VOD), memory.updates) { configs, _ ->
            configs.firstOrNull { it.id == memory.selected(SourceCapability.VOD) } ?: configs.firstOrNull()
        }.collect { vm.load(it?.id) } }
        launchOnStarted { combine(history.observeRecent(4), sources.observeSources(), vm.recommendations) { entries, configs, items ->
            Triple(entries, configs, items)
        }.collectLatest { (entries, configs, items) ->
            recent = entries
            val names = configs.associate { it.id to it.name }
            binding.recentHeading.isVisible = entries.isNotEmpty()
            binding.empty.isVisible = entries.isEmpty()
            binding.recent.isVisible = entries.isNotEmpty()
            val recommendations = HomeViewModel.recommendationsFor(items, entries)
            binding.recommendationHeading.isVisible = recommendations.isNotEmpty()
            binding.recommendations.isVisible = recommendations.isNotEmpty()
            binding.recommendationEmpty.isVisible = recommendations.isEmpty()
            recommendations.firstOrNull()?.let {
                binding.recommendationHeading.text = getString(R.string.home_recommendation, names[it.sourceId].orEmpty())
            }
            recommendationAdapter.submitList(recommendations.map { VodPoster(it) })
            val cards = entries.map { CoverCard(it.id, it.title, (names[it.sourceId] ?: getString(D.string.ui_source_missing)) +
                if (it.kind == PlayKind.LIVE) " · " + getString(D.string.ui_live_return) else "", cover = it.cover,
                progress = if (it.kind != PlayKind.LIVE && it.durationMs > 0) (it.positionMs * 1000 / it.durationMs).toInt().coerceIn(0, 1000) else null,
                isLogo = it.kind == PlayKind.LIVE) }
            historyAdapter.submitList(cards)
            sourceAdapter.submitList(configs.filter { it.enabled }.sortedBy { config -> entries.indexOfFirst { it.sourceId == config.id }.takeIf { it >= 0 } ?: Int.MAX_VALUE }
                .take(6).map { config ->
                    val capabilities = sources.capabilities(config)
                    val labels = listOfNotNull(
                        getString(D.string.ui_live).takeIf { SourceCapability.LIVE in capabilities },
                        getString(D.string.ui_vod).takeIf { SourceCapability.VOD in capabilities },
                        getString(D.string.ui_files).takeIf { SourceCapability.BROWSE in capabilities },
                    )
                    val icon = when {
                        SourceCapability.VOD in capabilities -> D.drawable.ic_vod
                        SourceCapability.LIVE in capabilities -> D.drawable.ic_live
                        else -> D.drawable.ic_files
                    }
                    MediaRow(config.id, config.name, labels.joinToString(" · "), icon)
                })
            // 旧版频道缓存可能没有台标，等本次后台刷新完成；每个源最多查询一次。
            val logos = entries.filter { it.kind == PlayKind.LIVE && it.cover.isNullOrBlank() }
                .map { it.sourceId }.distinct().associateWith { sourceId ->
                    try { live.channelGroups(sourceId).lastOrNull().orEmpty().flatMap { it.channels }.associate { it.id to it.logo } }
                    catch (error: Exception) { if (error is CancellationException) throw error else emptyMap() }
                }
            val resolved = cards.mapIndexed { index, card ->
                val entry = entries[index]
                if (entry.kind != PlayKind.LIVE || !entry.cover.isNullOrBlank()) card else {
                    card.copy(cover = logos[entry.sourceId]?.get(entry.ref))
                }
            }
            if (resolved != cards) historyAdapter.submitList(resolved)
        } }
    }
    private fun play(entry: HistoryEntry) = navigator.openPlayer(requireContext(), PlayRequest(entry.kind, entry.sourceId, entry.ref, entry.title, entry.extra))
    override fun onDestroyView() { binding.recommendations.adapter = null; binding.recent.adapter = null; binding.sources.adapter = null; super.onDestroyView() }
}
