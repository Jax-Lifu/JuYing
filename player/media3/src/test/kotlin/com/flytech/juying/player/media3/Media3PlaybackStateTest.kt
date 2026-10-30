package com.flytech.juying.player.media3

import android.content.Intent
import android.media.AudioManager
import android.os.Looper
import androidx.media3.common.Timeline
import androidx.media3.exoplayer.ExoPlayer
import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.DeviceForm
import com.flytech.juying.core.model.DeviceProfile
import com.flytech.juying.core.model.PerformanceTier
import com.flytech.juying.core.model.PlayItem
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class Media3PlaybackStateTest {
    private lateinit var engine: Media3Engine
    private lateinit var player: ExoPlayer

    @Before fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val manifest = buildString {
                append("#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:100\n")
                repeat(10) { append("#EXTINF:6.0,\nsegment$it.ts\n") }
                if (chain.request().url.encodedPath.startsWith("/vod")) append("#EXT-X-ENDLIST\n")
            }
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(if (chain.request().url.encodedPath.endsWith(".m3u8")) 200 else 404).message("Test fixture")
                .body(manifest.toResponseBody("application/vnd.apple.mpegurl".toMediaType())).build()
        }.build()
        engine = Media3Engine(context, DeviceProfile(DeviceForm.TV, PerformanceTier.LOW, 2048), AppSettings(),
            JuyingDataSourceFactory(context, client, emptyMap()))
        player = Media3Engine::class.java.getDeclaredField("player").apply { isAccessible = true }.get(engine) as ExoPlayer
    }

    @After fun tearDown() { engine.release() }

    @Test fun `live startup and line changes follow the new windows default position`() {
        engine.prepare(PlayItem("live", "Live", "https://playback.test/live.m3u8", isLive = true))
        val first = awaitTimeline()
        assertTrue(first.isLive)
        assertTrue(first.defaultPositionMs > 0)
        assertEquals(first.defaultPositionMs, player.currentPosition)

        engine.prepare(PlayItem("backup", "Backup", "https://playback.test/backup.m3u8", isLive = true, startPositionMs = 6_000))
        val backup = awaitTimeline()
        assertEquals(backup.defaultPositionMs, player.currentPosition)
        assertTrue(player.currentPosition > 6_000)
    }

    @Test fun `vod retains its explicit resume position`() {
        engine.prepare(PlayItem("vod", "Episode", "https://playback.test/vod.m3u8", startPositionMs = 24_000))
        assertFalse(awaitTimeline().isLive)
        assertEquals(24_000L, player.currentPosition)
    }

    @Test fun `live resets vod speed while preserving paused playback intent`() {
        for (speed in listOf(.5f, 2f)) {
            engine.prepare(PlayItem("vod", "Episode", "https://playback.test/vod.m3u8"))
            engine.setPlaybackSpeed(speed)
            engine.pause()

            engine.prepare(PlayItem("live", "Live", "https://playback.test/live.m3u8", isLive = true))

            assertEquals(1f, engine.playbackSpeed())
            assertFalse(player.playWhenReady)
            assertFalse(engine.state.value.playWhenReady)
            engine.prepare(PlayItem("backup", "Backup", "https://playback.test/backup.m3u8", isLive = true))
            assertEquals(1f, engine.playbackSpeed())
        }
    }

    @Test fun `vod changes preserve the selected playback speed`() {
        engine.prepare(PlayItem("vod", "Episode", "https://playback.test/vod.m3u8"))
        engine.setPlaybackSpeed(2f)

        engine.prepare(PlayItem("vod-next", "Next", "https://playback.test/vod-next.m3u8"))

        assertEquals(2f, engine.playbackSpeed())
    }

    @Test fun `noisy output pauses playback intent while buffering and reprepare preserves it`() {
        val item = PlayItem("live", "Live", "https://playback.test/live.m3u8", isLive = true)
        engine.prepare(item)
        assertTrue(engine.state.value.playWhenReady)
        assertFalse(engine.state.value.isPlaying)

        RuntimeEnvironment.getApplication().sendBroadcast(Intent(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(player.playWhenReady)
        assertFalse(engine.state.value.playWhenReady)

        engine.prepare(item.copy(id = "backup", url = "https://playback.test/backup.m3u8"))
        assertFalse(engine.state.value.playWhenReady)
        engine.play()
        assertTrue(engine.state.value.playWhenReady)
    }

    private fun awaitTimeline(): Timeline.Window {
        val deadline = System.nanoTime() + 5_000_000_000L
        while (System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            val timeline = player.currentTimeline
            if (!timeline.isEmpty) {
                val window = timeline.getWindow(0, Timeline.Window())
                if (!window.isPlaceholder) return window
            }
            Thread.sleep(10)
        }
        throw AssertionError("Media3 did not publish the fixture timeline")
    }
}
