package com.flytech.juying.core.ui

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.view.isVisible
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.flytech.juying.core.ui.databinding.ItemMediaRowBinding

data class MediaRow(val id: String, val title: String, val subtitle: String = "",
    val icon: Int = com.flytech.juying.core.designsystem.R.drawable.ic_play,
    val selected: Boolean = false, val progress: Int? = null)

/** Stable identities preserve focus as source discovery or history updates arrive. */
class MediaRowAdapter(private val onClick: (MediaRow) -> Unit,
    private val onFocus: ((MediaRow) -> Unit)? = null) :
    ListAdapter<MediaRow, MediaRowAdapter.Holder>(object : DiffUtil.ItemCallback<MediaRow>() {
        override fun areItemsTheSame(a: MediaRow, b: MediaRow) = a.id == b.id
        override fun areContentsTheSame(a: MediaRow, b: MediaRow) = a == b
    }) {
    class Holder(val binding: ItemMediaRowBinding) : RecyclerView.ViewHolder(binding.root)
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        Holder(ItemMediaRowBinding.inflate(LayoutInflater.from(parent.context), parent, false))
    override fun onBindViewHolder(holder: Holder, position: Int) = with(holder.binding) {
        val item = getItem(position)
        title.text = item.title
        subtitle.text = item.subtitle
        subtitle.isVisible = item.subtitle.isNotBlank()
        icon.setImageResource(item.icon)
        progress.isVisible = item.progress != null
        progress.progress = item.progress ?: 0
        root.isSelected = item.selected
        root.contentDescription = "${item.title}, ${item.subtitle}"
        root.setOnClickListener { onClick(item) }
        root.setOnFocusChangeListener { _, focused -> if (focused) onFocus?.invoke(item) }
    }
}
