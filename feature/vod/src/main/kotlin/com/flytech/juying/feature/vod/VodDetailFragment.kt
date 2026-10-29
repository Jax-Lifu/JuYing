package com.flytech.juying.feature.vod

import android.os.Bundle
import android.text.Html
import android.view.View
import androidx.core.os.bundleOf
import androidx.core.view.isVisible
import androidx.fragment.app.viewModels
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.GridLayoutManager
import com.flytech.juying.core.data.FavoriteRepository
import com.flytech.juying.core.model.FavoriteEntry
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.ui.*
import com.flytech.juying.feature.vod.databinding.FragmentVodDetailBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.launch
import javax.inject.Inject
import com.flytech.juying.core.designsystem.R as DesignR

/** 点播详情与选集播放页 Fragment。 */
@AndroidEntryPoint
class VodDetailFragment : ViewBindingFragment<FragmentVodDetailBinding>(FragmentVodDetailBinding::inflate), FocusTarget {
    private val vm: VodDetailViewModel by viewModels()
    @Inject lateinit var navigator: Navigator
    @Inject lateinit var favorites: FavoriteRepository
    private var favorited = false

    override fun requestPrimaryFocus(): Boolean {
        return binding.play.takeIf { it.isEnabled && it.isVisible }?.requestFocus() == true ||
               binding.back.takeIf { it.isEnabled && it.isVisible }?.requestFocus() == true ||
               binding.episodes.findFirstFocusable()?.requestFocus() == true ||
               binding.root.findFirstFocusable()?.requestFocus() == true
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val episodes = MediaRowAdapter(onClick = { episode ->
            playEpisode(episode.id, episode.title)
        })
        binding.play.setOnClickListener {
            vm.ui.value.detail?.playGroups?.getOrNull(vm.ui.value.group)?.episodes?.firstOrNull()?.let { episode ->
                playEpisode(episode.ref, episode.name)
            }
        }
        binding.episodes.apply {
            layoutManager = GridLayoutManager(context, if (resources.getBoolean(DesignR.bool.jy_wide)) 4 else 2)
            adapter = episodes
            itemAnimator = null
        }
        binding.back.setOnClickListener { findNavController().popBackStack() }
        val radius = resources.getDimension(DesignR.dimen.jy_radius)
        val outline = object : android.view.ViewOutlineProvider() {
            override fun getOutline(view: android.view.View, outline: android.graphics.Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, radius)
            }
        }
        binding.coverCard.outlineProvider = outline
        binding.coverCard.clipToOutline = true
        binding.cover.outlineProvider = outline
        binding.cover.clipToOutline = true
        binding.retry.setOnClickListener { vm.reload() }
        binding.descriptionMore.setOnClickListener {
            MaterialAlertDialogBuilder(requireContext()).setTitle(binding.title.text).setMessage(binding.description.text)
                .setPositiveButton(DesignR.string.ui_close, null).show()
        }
        binding.favorite.setOnClickListener {
            vm.ui.value.detail?.item?.let { item -> viewLifecycleOwner.lifecycleScope.launch {
                val id = "${vm.sourceId}:${item.id}"
                if (favorited) favorites.delete(id) else favorites.upsert(FavoriteEntry(id, PlayKind.VOD, vm.sourceId, item.id, item.title, item.cover))
            } }
        }
        launchOnStarted { favorites.observeAll().collect { items ->
            favorited = items.any { it.sourceId == vm.sourceId && it.ref == requireArguments().getString(ITEM_ID) }
            binding.favorite.isSelected = favorited
            binding.favorite.setCompoundDrawablesRelativeWithIntrinsicBounds(if (favorited) DesignR.drawable.ic_favorite_filled else DesignR.drawable.ic_favorite, 0, 0, 0)
            binding.favorite.setText(if (favorited) DesignR.string.ui_favorited else DesignR.string.ui_favorite)
        } }
        binding.line.setOnClickListener {
            val groups = vm.ui.value.detail?.playGroups.orEmpty()
            MaterialAlertDialogBuilder(requireContext()).setTitle(DesignR.string.content_select_line)
                .setSingleChoiceItems(groups.map { it.name }.toTypedArray(), vm.ui.value.group) { dialog, index ->
                    vm.selectGroup(index)
                    dialog.dismiss()
                }.show()
        }
        launchOnStarted { vm.ui.collect { state ->
            val detail = state.detail
            val group = detail?.playGroups?.getOrNull(state.group)
            binding.cover.loadImage(detail?.item?.cover, 600)
            binding.cover.isVisible = true
            binding.favorite.isEnabled = detail != null
            binding.play.isEnabled = !group?.episodes.isNullOrEmpty()
            binding.title.text = detail?.item?.title
            binding.metadata.text = listOfNotNull(detail?.year, detail?.area, detail?.item?.remarks)
                .filter { it.isNotBlank() }.distinct().joinToString(" · ")
            binding.description.text = Html.fromHtml(detail?.description.orEmpty(), Html.FROM_HTML_MODE_COMPACT).toString()
            binding.description.isVisible = binding.description.text.isNotBlank()
            binding.descriptionMore.isVisible = binding.description.text.isNotBlank()
            binding.progress.isVisible = state.loading
            binding.retry.isVisible = state.failed
            binding.status.isVisible = state.loading || state.failed || group?.episodes.isNullOrEmpty()
            binding.status.setText(when {
                state.loading -> DesignR.string.content_loading
                state.failed -> DesignR.string.content_failed
                else -> DesignR.string.content_empty
            })
            binding.line.isVisible = group != null
            binding.line.text = group?.name
            episodes.submitList(group?.episodes.orEmpty().map { MediaRow(it.ref, it.name, icon = DesignR.drawable.ic_play, cover = it.cover) })

            binding.root.post {
                if (isResumed && !binding.root.hasFocus()) {
                    requestPrimaryFocus()
                }
            }
        } }
        binding.root.post {
            if (isResumed && !binding.root.hasFocus()) {
                requestPrimaryFocus()
            }
        }
    }

    override fun onDestroyView() {
        binding.episodes.adapter = null
        super.onDestroyView()
    }

    private fun playEpisode(ref: String, title: String) {
        val item = vm.ui.value.detail?.item ?: return
        navigator.openPlayer(requireContext(), PlayRequest(PlayKind.VOD, vm.sourceId, ref, title,
            mapOf("cover" to item.cover.orEmpty(), "itemId" to item.id, "mediaTitle" to item.title, "episodeTitle" to title)))
    }

    companion object {
        internal const val SOURCE_ID = "sourceId"
        internal const val ITEM_ID = "itemId"
        fun arguments(sourceId: String, itemId: String): Bundle = bundleOf(SOURCE_ID to sourceId, ITEM_ID to itemId)
    }
}
