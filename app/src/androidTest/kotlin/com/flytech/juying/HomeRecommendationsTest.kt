package com.flytech.juying

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.BitmapDrawable
import android.view.KeyEvent
import android.view.View
import android.widget.ImageView
import androidx.navigation.fragment.NavHostFragment
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import com.flytech.juying.feature.home.R as HomeR
import com.flytech.juying.core.ui.R as UiR

@RunWith(AndroidJUnit4::class)
class HomeRecommendationsTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun recommendationsFillPosterFramesWithoutStretchingAndNavigateByRemote(): Unit = runBlocking {
        val context = instrumentation.targetContext
        val prefs = context.getSharedPreferences("source_browse", Context.MODE_PRIVATE)
        val previousSource = prefs.getString("selected.VOD", null)
        val sourceId = "home-posters-test-${UUID.randomUUID()}"
        val details = CopyOnWriteArrayList<String>()
        val images = listOf(150, 180).map { height ->
            val poster = Bitmap.createBitmap(120, height, Bitmap.Config.ARGB_8888)
            Canvas(poster).apply {
                drawColor(Color.BLUE)
                drawRect(4f, 4f, 116f, height - 4f, Paint().apply { color = Color.GREEN; style = Paint.Style.STROKE; strokeWidth = 8f })
            }
            ByteArrayOutputStream().use { poster.compress(Bitmap.CompressFormat.PNG, 100, it); it.toByteArray() }
                .also { poster.recycle() }
        }
        var repository: SourceRepository? = null
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val url = request.requestUrl!!
                    if (url.encodedPath == "/poster-0.png") return MockResponse().setHeader("Content-Type", "image/png").setBody(Buffer().write(images[0]))
                    if (url.encodedPath == "/poster-1.png") return MockResponse().setHeader("Content-Type", "image/png").setBody(Buffer().write(images[1]))
                    if (url.queryParameter("ac") == null) return MockResponse().setBody("""{"class":[{"type_id":"all","type_name":"Test"}]}""")
                    val id = url.queryParameter("ids")?.also { details += it }
                    val rows = JSONArray()
                    (0 until 30).filter { id == null || id == "poster-$it" }.forEach { index ->
                        rows.put(JSONObject().put("vod_id", "poster-$index").put("vod_name", "Poster $index")
                            .put("vod_pic", server.url("/poster-${index % 2}.png").toString()).put("vod_content", "Original test poster"))
                    }
                    return MockResponse().setBody(JSONObject().put("list", rows).toString())
                }
            }
            server.start()
            try {
                ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                    scenario.onActivity { repository = it.sources }
                    repository!!.upsert(SourceConfig(sourceId, "Home poster test", SourceType.TVBOX, server.url("/cms").toString()))
                    scenario.onActivity {
                        it.memory.select(sourceId, SourceCapability.VOD)
                        host(it).navController.navigate(R.id.nav_home)
                    }
                    waitFor(scenario) { activity ->
                        val row = activity.findViewById<RecyclerView>(HomeR.id.recommendations)
                        row?.adapter?.itemCount == 24 && (0..1).all { index ->
                            row.findViewHolderForAdapterPosition(index)?.itemView?.findViewById<ImageView>(UiR.id.cover)?.drawable is BitmapDrawable
                        }
                    }
                    // 触屏设备可能仍处于触摸模式；遥控导航前先进入焦点模式。
                    instrumentation.setInTouchMode(false)
                    waitFor(scenario) { !list(it).isInTouchMode }
                    scenario.onActivity { activity ->
                        val list = list(activity)
                        val layout = list.layoutManager as LinearLayoutManager
                        assertEquals(LinearLayoutManager.HORIZONTAL, layout.orientation)
                        assertTrue(activity.findViewById<View>(HomeR.id.recommendation_heading).isShown)
                        assertFalse(activity.findViewById<View>(HomeR.id.recommendation_empty).isShown)
                        assertTrue("The first screen contains several complete posters", layout.findLastCompletelyVisibleItemPosition() >= 1)
                        for (index in 0..1) {
                            val card = list.findViewHolderForAdapterPosition(index)!!.itemView
                            val bounds = Rect().also { layout.getDecoratedBoundsWithMargins(card, it) }
                            assertTrue("Cards stay inside their row", bounds.left >= 0 && bounds.right <= list.width && bounds.top >= 0 && bounds.bottom <= list.height)
                            val cover = card.findViewById<ImageView>(UiR.id.cover)
                            assertEquals(ImageView.ScaleType.CENTER_CROP, cover.scaleType)
                            assertEquals(4f / 5f, cover.width.toFloat() / cover.height, .02f)
                            val values = FloatArray(9).also(cover.imageMatrix::getValues)
                            assertEquals("Poster scales uniformly", values[Matrix.MSCALE_X], values[Matrix.MSCALE_Y], .001f)
                            val drawn = RectF(cover.drawable.bounds).also { cover.imageMatrix.mapRect(it) }
                            val contentWidth = (cover.width - cover.paddingLeft - cover.paddingRight).toFloat()
                            val contentHeight = (cover.height - cover.paddingTop - cover.paddingBottom).toFloat()
                            assertTrue("Posters fill their frames without blank bands", drawn.left <= .5f && drawn.top <= .5f &&
                                drawn.right >= contentWidth - .5f && drawn.bottom >= contentHeight - .5f)
                            if (index == 0) {
                                assertEquals("Matching 4:5 poster keeps its left edge", 0f, drawn.left, .5f)
                                assertEquals("Matching 4:5 poster keeps its top edge", 0f, drawn.top, .5f)
                                assertEquals("Matching 4:5 poster keeps its right edge", contentWidth, drawn.right, .5f)
                                assertEquals("Matching 4:5 poster keeps its bottom edge", contentHeight, drawn.bottom, .5f)
                            } else {
                                assertTrue("A different aspect ratio is cropped instead of stretched", drawn.left < -.5f || drawn.top < -.5f)
                            }
                        }
                        assertTrue("First poster accepts keyboard focus", list.findViewHolderForAdapterPosition(0)!!.itemView.requestFocus())
                    }
                    for (index in 1 until 24) {
                        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_RIGHT)
                        waitFor(scenario) { focusedPosition(it) == index }
                    }
                    scenario.onActivity { assertTrue("D-pad reaches beyond the first screen", (list(it).layoutManager as LinearLayoutManager).findFirstVisibleItemPosition() > 0) }
                    instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_LEFT)
                    waitFor(scenario) { focusedPosition(it) == 22 }
                    instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_CENTER)
                    waitFor(scenario) { host(it).navController.currentDestination?.id == R.id.vod_detail && details.contains("poster-22") }
                    scenario.onActivity { assertEquals(sourceId, host(it).childFragmentManager.primaryNavigationFragment!!.requireArguments().getString("sourceId")) }
                }
            } finally {
                prefs.edit().apply {
                    putString("selected.VOD", previousSource)
                    prefs.all.keys.filter { it.startsWith("$sourceId.") }.forEach(::remove)
                }.commit()
                repository?.delete(sourceId)
            }
        }
    }

    private fun host(activity: MainActivity) = activity.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
    private fun list(activity: MainActivity) = activity.findViewById<RecyclerView>(HomeR.id.recommendations)
    private fun focusedPosition(activity: MainActivity): Int = activity.currentFocus?.let { list(activity).findContainingItemView(it) }
        ?.let { list(activity).getChildAdapterPosition(it) } ?: RecyclerView.NO_POSITION
    private suspend fun waitFor(scenario: ActivityScenario<MainActivity>, ready: (MainActivity) -> Boolean) = withTimeout(15_000) {
        while (true) {
            var done = false
            scenario.onActivity { done = ready(it) }
            if (done) { instrumentation.waitForIdleSync(); return@withTimeout }
            delay(100)
        }
    }
}
