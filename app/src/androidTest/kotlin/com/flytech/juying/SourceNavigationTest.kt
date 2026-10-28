package com.flytech.juying

import android.content.Context
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import androidx.navigation.fragment.NavHostFragment
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.HistoryRepository
import com.flytech.juying.core.model.HistoryEntry
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.ui.MediaRowAdapter
import com.flytech.juying.feature.home.HomeFragment
import com.flytech.juying.source.cctv.BUILTIN_CCTV_ID
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import com.flytech.juying.core.designsystem.R as DesignR
import com.flytech.juying.feature.home.R as HomeR

@RunWith(AndroidJUnit4::class)
class SourceNavigationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val prefs = instrumentation.targetContext.getSharedPreferences("source_browse", Context.MODE_PRIVATE)

    @Test fun homeCctvCardOffersVodAfterWatchingLive(): Unit = withSourcePreferences {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var history: HistoryRepository
            scenario.onActivity {
                val host = it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
                history = (host.childFragmentManager.primaryNavigationFragment as HomeFragment).history
            }
            val historyId = "source-navigation-test-${UUID.randomUUID()}"
            try {
                // Keep CCTV inside the six home cards even when the device has many configured sources.
                history.record(HistoryEntry(historyId, PlayKind.LIVE, BUILTIN_CCTV_ID, "cctv1",
                    "CCTV navigation test", 0, 0, Long.MAX_VALUE))
                waitFor(scenario) { sourceRow(it.findViewById(HomeR.id.sources)) != null }
                scenario.onActivity {
                    remember(SourceCapability.LIVE)
                    assertTrue(sourceRow(it.findViewById(HomeR.id.sources))!!.performClick())
                }
                val live = instrumentation.targetContext.getString(DesignR.string.ui_live)
                val vod = instrumentation.targetContext.getString(DesignR.string.ui_vod)
                withTimeout(5_000) {
                    while (true) {
                        scenario.onActivity { assertEquals("Home must offer both CCTV capabilities", R.id.nav_home, destination(it)) }
                        val liveChoice = capabilityChoice(live)
                        val vodChoice = capabilityChoice(vod)
                        if (liveChoice != null && vodChoice != null) {
                            assertTrue(vodChoice.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                            break
                        }
                        delay(100)
                    }
                }
                waitFor(scenario) { destination(it) == R.id.nav_vod }
                scenario.onActivity { assertEquals(BUILTIN_CCTV_ID, it.memory.selected(SourceCapability.VOD)) }
            } finally {
                history.delete(historyId)
            }
        }
    }

    @Test fun vodPickerIgnoresPreviousLiveCapability(): Unit = pickerKeepsPage(SourceCapability.VOD, SourceCapability.LIVE)

    @Test fun livePickerIgnoresPreviousVodCapability(): Unit = pickerKeepsPage(SourceCapability.LIVE, SourceCapability.VOD)

    @Test fun explicitCapabilityOverridesCurrentPage(): Unit = withSourcePreferences {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { it.openSource(SourceCapability.LIVE) }
            waitFor(scenario) { destination(it) == R.id.nav_live }
            scenario.onActivity { it.navigator.openSource(it, BUILTIN_CCTV_ID, SourceCapability.VOD) }
            waitFor(scenario) { destination(it) == R.id.nav_vod }
            scenario.onActivity { assertEquals(BUILTIN_CCTV_ID, it.memory.selected(SourceCapability.VOD)) }
        }
    }

    private fun pickerKeepsPage(capability: SourceCapability, previous: SourceCapability): Unit = withSourcePreferences {
        val expected = if (capability == SourceCapability.VOD) R.id.nav_vod else R.id.nav_live
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { it.openSource(capability) }
            waitFor(scenario) { destination(it) == expected }
            scenario.onActivity { assertTrue(it.findViewById<View>(R.id.source_switch).performClick()) }
            waitFor(scenario) { sourceRow(picker(it)?.dialog?.findViewById(R.id.source_list)) != null }
            scenario.onActivity {
                // Reproduce a stale last-used capability without notifying the current page to overwrite it.
                remember(previous)
                assertTrue(sourceRow(picker(it)!!.requireDialog().findViewById(R.id.source_list))!!.performClick())
            }
            waitFor(scenario) {
                assertEquals("Choosing CCTV must preserve the current content page", expected, destination(it))
                picker(it) == null && it.memory.lastCapability(BUILTIN_CCTV_ID) == capability
            }
            scenario.onActivity { assertEquals(BUILTIN_CCTV_ID, it.memory.selected(capability)) }
        }
    }

    private fun remember(capability: SourceCapability) {
        prefs.edit().putString("$BUILTIN_CCTV_ID.capability", capability.name).commit()
    }

    private fun sourceRow(list: RecyclerView?): View? {
        val recycler = list ?: return null
        val adapter = recycler.adapter as? MediaRowAdapter ?: return null
        val index = adapter.currentList.indexOfFirst { it.id == BUILTIN_CCTV_ID }
        if (index < 0) return null
        recycler.scrollToPosition(index)
        return recycler.findViewHolderForAdapterPosition(index)?.itemView
    }

    private fun capabilityChoice(label: String): AccessibilityNodeInfo? =
        instrumentation.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText(label)
            ?.firstOrNull { it.text?.toString() == label && it.parent?.className?.toString() == "android.widget.ListView" }

    private fun picker(activity: MainActivity) = activity.supportFragmentManager.findFragmentByTag("source-picker") as? SourcePickerDialog
    private fun destination(activity: MainActivity) =
        (activity.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment).navController.currentDestination?.id

    private suspend fun waitFor(scenario: ActivityScenario<MainActivity>, ready: (MainActivity) -> Boolean) = withTimeout(5_000) {
        while (true) {
            var done = false
            scenario.onActivity { done = ready(it) }
            if (done) { instrumentation.waitForIdleSync(); return@withTimeout }
            delay(100)
        }
    }

    private fun withSourcePreferences(block: suspend () -> Unit): Unit = runBlocking {
        fun relevant(key: String) = key.startsWith("selected.") || key.startsWith("$BUILTIN_CCTV_ID.")
        val previous = prefs.all.filterKeys(::relevant)
        prefs.edit().putString("selected.LIVE", BUILTIN_CCTV_ID).putString("selected.VOD", BUILTIN_CCTV_ID).commit()
        try { block() }
        finally {
            prefs.edit().apply {
                prefs.all.keys.filter(::relevant).forEach(::remove)
                previous.forEach { (key, value) -> putString(key, value as String?) }
            }.commit()
        }
    }
}
