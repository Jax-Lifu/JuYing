package com.flytech.juying.core.ui

import android.graphics.Outline
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.ImageView
import androidx.core.view.isVisible
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.flytech.juying.core.model.VodItem
import com.flytech.juying.core.ui.databinding.ItemVodPosterBinding
import com.flytech.juying.core.designsystem.R as D

/** 点播和跨源搜索共用海报；来源标签随列表提交，避免异步结果串站。 */
data class VodPoster(val item: VodItem, val caption: String = item.remarks.orEmpty())

/** 点播竖版海报网格 RecyclerView 适配器。 */
class VodPosterAdapter(private val carousel: Boolean = false, private val onClick: (VodItem) -> Unit) :
    ListAdapter<VodPoster, VodPosterAdapter.Holder>(object : DiffUtil.ItemCallback<VodPoster>() {
        override fun areItemsTheSame(a: VodPoster, b: VodPoster) = a.item.sourceId == b.item.sourceId && a.item.id == b.item.id
        override fun areContentsTheSame(a: VodPoster, b: VodPoster) = a == b
    }) {
    /** 列表项 ViewHolder 缓存载体。 */
    class Holder(val binding: ItemVodPosterBinding) : RecyclerView.ViewHolder(binding.root)
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        Holder(ItemVodPosterBinding.inflate(LayoutInflater.from(parent.context), parent, false).apply {
            val radius = root.resources.getDimension(D.dimen.jy_radius)
            val outline = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, radius)
                }
            }
            root.outlineProvider = outline
            root.clipToOutline = true
            cover.outlineProvider = outline
            cover.clipToOutline = true

            if (carousel) {
                val height = parent.resources.getDimensionPixelSize(D.dimen.jy_poster_carousel_height)
                root.layoutParams.width = height * 4 / 5 + root.paddingLeft + root.paddingRight
                cover.layoutParams.height = height
                cover.scaleType = ImageView.ScaleType.CENTER_CROP
            }
        })
    override fun onBindViewHolder(holder: Holder, position: Int) {
        val poster = getItem(position)
        with(holder.binding) {
            title.text = poster.item.title
            caption.text = poster.caption
            caption.isVisible = poster.caption.isNotBlank()
            cover.loadImage(poster.item.cover)
            root.contentDescription = listOf(poster.item.title, poster.caption).filter { it.isNotBlank() }.joinToString("，")
            root.setOnClickListener { onClick(poster.item) }
        }
    }
    override fun onViewRecycled(holder: Holder) { holder.binding.cover.loadImage(null) }
}
