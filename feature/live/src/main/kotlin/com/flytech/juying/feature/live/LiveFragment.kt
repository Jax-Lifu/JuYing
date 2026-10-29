package com.flytech.juying.feature.live

import android.os.Bundle
import android.view.View
import androidx.core.view.isVisible
import androidx.fragment.app.viewModels
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.flytech.juying.core.data.LiveRepository
import com.flytech.juying.core.data.SourceBrowseMemory
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.core.ui.loadImage
import com.flytech.juying.feature.live.databinding.FragmentLiveBinding
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date
import com.flytech.juying.core.designsystem.R as D

/** 直播页面 Fragment，支持三端形态分流与遥控器换台。 */
@AndroidEntryPoint
class LiveFragment : ViewBindingFragment<FragmentLiveBinding>(FragmentLiveBinding::inflate) {
    private val vm: LiveViewModel by viewModels()
    @Inject lateinit var navigator: Navigator
    @Inject lateinit var sources: SourceRepository
    @Inject lateinit var live: LiveRepository
    @Inject lateinit var memory: SourceBrowseMemory
    private var preview: Channel? = null
    private var previewSource: String? = null
    private var epgJob: Job? = null
    private var restoredList: String? = null
    private val groupAdapter = GroupAdapter { index ->
        savePosition()
        vm.selectGroup(index)
        vm.uiState.value.sourceId?.let { memory.put(it, "group", index.toString()) }
    }
    private val channelAdapter = ChannelAdapter(::preview, ::play)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        binding.groups.apply { adapter = groupAdapter; itemAnimator = null }
        binding.channels.apply { adapter = channelAdapter; itemAnimator = null; setItemViewCacheSize(8) }
        binding.play.setOnClickListener { preview?.let(::play) }
        binding.retry.setOnClickListener { vm.uiState.value.sourceId?.let { vm.load(it, vm.uiState.value.selectedGroup) } ?: navigator.openSourceSettings(this) }
        launchOnStarted { combine(sources.observeSources(SourceCapability.LIVE), memory.updates) { configs, _ -> configs }.collect { configs ->
            val selected = configs.firstOrNull { it.id == memory.selected(SourceCapability.LIVE) } ?: configs.firstOrNull()
            if (selected != null) {
                if (vm.uiState.value.sourceId != selected.id) {
                    savePosition()
                    vm.load(selected.id, memory.get(selected.id, "group").toIntOrNull() ?: 0)
                }
                memory.select(selected.id, SourceCapability.LIVE)
            }
        } }
        launchOnStarted { vm.uiState.collect(::render) }
    }
    private fun play(channel: Channel) {
        val sourceId = vm.uiState.value.sourceId ?: return
        memory.put(sourceId, "channel", channel.id)
        navigator.openPlayer(requireContext(), PlayRequest(PlayKind.LIVE, sourceId, channel.id, channel.name, mapOf("cover" to channel.logo.orEmpty())))
    }
    private fun preview(channel: Channel) {
        val sourceId = vm.uiState.value.sourceId ?: return
        if (preview == channel && previewSource == sourceId) return
        preview = channel; previewSource = sourceId
        binding.channels.post { channelAdapter.select(channel.id) }
        memory.put(sourceId, "channel", channel.id)
        memory.put(sourceId, "location", channel.name)
        binding.previewLogo.loadImage(channel.logo, 512, D.drawable.ic_live)
        binding.previewName.text = channel.name
        binding.epg.setText(D.string.ui_no_epg)
        epgJob?.cancel()
        epgJob = viewLifecycleOwner.lifecycleScope.launch {
            delay(EPG_FOCUS_DELAY_MS)
            try {
                val programmes = live.epg(sourceId, channel.id).filter { it.endMs > System.currentTimeMillis() }.take(4)
                binding.epg.text = programmes.joinToString("\n") { DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(it.startMs)) + "  " + it.title }
                    .ifEmpty { getString(D.string.ui_no_epg) }
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { binding.epg.setText(D.string.ui_no_epg) }
        }
    }
    private fun render(s: LiveUiState) {
        binding.progress.isVisible = s.loading
        binding.error.isVisible = s.error != null || (!s.loading && s.groups.isEmpty())
        binding.error.setText(if (s.error != null) D.string.ui_failed else D.string.ui_empty)
        binding.retry.isVisible = s.error != null
        groupAdapter.submit(s.groups.map { it.name }, s.selectedGroup)
        binding.groups.isVisible = s.groups.size > 1
        val channels = s.groups.getOrNull(s.selectedGroup)?.channels.orEmpty()
        binding.channelCount.text = getString(D.string.ui_channel_count, channels.size)
        val listKey = "${s.sourceId}:${s.selectedGroup}"
        val channelList = binding.channels
        channelAdapter.submitList(channels) {
            val current = vm.uiState.value
            if (!channelList.isAttachedToWindow || channelList.adapter !== channelAdapter ||
                current.sourceId != s.sourceId || current.selectedGroup != s.selectedGroup) return@submitList
            if (channels.isNotEmpty() && restoredList != listKey) {
                restoredList = listKey
                val saved = s.sourceId?.let { memory.get(it, "live-scroll.${s.selectedGroup}").toIntOrNull() } ?: 0
                (channelList.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(saved.coerceIn(channels.indices), 0)
            }
        }
        if (channels.none { it.id == preview?.id } || previewSource != s.sourceId) {
            (channels.firstOrNull { it.id == s.sourceId?.let { id -> memory.get(id, "channel") } } ?: channels.firstOrNull())?.let(::preview)
        }
        binding.play.isEnabled = channels.isNotEmpty()
        if (channels.isEmpty() && !s.loading) {
            epgJob?.cancel(); preview = null; previewSource = null
            binding.previewLogo.loadImage(null)
            binding.previewName.text = ""
            binding.epg.setText(D.string.ui_no_epg)
        }
    }
    private fun savePosition() {
        vm.uiState.value.sourceId?.let {
            memory.put(it, "live-scroll.${vm.uiState.value.selectedGroup}",
                (binding.channels.layoutManager as LinearLayoutManager).findFirstVisibleItemPosition().coerceAtLeast(0).toString())
        }
    }
    override fun onDestroyView() {
        savePosition(); restoredList = null
        epgJob?.cancel(); preview = null; previewSource = null
        binding.groups.adapter = null; binding.channels.adapter = null; super.onDestroyView()
    }

    private companion object { const val EPG_FOCUS_DELAY_MS = 150L }
}
