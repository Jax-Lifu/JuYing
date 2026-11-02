package com.flytech.juying

import android.view.KeyEvent
import android.view.View
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.HistoryRepository
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.feature.player.PlayerActivity
import com.flytech.juying.feature.player.PlayerViewModel
import com.flytech.juying.source.tvbox.TvboxSource
import java.util.UUID
import javax.inject.Provider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import com.flytech.juying.feature.player.R as PlayerR

@RunWith(AndroidJUnit4::class)
class PlayerRemoteControlTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun remoteSeeksAndNavigatesEpisodesOnTheNativePlayer(): Unit = runBlocking {
        val sourceId = "remote-test-${UUID.randomUUID()}"
        var repository: SourceRepository? = null
        var model: PlayerViewModel? = null
        var refs = emptyList<String>()
        MockWebServer().use { server ->
            server.start()
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val name = request.requestUrl!!.encodedPath.substringAfterLast('/')
                    if (name != "cms") {
                        val bytes = instrumentation.context.assets.open("quality/$name").use { it.readBytes() }
                        return MockResponse().setHeader("Content-Type", if (name.endsWith("m3u8")) "application/vnd.apple.mpegurl" else "video/mp2t")
                            .setBody(Buffer().write(bytes))
                    }
                    val episodes = (1..3).joinToString("#") { "Episode $it${'$'}${server.url("/high.m3u8?episode=$it")}" }
                    return MockResponse().setBody("""{"list":[{"vod_id":"remote","vod_name":"Remote test","vod_play_from":"Native","vod_play_url":"$episodes"}]}""")
                }
            }
            val config = SourceConfig(sourceId, "Remote control test", SourceType.TVBOX, server.url("/cms").toString())
            val source = TvboxSource(Provider { OkHttpClient() }, Dispatchers.Default, Provider { error("CMS must not start a Spider") })
            val item = source.search(config, "remote", 1).single()
            val episodes = source.detail(config, item.id).playGroups.single().episodes
            refs = episodes.map { it.ref }
            try {
                ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                    scenario.onActivity { repository = it.sources }
                    repository!!.upsert(config)
                }
                val request = PlayRequest(PlayKind.VOD, sourceId, refs[1], "Remote test", mapOf("itemId" to item.id))
                ActivityScenario.launch<PlayerActivity>(PlayerActivity.intent(instrumentation.targetContext, request)).use { scenario ->
                    scenario.onActivity { model = ViewModelProvider(it)[PlayerViewModel::class.java] }
                    val vm = model!!
                    waitUntil(scenario) { vm.currentRequest?.ref == refs[1] && vm.durationMs() > 20_000 && vm.ui.value.episodes.size == 3 && vm.ui.value.playback.isPlaying }
                    press(KeyEvent.KEYCODE_MEDIA_PAUSE)
                    waitUntil(scenario) { !vm.ui.value.playback.playWhenReady }
                    var start = 0L
                    scenario.onActivity { start = vm.positionMs() }
                    press(KeyEvent.KEYCODE_BACK)
                    scenario.onActivity { assertFalse(it.findViewById<View>(PlayerR.id.controls).isShown) }
                    press(KeyEvent.KEYCODE_DPAD_RIGHT)
                    waitUntil(scenario) { kotlin.math.abs(vm.positionMs() - start - 10_000) < 800 }
                    scenario.onActivity { assertTrue(it.findViewById<View>(PlayerR.id.progress).hasFocus()) }
                    press(KeyEvent.KEYCODE_MEDIA_REWIND)
                    waitUntil(scenario) { kotlin.math.abs(vm.positionMs() - start) < 800 }
                    press(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
                    waitUntil(scenario) { kotlin.math.abs(vm.positionMs() - start - 10_000) < 800 }
                    press(KeyEvent.KEYCODE_DPAD_LEFT)
                    waitUntil(scenario) { kotlin.math.abs(vm.positionMs() - start) < 800 }

                    press(KeyEvent.KEYCODE_DPAD_DOWN)
                    scenario.onActivity { assertTrue(it.findViewById<View>(PlayerR.id.play_pause).hasFocus()) }
                    press(KeyEvent.KEYCODE_DPAD_RIGHT)
                    scenario.onActivity { assertTrue(it.findViewById<View>(PlayerR.id.next).hasFocus()) }
                    press(KeyEvent.KEYCODE_DPAD_CENTER)
                    waitUntil(scenario) { vm.currentRequest?.ref == refs[2] && vm.ui.value.pendingTitle == null && vm.ui.value.playback.isPlaying }
                    press(KeyEvent.KEYCODE_BACK)
                    press(KeyEvent.KEYCODE_DPAD_CENTER)
                    scenario.onActivity { assertTrue(it.findViewById<View>(PlayerR.id.play_pause).hasFocus()) }
                    press(KeyEvent.KEYCODE_DPAD_LEFT)
                    scenario.onActivity { assertTrue(it.findViewById<View>(PlayerR.id.previous).hasFocus()) }
                    press(KeyEvent.KEYCODE_DPAD_CENTER)
                    waitUntil(scenario) { vm.currentRequest?.ref == refs[1] && vm.ui.value.pendingTitle == null && vm.ui.value.playback.isPlaying }
                    press(KeyEvent.KEYCODE_MEDIA_PAUSE)
                    waitUntil(scenario) { !vm.ui.value.playback.playWhenReady }
                    for (id in listOf(PlayerR.id.quality, PlayerR.id.speed, PlayerR.id.audio, PlayerR.id.subtitles, PlayerR.id.episodes)) {
                        navigateTo(scenario, id)
                        press(KeyEvent.KEYCODE_DPAD_CENTER)
                        delay(6_500)
                        scenario.onActivity { assertTrue("Controls stay visible under picker", it.findViewById<View>(PlayerR.id.controls).isShown) }
                        press(KeyEvent.KEYCODE_BACK)
                        scenario.onActivity { assertTrue("Picker restores its trigger", it.findViewById<View>(id).hasFocus()) }
                    }
                    navigateTo(scenario, PlayerR.id.speed)
                    press(KeyEvent.KEYCODE_DPAD_CENTER)
                    press(KeyEvent.KEYCODE_DPAD_DOWN)
                    press(KeyEvent.KEYCODE_DPAD_CENTER)
                    scenario.onActivity { assertEquals(1.25f, vm.playbackSpeed()) }
                    press(KeyEvent.KEYCODE_MENU)
                    scenario.onActivity { assertTrue((it.supportFragmentManager.findFragmentByTag("source-picker") as SourcePickerDialog).dialog!!.isShowing) }
                    press(KeyEvent.KEYCODE_BACK)
                    scenario.onActivity { assertNull(it.supportFragmentManager.findFragmentByTag("source-picker")) }
                    scenario.onActivity { assertTrue(it.findViewById<View>(PlayerR.id.controls).isShown) }
                    scenario.onActivity {
                        assertNull(vm.ui.value.error)
                        assertNull(vm.ui.value.webPage)
                        assertTrue(it.findViewById<View>(PlayerR.id.surface).isShown)
                        assertEquals(240, vm.ui.value.playback.videoHeight)
                    }
                }
            } finally {
                model?.let { vm ->
                    val history = field<HistoryRepository>(vm, "history")
                    field<Mutex>(vm, "historyWrites").withLock { refs.forEach { history.delete("$sourceId:$it") } }
                }
                repository?.delete(sourceId)
            }
        }
    }

    private fun navigateTo(scenario: ActivityScenario<PlayerActivity>, id: Int) {
        var keys: List<Int>? = null
        scenario.onActivity { activity ->
            val target = activity.findViewById<View>(id)
            val queue = ArrayDeque<Pair<View, List<Int>>>()
            queue.add(checkNotNull(activity.currentFocus) to emptyList())
            val visited = mutableSetOf<View>()
            val directions = listOf(View.FOCUS_LEFT to KeyEvent.KEYCODE_DPAD_LEFT, View.FOCUS_RIGHT to KeyEvent.KEYCODE_DPAD_RIGHT,
                View.FOCUS_UP to KeyEvent.KEYCODE_DPAD_UP, View.FOCUS_DOWN to KeyEvent.KEYCODE_DPAD_DOWN)
            while (queue.isNotEmpty()) {
                val (view, route) = queue.removeFirst()
                if (!visited.add(view)) continue
                if (view === target) { keys = route; break }
                directions.filterNot { (direction, _) -> view.id == PlayerR.id.progress &&
                    (direction == View.FOCUS_LEFT || direction == View.FOCUS_RIGHT) }.forEach { (direction, key) ->
                    view.focusSearch(direction)?.takeIf { it.isShown && it.isEnabled }?.let { queue.add(it to (route + key)) }
                }
            }
        }
        checkNotNull(keys) { "Unreachable player control $id" }.forEach(::press)
        scenario.onActivity { assertTrue(it.findViewById<View>(id).hasFocus()) }
    }

    private fun press(key: Int) {
        instrumentation.sendKeyDownUpSync(key)
        instrumentation.waitForIdleSync()
    }

    private suspend fun waitUntil(scenario: ActivityScenario<PlayerActivity>, ready: () -> Boolean) = withTimeout(20_000) {
        while (true) {
            var complete = false
            scenario.onActivity { complete = ready() }
            if (complete) return@withTimeout
            delay(50)
        }
    }

    private inline fun <reified T> field(model: PlayerViewModel, name: String): T =
        PlayerViewModel::class.java.getDeclaredField(name).apply { isAccessible = true }.get(model) as T
}
