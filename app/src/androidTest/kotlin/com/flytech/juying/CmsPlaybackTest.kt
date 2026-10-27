package com.flytech.juying

import android.view.SurfaceView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.network.fetchText
import com.flytech.juying.player.media3.JuyingDataSourceFactory
import com.flytech.juying.player.media3.Media3Engine
import com.flytech.juying.player.api.PlayerTrackType
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.source.tvbox.TvboxSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import javax.inject.Provider

@RunWith(AndroidJUnit4::class)
class CmsPlaybackTest {
    @Test fun qualitySelectionChangesTheDecodedVideoAndRestoresAuto() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext.applicationContext as JuyingApplication
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val name = request.requestUrl!!.encodedPath.substringAfterLast('/')
                    val bytes = instrumentation.context.assets.open("quality/$name").use { it.readBytes() }
                    return MockResponse().setHeader("Content-Type", if (name.endsWith("m3u8")) "application/vnd.apple.mpegurl" else "video/mp2t")
                        .setBody(Buffer().write(bytes))
                }
            }
            server.start()
            val streamUrl = server.url("/master.m3u8").toString()
            ActivityScenario.launch(MainActivity::class.java).use { activity ->
                lateinit var engine: Media3Engine
                activity.onActivity {
                    val surface = SurfaceView(it)
                    it.setContentView(surface)
                    engine = Media3Engine(it, app.deviceProfile.get(), AppSettings(), JuyingDataSourceFactory(it, OkHttpClient(), emptyMap()))
                    engine.setSurfaceView(surface)
                    engine.prepare(PlayItem("quality-test", "Self-generated HLS", streamUrl))
                }
                try {
                    withContext(Dispatchers.Main) {
                        withTimeout(15_000) { while (engine.tracks(PlayerTrackType.VIDEO).size != 2) delay(100) }
                        val tracks = engine.tracks(PlayerTrackType.VIDEO)
                        val high = tracks.single { it.label.startsWith("320 × 240") }
                        val low = tracks.single { it.label.startsWith("160 × 120") }
                        engine.selectTrack(PlayerTrackType.VIDEO, high.id)
                        withTimeout(15_000) { while (engine.state.value.videoHeight != 240 || !engine.state.value.isPlaying) delay(100) }
                        engine.selectTrack(PlayerTrackType.VIDEO, low.id)
                        withTimeout(15_000) { while (engine.state.value.videoHeight != 120 || !engine.state.value.isPlaying) delay(100) }
                        assertEquals(low.id, engine.tracks(PlayerTrackType.VIDEO).single { it.selected }.id)
                        engine.selectTrack(PlayerTrackType.AUDIO, high.id)
                        engine.selectTrack(PlayerTrackType.VIDEO, "invalid:id")
                        assertEquals(low.id, engine.tracks(PlayerTrackType.VIDEO).single { it.selected }.id)
                        engine.selectTrack(PlayerTrackType.VIDEO, null)
                        assertTrue(engine.tracks(PlayerTrackType.VIDEO).none { it.selected })
                        engine.setPlaybackSpeed(1.5f)
                        assertEquals(1.5f, engine.playbackSpeed(), .01f)
                        assertTrue(engine.positionMs() > 0)
                        assertEquals(null, engine.state.value.error)
                    }
                } finally { withContext(Dispatchers.Main) { engine.release() } }
            }
        }
    }

    @Test fun networkTextBodyCanLoadOnMainDispatcher() = runBlocking {
        val server = MockWebServer()
        server.enqueue(MockResponse().setBody("delayed response").setBodyDelay(200, java.util.concurrent.TimeUnit.MILLISECONDS))
        server.start()
        try {
            val url = server.url("/").toString()
            val body = withContext(Dispatchers.Main) { OkHttpClient().fetchText(url) }
            assertEquals("delayed response", body)
        } finally { server.shutdown() }
    }

    @Test fun cmsCategoryToEpisodeDecodesOnNativeSurface() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext.applicationContext as JuyingApplication
        val server = MockWebServer()
        val video = instrumentation.context.assets.open("test-pattern.mp4").use { it.readBytes() }
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.requestUrl!!.encodedPath == "/video.mp4" ->
                    MockResponse().setHeader("Content-Type", "video/mp4").setBody(Buffer().write(video))
                request.requestUrl!!.queryParameter("ac") == null ->
                    MockResponse().setBody("""{"class":[{"type_id":"test","type_name":"自制测试片"}]}""")
                else -> MockResponse().setBody("""{"list":[{"vod_id":"pattern","vod_name":"自制测试片","vod_play_from":"原生","vod_play_url":"正片${'$'}${server.url("/video.mp4")}"}]}""")
            }
        }
        server.start()
        try {
            val client = OkHttpClient()
            val source = TvboxSource(Provider { client }, Dispatchers.Default, Provider { error("CMS must not start a Spider") })
            val config = SourceConfig("cms-test", "CMS 测试", SourceType.TVBOX, server.url("/cms").toString())
            val category = source.categories(config).single()
            val item = source.list(config, category.id, 1).single()
            assertEquals(item.id, source.search(config, "自制测试片", 1).single().id)
            val detail = source.detail(config, item.id)
            val play = source.resolve(config, detail.playGroups.single().episodes.single().ref)
            ActivityScenario.launch(MainActivity::class.java).use { activity ->
                lateinit var engine: Media3Engine
                activity.onActivity {
                    val surface = SurfaceView(it)
                    it.setContentView(surface)
                    engine = Media3Engine(it, app.deviceProfile.get(), AppSettings(), JuyingDataSourceFactory(it, client, emptyMap()))
                    engine.setSurfaceView(surface)
                    engine.prepare(play)
                }
                try {
                    withContext(Dispatchers.Main) {
                        withTimeout(15_000) {
                            while (!engine.state.value.isPlaying || engine.positionMs() < 1_000) {
                                check(engine.state.value.error == null) { engine.state.value.error.orEmpty() }
                                delay(100)
                            }
                        }
                        assertEquals(320, engine.state.value.videoWidth)
                        assertEquals(240, engine.state.value.videoHeight)
                        assertTrue(engine.durationMs() >= 7_000)
                    }
                } finally {
                    withContext(Dispatchers.Main) { engine.release() }
                }
            }
        } finally {
            server.shutdown()
        }
    }
}
