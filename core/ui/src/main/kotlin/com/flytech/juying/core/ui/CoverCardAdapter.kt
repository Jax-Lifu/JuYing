package com.flytech.juying.core.ui

import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.ImageView
import androidx.core.view.isVisible
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.flytech.juying.core.ui.databinding.ItemCoverCardBinding

/** Cover is optional: missing artwork never blocks playback or invents metadata. */
data class CoverCard(val id: String, val title: String, val subtitle: String, val cover: String? = null,
    val progress: Int? = null, val isLogo: Boolean = false)

class CoverCardAdapter(private val carousel: Boolean = false, private val onClick: (CoverCard) -> Unit,
    private val onLongClick: ((CoverCard) -> Unit)? = null) : ListAdapter<CoverCard, CoverCardAdapter.Holder>(object : DiffUtil.ItemCallback<CoverCard>() {
    override fun areItemsTheSame(a: CoverCard, b: CoverCard) = a.id == b.id
    override fun areContentsTheSame(a: CoverCard, b: CoverCard) = a == b
}) {
    class Holder(val binding: ItemCoverCardBinding) : RecyclerView.ViewHolder(binding.root)
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val binding = ItemCoverCardBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        if (carousel) binding.root.layoutParams.width = parent.resources.getDimensionPixelSize(com.flytech.juying.core.designsystem.R.dimen.jy_history_width)
        return Holder(binding)
    }
    override fun onBindViewHolder(holder: Holder, position: Int) = with(holder.binding) {
        val item = getItem(position)
        title.text = item.title; subtitle.text = item.subtitle
        cover.scaleType = if (item.isLogo) ImageView.ScaleType.FIT_CENTER else ImageView.ScaleType.CENTER_CROP
        cover.setBackgroundColor(if (item.isLogo) android.graphics.Color.rgb(245, 246, 246) else android.graphics.Color.TRANSPARENT)
        val padding = if (item.isLogo) (8 * root.resources.displayMetrics.density).toInt() else 0
        cover.setPadding(padding, padding, padding, padding)
        cover.loadImage(item.cover)
        progress.isVisible = item.progress != null; progress.progress = item.progress ?: 0
        root.contentDescription = "${item.title}, ${item.subtitle}"
        root.setOnClickListener { onClick(item) }
        root.setOnLongClickListener { onLongClick?.invoke(item); onLongClick != null }
    }

    override fun onViewRecycled(holder: Holder) { holder.binding.cover.loadImage(null); super.onViewRecycled(holder) }
}
