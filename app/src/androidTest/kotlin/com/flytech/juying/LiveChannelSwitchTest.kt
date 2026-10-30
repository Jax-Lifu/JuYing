package com.flytech.juying

import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.HistoryRepository
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.feature.player.PlayerActivity
import com.flytech.juying.feature.player.PlayerViewModel
import com.flytech.juying.player.api.PlaybackManager
import com.flytech.juying.player.api.PlayerEngine
import com.flytech.juying.source.api.playlist.PlaylistParser
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import com.flytech.juying.feature.player.R as PlayerR

@RunWith(AndroidJUnit4::class)
class LiveChannelSwitchTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun buttonBurstsAndChannelKeysKeepTheFinalChannelOnOneNativePlayer(): Unit = runBlocking {
        val sourceId = "live-switch-test-${UUID.randomUUID()}"
        val video = instrumentation.context.assets.open("test-pattern.mp4").use { it.readBytes() }
        var repository: SourceRepository? = null
        var model: PlayerViewModel? = null
        var manager: PlaybackManager? = null
        MockWebServer().use { server ->
            server.start()
            val playlist = "#EXTM3U\n" + ('A'..'D').joinToString("\n") { name ->
                "#EXTINF:-1 group-title=\"Switch test\",Test $name\n${server.url("/$name.mp4")}"
            }
            val channels = PlaylistParser.parse(playlist).single().channels
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse = when (request.requestUrl!!.encodedPath) {
                    "/channels.m3u" -> MockResponse().setBody(playlist)
                    "/A.mp4", "/B.mp4", "/C.mp4", "/D.mp4" ->
                        MockResponse().setHeader("Content-Type", "video/mp4").setBody(Buffer().write(video))
                    else -> MockResponse().setResponseCode(404)
                }
            }
            try {
                ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                    scenario.onActivity { repository = it.sources }
                    repository!!.upsert(SourceConfig(sourceId, "Live switch test", SourceType.IPTV, server.url("/channels.m3u").toString()))
                }
                val first = channels.first()
                val request = PlayRequest(PlayKind.LIVE, sourceId, first.id, first.name)
                ActivityScenario.launch<PlayerActivity>(PlayerActivity.intent(instrumentation.targetContext, request)).use { scenario ->
                    scenario.onActivity {
                        model = ViewModelProvider(it)[PlayerViewModel::class.java]
                        manager = field(checkNotNull(model), "playback")
                    }
                    val vm = model!!
                    waitForChannel(scenario, vm, first)
                    val engine = checkNotNull(manager!!.current())
                    assertRenderedVideo(scenario)

                    // One main-thread burst exercises queued requests before the source lookup completes.
                    clickBurst(scenario, listOf(1, 1, -1, 1, 1))
                    waitForChannel(scenario, vm, channels[3], engine, manager)
                    assertRenderedVideo(scenario)

                    clickBurst(scenario, listOf(-1, -1, 1, -1, 1, -1, -1))
                    waitForChannel(scenario, vm, channels[0], engine, manager)

                    // These enter through Android key dispatch, including wraparound and direction changes.
                    listOf(1, 1, 1, -1, -1).forEach { direction ->
                        instrumentation.sendKeyDownUpSync(if (direction > 0) KeyEvent.KEYCODE_CHANNEL_DOWN else KeyEvent.KEYCODE_CHANNEL_UP)
                    }
                    waitForChannel(scenario, vm, channels[1], engine, manager)
                    listOf(-1, -1, -1, 1).forEach { direction ->
                        instrumentation.sendKeyDownUpSync(if (direction > 0) KeyEvent.KEYCODE_CHANNEL_DOWN else KeyEvent.KEYCODE_CHANNEL_UP)
                    }
                    waitForChannel(scenario, vm, channels[3], engine, manager)
                    assertRenderedVideo(scenario)

                    scenario.recreate()
                    scenario.onActivity { assertSame(vm, ViewModelProvider(it)[PlayerViewModel::class.java]) }
                    waitForChannel(scenario, vm, channels[3], engine, manager)
                    assertRenderedVideo(scenario)

                    val nextRequest = request.copy(ref = channels[1].id, title = channels[1].name)
                    scenario.onActivity { it.startActivity(PlayerActivity.intent(it, nextRequest)) }
                    waitForChannel(scenario, vm, channels[1], engine, manager)
                    scenario.onActivity { assertEquals(nextRequest.ref, it.intent.getStringExtra("ref")) }

                    clickBurst(scenario, listOf(1))
                    waitForChannel(scenario, vm, channels[2], engine, manager)
                    // Drop retained state to exercise saved-request restoration with a fresh ViewModel.
                    scenario.onActivity { it.viewModelStore.clear() }
                    scenario.recreate()
                    scenario.onActivity {
                        model = ViewModelProvider(it)[PlayerViewModel::class.java]
                        assertNotSame(vm, model)
                    }
                    waitForChannel(scenario, model!!, channels[2], manager = manager)
                    assertRenderedVideo(scenario)
                }
                assertNull("Closing PlayerActivity releases its decoder", manager!!.current())
            } finally {
                model?.let { vm ->
                    // onStop may finish its short history write after ViewModel destruction.
                    val history = field<HistoryRepository>(vm, "history")
                    field<Mutex>(vm, "historyWrites").withLock {
                        channels.forEach { history.delete("$sourceId:${it.id}") }
                    }
                }
                repository?.delete(sourceId)
            }
        }
    }

    private fun clickBurst(scenario: ActivityScenario<PlayerActivity>, directions: List<Int>) {
        scenario.onActivity { activity ->
            if (!activity.findViewById<View>(PlayerR.id.controls).isShown) {
                activity.findViewById<View>(PlayerR.id.video_stage).performClick()
            }
            directions.forEach { direction ->
                val button = activity.findViewById<View>(if (direction > 0) PlayerR.id.next else PlayerR.id.previous)
                assertTrue("Live channel buttons remain available while resolving", button.isShown && button.isEnabled)
                assertTrue(button.performClick())
            }
        }
    }

    private suspend fun waitForChannel(
        scenario: ActivityScenario<PlayerActivity>,
        model: PlayerViewModel,
        channel: Channel,
        engine: PlayerEngine? = null,
        manager: PlaybackManager? = null,
    ) = withTimeout(20_000) {
        while (true) {
            var ready = false
            scenario.onActivity { activity ->
                val state = model.ui.value
                assertNull(state.error)
                assertFalse(state.switchError)
                if (engine != null) assertSame("Channel changes reuse the active player", engine, manager!!.current())
                ready = model.currentRequest?.ref == channel.id && state.pendingTitle == null &&
                    state.playback.isPlaying && state.playback.videoWidth == 320 && state.playback.videoHeight == 240 && model.positionMs() >= 500
                if (ready) {
                    assertEquals(channel.name, state.title)
                    assertNull(state.webPage)
                    assertTrue(activity.findViewById<SurfaceView>(PlayerR.id.surface).isShown)
                }
            }
            if (ready) return@withTimeout
            delay(50)
        }
    }

    private fun assertRenderedVideo(scenario: ActivityScenario<PlayerActivity>) {
        val bitmap = Bitmap.createBitmap(64, 48, Bitmap.Config.ARGB_8888)
        val copied = CountDownLatch(1)
        var result = PixelCopy.ERROR_UNKNOWN
        try {
            scenario.onActivity { activity ->
                PixelCopy.request(activity.findViewById<SurfaceView>(PlayerR.id.surface), bitmap, {
                    result = it
                    copied.countDown()
                }, Handler(Looper.getMainLooper()))
            }
            assertTrue("Native surface copy completes", copied.await(5, TimeUnit.SECONDS))
            assertEquals(PixelCopy.SUCCESS, result)
            val pixels = IntArray(bitmap.width * bitmap.height)
            bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            assertTrue("The native surface contains the decoded test pattern", pixels.filter { Color.red(it) + Color.green(it) + Color.blue(it) > 60 }.distinct().size > 3)
        } finally { bitmap.recycle() }
    }

    // Inspect the production Hilt instance without replacing repositories or the player.
    private inline fun <reified T> field(model: PlayerViewModel, name: String): T =
        PlayerViewModel::class.java.getDeclaredField(name).apply { isAccessible = true }.get(model) as T
}
