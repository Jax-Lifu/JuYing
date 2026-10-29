package com.flytech.juying.core.ui

import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView

/** 文本选项选择数据实体。 */
data class TextChoice(val id: String, val label: String, val selected: Boolean = false)

/** 文本选项选择列表 RecyclerView 适配器，用于线路、音轨、字幕等单选菜单。 */
class TextChoiceAdapter(private val onClick: (TextChoice) -> Unit) :
    ListAdapter<TextChoice, TextChoiceAdapter.Holder>(object : DiffUtil.ItemCallback<TextChoice>() {
        override fun areItemsTheSame(a: TextChoice, b: TextChoice) = a.id == b.id
        override fun areContentsTheSame(a: TextChoice, b: TextChoice) = a == b
    }) {
    /** 列表项 ViewHolder 缓存载体。 */
    class Holder(val text: TextView) : RecyclerView.ViewHolder(text)
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = Holder(
        LayoutInflater.from(parent.context).inflate(R.layout.item_text_choice, parent, false) as TextView)
    override fun onBindViewHolder(holder: Holder, position: Int) {
        val choice = getItem(position)
        holder.text.text = choice.label
        holder.text.isSelected = choice.selected
        holder.text.setCompoundDrawablesRelativeWithIntrinsicBounds(
            if (choice.selected) com.flytech.juying.core.designsystem.R.drawable.ic_check else 0, 0, 0, 0)
        holder.text.setTypeface(null, if (choice.selected) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
        holder.text.setOnClickListener { onClick(choice) }
    }
}
