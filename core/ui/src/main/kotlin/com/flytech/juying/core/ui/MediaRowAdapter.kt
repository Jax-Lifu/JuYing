package com.flytech.juying.core.ui

import android.graphics.Outline
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import androidx.annotation.DrawableRes
import androidx.core.view.isVisible
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.flytech.juying.core.designsystem.R as D
import com.flytech.juying.core.ui.databinding.ItemMediaRowBinding

/**
 * 结构化多源列表项（适用于本地/局域网目录浏览、历史记录与播放线路列表）。
 *
 * @property id 唯一稳定标识（对于文件系统是完整 path，历史记录是记录 ID）。
 * @property cover 封面图片地址或本地直链，为 null 时展示 [icon]。
 * @property progress 观看进度条百分比（0-1000），null 则隐藏进度条。
 */
data class MediaRow(
    val id: String,
    val title: String,
    val subtitle: String = "",
    @DrawableRes val icon: Int = 0,
    val progress: Int? = null,
    val selected: Boolean = false,
    val cover: String? = null,
)

/** Stable identities preserve focus as source discovery or history updates arrive. */
class MediaRowAdapter(
    private val onClick: (MediaRow) -> Unit,
    private val onFocus: ((MediaRow) -> Unit)? = null,
) : ListAdapter<MediaRow, MediaRowAdapter.Holder>(object : DiffUtil.ItemCallback<MediaRow>() {
    override fun areItemsTheSame(a: MediaRow, b: MediaRow) = a.id == b.id
    override fun areContentsTheSame(a: MediaRow, b: MediaRow) = a == b
}) {
    /** 列表项 ViewHolder 缓存载体。 */
    class Holder(val binding: ItemMediaRowBinding) : RecyclerView.ViewHolder(binding.root)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        Holder(ItemMediaRowBinding.inflate(LayoutInflater.from(parent.context), parent, false).apply {
            val radius = root.resources.getDimension(D.dimen.jy_radius)
            val outline = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, radius)
                }
            }
            root.outlineProvider = outline
            root.clipToOutline = true
            thumbContainer.outlineProvider = outline
            thumbContainer.clipToOutline = true
        })

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

        val hasCover = !item.cover.isNullOrBlank()
        cover.isVisible = hasCover
        icon.isVisible = !hasCover
        if (hasCover) {
            cover.loadImage(item.cover)
        } else {
            cover.loadImage(null)
        }
    }

    override fun onViewRecycled(holder: Holder) {
        holder.binding.cover.loadImage(null)
    }
}
