package com.flytech.juying

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.view.ContextThemeWrapper
import android.widget.FrameLayout
import androidx.recyclerview.widget.RecyclerView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.model.Channel
import com.flytech.juying.feature.live.ChannelAdapter
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import com.flytech.juying.core.designsystem.R as D

@RunWith(AndroidJUnit4::class)
class ChannelAdapterTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val channels = listOf(Channel("one", "One"), Channel("two", "Two"))

    @Test fun selectionNotifiesOnlyOldAndNewItemsWithTheSamePayload() = instrumentation.runOnMainSync {
        val adapter = ChannelAdapter({}, {}).apply { submitList(channels) }
        val changes = mutableListOf<Change>()
        adapter.registerAdapterDataObserver(observer(changes))

        adapter.select("one")
        assertEquals(listOf(0), changes.map { it.position })
        val payload = changes.single().payload
        assertNotNull(payload)
        changes.clear()

        adapter.select("two")
        assertEquals(listOf(0, 1), changes.map { it.position })
        assertTrue(changes.all { it.count == 1 && it.payload === payload })
        changes.clear()

        adapter.select("two")
        assertTrue("Selecting the current channel does not notify again", changes.isEmpty())
    }

    @Test fun selectionPayloadChangesOnlySelectedState() = instrumentation.runOnMainSync {
        val adapter = ChannelAdapter({}, {}).apply { submitList(channels) }
        val changes = mutableListOf<Change>()
        adapter.registerAdapterDataObserver(observer(changes))
        val context = ContextThemeWrapper(instrumentation.targetContext, D.style.Theme_Juying_Light)
        val holder = adapter.onCreateViewHolder(FrameLayout(context), 0)
        adapter.onBindViewHolder(holder, 0)
        val logo = ColorDrawable(Color.MAGENTA)
        holder.b.name.text = "sentinel name"
        holder.b.root.contentDescription = "sentinel description"
        holder.b.logo.setImageDrawable(logo)

        adapter.select("one")
        val payload = changes.single().payload!!
        adapter.onBindViewHolder(holder, 0, mutableListOf(payload))
        assertTrue(holder.b.root.isSelected)
        assertEquals("sentinel name", holder.b.name.text.toString())
        assertEquals("sentinel description", holder.b.root.contentDescription)
        assertSame("Selection keeps the existing logo", logo, holder.b.logo.drawable)

        adapter.select("two")
        adapter.onBindViewHolder(holder, 0, mutableListOf(payload))
        assertFalse(holder.b.root.isSelected)
        assertEquals("sentinel name", holder.b.name.text.toString())
        assertSame(logo, holder.b.logo.drawable)
    }

    @Test fun emptyOrUnknownPayloadStillBindsChannelContent() = instrumentation.runOnMainSync {
        val adapter = ChannelAdapter({}, {}).apply { submitList(channels) }
        val context = ContextThemeWrapper(instrumentation.targetContext, D.style.Theme_Juying_Light)
        val holder = adapter.onCreateViewHolder(FrameLayout(context), 0)
        adapter.select("one")
        for (payloads in listOf(mutableListOf<Any>(), mutableListOf(Any()))) {
            holder.b.name.text = "sentinel name"
            adapter.onBindViewHolder(holder, 0, payloads)
            assertEquals("One", holder.b.name.text.toString())
            assertTrue(holder.b.root.isSelected)
        }
    }

    private data class Change(val position: Int, val count: Int, val payload: Any?)

    private fun observer(changes: MutableList<Change>) = object : RecyclerView.AdapterDataObserver() {
        override fun onItemRangeChanged(positionStart: Int, itemCount: Int, payload: Any?) {
            changes += Change(positionStart, itemCount, payload)
        }
    }
}
