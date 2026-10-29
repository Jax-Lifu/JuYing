package com.flytech.juying.feature.live

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.ui.loadImage
import com.flytech.juying.feature.live.databinding.ItemChannelBinding
import com.flytech.juying.feature.live.databinding.ItemGroupBinding

/** 直播频道分组横向/纵向选择适配器。 */
class GroupAdapter(private val onSelect: (Int) -> Unit) :
    ListAdapter<String, GroupAdapter.VH>(object : DiffUtil.ItemCallback<String>() {
        override fun areItemsTheSame(a: String, b: String) = a == b
        override fun areContentsTheSame(a: String, b: String) = a == b
    }) {

    private var selected = 0

    fun submit(names: List<String>, selectedIndex: Int) {
        val old = selected
        selected = selectedIndex
        submitList(names) {
            if (old in currentList.indices) notifyItemChanged(old)
            if (selectedIndex in currentList.indices) notifyItemChanged(selectedIndex)
        }
    }

    inner class VH(val b: ItemGroupBinding) : RecyclerView.ViewHolder(b.root) {
        private val focusSelectRunnable = Runnable {
            val pos = bindingAdapterPosition
            if (pos != RecyclerView.NO_POSITION && b.root.hasFocus()) {
                onSelect(pos)
            }
        }

        init {
            // 遥控器焦点移到某分组时延迟 120ms 切换右侧列表，防止长按方向键快速掠过时高频全量刷新掉帧；点击则立即生效。
            b.root.setOnFocusChangeListener { v, hasFocus ->
                v.removeCallbacks(focusSelectRunnable)
                if (hasFocus && bindingAdapterPosition != RecyclerView.NO_POSITION) {
                    v.postDelayed(focusSelectRunnable, GROUP_FOCUS_DELAY_MS)
                }
            }
            b.root.setOnClickListener { v ->
                v.removeCallbacks(focusSelectRunnable)
                if (bindingAdapterPosition != RecyclerView.NO_POSITION) onSelect(bindingAdapterPosition)
            }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val binding = ItemGroupBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        if ((parent as RecyclerView).layoutManager.let { it is LinearLayoutManager && it.orientation == RecyclerView.HORIZONTAL }) {
            binding.root.layoutParams.width = ViewGroup.LayoutParams.WRAP_CONTENT
        }
        return VH(binding)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.b.name.text = getItem(position)
        holder.b.root.contentDescription = getItem(position)
        holder.b.root.isSelected = position == selected
    }

    private companion object { const val GROUP_FOCUS_DELAY_MS = 120L }
}

/** 直播频道列表适配器，支持 Payload 局部刷新台标与焦点态。 */
class ChannelAdapter(private val onFocus: (Channel) -> Unit, private val onClick: (Channel) -> Unit) :
    ListAdapter<Channel, ChannelAdapter.VH>(object : DiffUtil.ItemCallback<Channel>() {
        override fun areItemsTheSame(a: Channel, b: Channel) = a.id == b.id
        override fun areContentsTheSame(a: Channel, b: Channel) = a == b
    }) {

    private var selectedId: String? = null

    fun select(channelId: String) {
        if (selectedId == channelId) return
        val old = currentList.indexOfFirst { it.id == selectedId }
        selectedId = channelId
        val next = currentList.indexOfFirst { it.id == selectedId }
        if (old >= 0) notifyItemChanged(old, SelectionPayload)
        if (next >= 0) notifyItemChanged(next, SelectionPayload)
    }

    inner class VH(val b: ItemChannelBinding) : RecyclerView.ViewHolder(b.root) {
        init {
            b.root.setOnClickListener {
                if (bindingAdapterPosition != RecyclerView.NO_POSITION) onClick(getItem(bindingAdapterPosition))
            }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        VH(ItemChannelBinding.inflate(LayoutInflater.from(parent.context), parent, false))

    override fun onBindViewHolder(holder: VH, position: Int, payloads: MutableList<Any>) {
        // 焦点切换只更新选中态，避免重复提交频道 logo 的图片请求。
        if (payloads.isNotEmpty() && payloads.all { it === SelectionPayload }) {
            holder.b.root.isSelected = getItem(position).id == selectedId
        } else onBindViewHolder(holder, position)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val c = getItem(position)
        holder.b.name.text = c.name
        holder.b.root.isSelected = c.id == selectedId
        holder.b.root.contentDescription = c.name
        holder.b.root.setOnFocusChangeListener { _, focused -> if (focused) onFocus(c) }
        holder.b.logo.loadImage(c.logo, 256, com.flytech.juying.core.designsystem.R.drawable.ic_live)
    }

    override fun onViewRecycled(holder: VH) { holder.b.logo.loadImage(null); super.onViewRecycled(holder) }

    private object SelectionPayload
}
