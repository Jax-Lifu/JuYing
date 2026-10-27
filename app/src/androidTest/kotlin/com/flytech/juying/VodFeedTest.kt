package com.flytech.juying

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Trace
import android.view.FrameMetrics
import android.view.KeyEvent
import android.view.View
import android.view.Window
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.TextView
import androidx.navigation.fragment.NavHostFragment
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.ui.VodPosterAdapter
import java.io.File
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import com.flytech.juying.feature.vod.R as V

@RunWith(AndroidJUnit4::class)
class VodFeedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun emptyPageCategoryOverflowAndRapidScrollingKeepTheFeedMoving(): Unit = runBlocking {
        val sourceId = "vod-feed-ui-test"
        val preferences = context.getSharedPreferences("source_browse", Context.MODE_PRIVATE)
        val previousMemory = preferences.all.filterKeys { it == "selected.VOD" || it.startsWith("$sourceId.") }
        val requests = CopyOnWriteArrayList<Pair<String, Int>>()
        val active = AtomicInteger()
        val maxActive = AtomicInteger()
        val frameSamples = ConcurrentLinkedQueue<LongArray>()
        val frameThread = HandlerThread("VodFeedMetrics")
        var frameWindow: Window? = null
        val frameListener = Window.OnFrameMetricsAvailableListener { _, frame, dropped ->
            // Copy reused framework metrics off the UI thread; no file I/O or View reads here.
            frameSamples.add(LongArray(FRAME_FIELDS.size + 1) { index ->
                if (index == FRAME_FIELDS.size) dropped.toLong() else frame.getMetric(FRAME_FIELDS[index].second)
            })
        }
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val url = request.requestUrl!!
                    val category = url.queryParameter("t")
                    if (category == null) return MockResponse().setBody(JSONObject().put("class", JSONArray().apply {
                        (1..30).forEach { put(JSONObject().put("type_id", "c$it").put("type_name", "Category $it")) }
                    }).toString())
                    val page = url.queryParameter("pg")!!.toInt()
                    requests += category to page
                    val inFlight = active.incrementAndGet()
                    maxActive.updateAndGet { maxOf(it, inFlight) }
                    Trace.beginSection("VodFeed.fixture.$category.p$page")
                    try {
                        // Keep a request pending while repeated UI scroll events arrive.
                        Thread.sleep(RESPONSE_DELAY_MS)
                        val rows = JSONArray()
                        val contentPage = if (category == "c30" && page == 5) 4 else page
                        if (category != "c1" || page != 1) repeat(PAGE_SIZE) { index ->
                            rows.put(JSONObject().put("vod_id", "$category-$contentPage-$index")
                                .put("vod_name", "$category page $contentPage item $index"))
                        }
                        return MockResponse().setBody(JSONObject().put("page", page)
                            .put("pagecount", if (category == "c1") 2 else LAST_PAGE).put("list", rows).toString())
                    } finally {
                        Trace.endSection()
                        active.decrementAndGet()
                    }
                }
            }
            server.start()
            try {
                ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                    lateinit var repository: SourceRepository
                    scenario.onActivity {
                        repository = it.sources
                        // Stop home recommendations before selecting this isolated CMS fixture.
                        (it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment)
                            .navController.navigate(R.id.nav_settings)
                    }
                    instrumentation.waitForIdleSync()
                    val previousSource = repository.get(sourceId)
                    try {
                        repository.upsert(SourceConfig(sourceId, "VOD feed regression", SourceType.TVBOX, server.url("/cms").toString()))
                        scenario.onActivity {
                            it.memory.select(sourceId, SourceCapability.VOD)
                            (it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment)
                                .navController.navigate(R.id.nav_vod)
                        }
                        waitFor(scenario) {
                            (it.findViewById<RecyclerView>(V.id.posters)?.adapter as? VodPosterAdapter)
                                ?.currentList?.lastOrNull()?.item?.title == "c1 page 2 item 47"
                        }
                        assertEquals("An empty first page continues without any scroll", listOf("c1" to 1, "c1" to 2), requests.toList())
                        scenario.onActivity {
                            val categories = it.findViewById<RecyclerView>(V.id.categories)
                            assertEquals(30, categories.adapter!!.itemCount)
                            assertTrue("Thirty categories overflow the visible row", categories.canScrollHorizontally(1))
                            assertTrue(it.findViewById<View>(V.id.all_categories).performClick())
                        }
                        withTimeout(UI_TIMEOUT_MS) {
                            while (true) {
                                val root = instrumentation.uiAutomation.rootInActiveWindow
                                val last = root?.findAccessibilityNodeInfosByText("Category 30")?.firstOrNull { it.isVisibleToUser }
                                if (last != null) { assertTrue(last.performAction(AccessibilityNodeInfo.ACTION_CLICK)); break }
                                findDialogList(root)?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                                delay(POLL_MS)
                            }
                        }
                        waitFor(scenario) {
                            val category = it.findViewById<RecyclerView>(V.id.categories).findViewHolderForAdapterPosition(29)?.itemView as? TextView
                            category?.isSelected == true && category.compoundDrawablesRelative[0] != null &&
                                (posters(it).adapter as VodPosterAdapter).currentList.firstOrNull()?.item?.title?.startsWith("c30 ") == true
                        }
                        scenario.onActivity { it.findViewById<View>(V.id.all_categories).performClick() }
                        withTimeout(UI_TIMEOUT_MS) {
                            while (instrumentation.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText("Category 30")
                                    ?.any { it.isChecked } != true) delay(POLL_MS)
                        }
                        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
                        frameThread.start()
                        val frameHandler = Handler(frameThread.looper)
                        scenario.onActivity {
                            frameWindow = it.window
                            it.window.addOnFrameMetricsAvailableListener(frameListener, frameHandler)
                        }
                        withTimeout(SCROLL_TIMEOUT_MS) {
                            var reachedLast = false
                            while (!reachedLast) {
                                scenario.onActivity {
                                    val list = posters(it)
                                    val items = (list.adapter as VodPosterAdapter).currentList
                                    val end = it.findViewById<TextView>(V.id.page_status).text.toString()
                                    if (items.size < FINAL_ITEM_COUNT) assertNotEquals("A repeated page must not report the end", it.getString(V.string.vod_end), end)
                                    assertFalse("A duplicate page must not show a retry error", it.findViewById<View>(V.id.retry).isShown)
                                    Trace.beginSection("VodFeed.scroll.items${items.size}")
                                    try { list.scrollBy(0, list.height * 2) } finally { Trace.endSection() }
                                    reachedLast = list.findViewHolderForAdapterPosition(FINAL_ITEM_COUNT - 1)?.itemView
                                        ?.getGlobalVisibleRect(android.graphics.Rect()) == true
                                }
                                delay(SCROLL_INTERVAL_MS)
                            }
                        }
                        scenario.onActivity {
                            val items = (posters(it).adapter as VodPosterAdapter).currentList
                            assertEquals(FINAL_ITEM_COUNT, items.size)
                            assertEquals("c30 page 10 item 47", items.last().item.title)
                        }
                        assertEquals("Each of ten pages is requested once, including the duplicate fifth page",
                            (1..LAST_PAGE).map { "c30" to it }, requests.filter { it.first == "c30" })
                        assertEquals("At most one feed request may be in flight", 1, maxActive.get())
                    } finally {
                        scenario.onActivity {
                            frameWindow?.removeOnFrameMetricsAvailableListener(frameListener)
                            frameWindow = null
                            (it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment)
                                .navController.navigate(R.id.nav_settings)
                        }
                        if (previousSource == null) repository.delete(sourceId) else repository.upsert(previousSource)
                    }
                }
            } finally {
                // Also detach if an assertion or ActivityScenario cleanup failed before navigation.
                frameWindow?.let { window ->
                    instrumentation.runOnMainSync { window.removeOnFrameMetricsAvailableListener(frameListener) }
                }
                frameThread.quitSafely()
                frameThread.join(FRAME_THREAD_TIMEOUT_MS)
                preferences.edit().apply {
                    preferences.all.keys.filter { it == "selected.VOD" || it.startsWith("$sourceId.") }.forEach { remove(it) }
                    previousMemory.forEach { (key, value) -> putString(key, value as String) }
                }.commit()
                val histogram = JSONArray()
                val samples = frameSamples.toList()
                samples.filter { it[0] >= 0 }.groupingBy { (it[0] + NS_PER_MS / 2) / NS_PER_MS }
                    .eachCount().toSortedMap().forEach { (durationMs, count) ->
                    histogram.put(JSONObject().put("durationMs", durationMs).put("frames", count))
                }
                val report = JSONObject().put("frameDurationHistogram", histogram).put("maxConcurrentRequests", maxActive.get())
                    .put("frameCount", samples.size).put("droppedFrameReports", samples.sumOf { it.last() })
                    .put("requests", JSONArray(requests.map { "${it.first}:${it.second}" }))
                val output = File(context.getExternalFilesDir(null), "ui-check/vod-feed-metrics.json")
                output.parentFile!!.mkdirs(); output.writeText(report.toString(2))
                val frameOutput = File(output.parentFile, "vod-feed-frames.csv")
                frameOutput.bufferedWriter().use { writer ->
                    writer.appendLine(FRAME_FIELDS.joinToString(",") { it.first } + ",dropped_reports")
                    samples.forEach { writer.appendLine(it.joinToString(",")) }
                }
                instrumentation.sendStatus(0, Bundle().apply {
                    putString("vod_feed_metrics", output.absolutePath)
                    putString("vod_feed_frames", frameOutput.absolutePath)
                })
                check(!frameThread.isAlive) { "Frame metrics thread did not stop" }
            }
        }
    }

    private fun posters(activity: MainActivity): RecyclerView = activity.findViewById(V.id.posters)

    private suspend fun waitFor(scenario: ActivityScenario<MainActivity>, condition: (MainActivity) -> Boolean) = withTimeout(UI_TIMEOUT_MS) {
        while (true) {
            var ready = false
            scenario.onActivity { ready = condition(it) }
            if (ready) return@withTimeout
            delay(POLL_MS)
        }
    }

    private fun findDialogList(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null || node.className == "android.widget.ListView") return node
        for (index in 0 until node.childCount) findDialogList(node.getChild(index))?.let { return it }
        return null
    }

    private companion object {
        const val PAGE_SIZE = 48
        const val LAST_PAGE = 10
        const val FINAL_ITEM_COUNT = PAGE_SIZE * (LAST_PAGE - 1)
        const val RESPONSE_DELAY_MS = 160L
        const val SCROLL_INTERVAL_MS = 60L
        const val POLL_MS = 100L
        const val UI_TIMEOUT_MS = 15_000L
        const val SCROLL_TIMEOUT_MS = 45_000L
        const val FRAME_THREAD_TIMEOUT_MS = 3_000L
        const val NS_PER_MS = 1_000_000L
        // Unsupported metrics return -1 on older Android versions; retain vsync timestamps for trace correlation.
        val FRAME_FIELDS = listOf(
            "total_ns" to FrameMetrics.TOTAL_DURATION,
            "unknown_delay_ns" to FrameMetrics.UNKNOWN_DELAY_DURATION,
            "input_ns" to FrameMetrics.INPUT_HANDLING_DURATION,
            "animation_ns" to FrameMetrics.ANIMATION_DURATION,
            "layout_measure_ns" to FrameMetrics.LAYOUT_MEASURE_DURATION,
            "draw_ns" to FrameMetrics.DRAW_DURATION,
            "sync_ns" to FrameMetrics.SYNC_DURATION,
            "command_issue_ns" to FrameMetrics.COMMAND_ISSUE_DURATION,
            "swap_buffers_ns" to FrameMetrics.SWAP_BUFFERS_DURATION,
            "gpu_ns" to FrameMetrics.GPU_DURATION,
            "deadline_ns" to FrameMetrics.DEADLINE,
            "first_draw" to FrameMetrics.FIRST_DRAW_FRAME,
            "intended_vsync_ns" to FrameMetrics.INTENDED_VSYNC_TIMESTAMP,
            "vsync_ns" to FrameMetrics.VSYNC_TIMESTAMP,
        )
    }
}
