package com.flytech.juying.player.media3

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.ExoPlayer
import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.DeviceForm
import com.flytech.juying.core.model.DeviceProfile
import com.flytech.juying.core.model.PerformanceTier
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.player.api.PlayerTrackType
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
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class Media3InitialQualityTest {
    private lateinit var engine: Media3Engine
    private lateinit var player: ExoPlayer
    private lateinit var listener: Player.Listener
    private val item = PlayItem("live", "Live", "https://quality.test/empty.m3u8", preferHighestVideoQuality = true)
    private val video = TrackGroup(
        video(1280, 720, 8_000_000),
        video(1920, 1080, 3_000_000),
        video(1920, 1080, 5_000_000),
    )
    private val videoTracks = Tracks(listOf(group(video)))

    @Before fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-ENDLIST\n".toResponseBody("application/vnd.apple.mpegurl".toMediaType())).build()
        }.build()
        engine = Media3Engine(context, DeviceProfile(DeviceForm.TV, PerformanceTier.LOW, 2048), AppSettings(),
            JuyingDataSourceFactory(context, client, emptyMap()))
        // Deliver deterministic track notifications without networking or a device codec.
        player = Media3Engine::class.java.getDeclaredField("player").apply { isAccessible = true }.get(engine) as ExoPlayer
        listener = Media3Engine::class.java.getDeclaredField("listener").apply { isAccessible = true }.get(engine) as Player.Listener
    }

    @After fun tearDown() { engine.release() }

    @Test fun `initial video choice uses resolution then bitrate and leaves audio alone`() {
        val audio = TrackGroup(Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).build())
        val audioOverride = TrackSelectionOverride(audio, 0)
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon().addOverride(audioOverride).build()
        engine.prepare(item)
        listener.onTracksChanged(Tracks(listOf(group(audio))))
        assertFalse(player.trackSelectionParameters.overrides.containsKey(video))
        listener.onTracksChanged(videoTracks)
        assertEquals(listOf(2), player.trackSelectionParameters.overrides[video]?.trackIndices)
        assertEquals(audioOverride, player.trackSelectionParameters.overrides[audio])
    }

    @Test fun `later track callbacks preserve a manual choice and restored auto mode`() {
        engine.prepare(item)
        listener.onTracksChanged(videoTracks)
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .setOverrideForType(TrackSelectionOverride(video, 0)).build()
        listener.onTracksChanged(videoTracks)
        assertEquals(listOf(0), player.trackSelectionParameters.overrides[video]?.trackIndices)
        engine.selectTrack(PlayerTrackType.VIDEO, null)
        listener.onTracksChanged(videoTracks)
        assertTrue(player.trackSelectionParameters.overrides.isEmpty())
        engine.prepare(item)
        engine.selectTrack(PlayerTrackType.VIDEO, null)
        listener.onTracksChanged(videoTracks)
        assertTrue(player.trackSelectionParameters.overrides.isEmpty())
    }

    @Test fun `new items reset both pending selection and the previous video override`() {
        engine.prepare(item)
        engine.prepare(item.copy(id = "ordinary", preferHighestVideoQuality = false))
        listener.onTracksChanged(videoTracks)
        assertTrue(player.trackSelectionParameters.overrides.isEmpty())
        engine.prepare(item)
        listener.onTracksChanged(videoTracks)
        assertEquals(listOf(2), player.trackSelectionParameters.overrides[video]?.trackIndices)
        engine.prepare(item.copy(id = "ordinary", preferHighestVideoQuality = false))
        listener.onTracksChanged(videoTracks)
        assertTrue(player.trackSelectionParameters.overrides.isEmpty())
    }

    @Test fun `unsupported highest track is not silently replaced with a lower one`() {
        engine.prepare(item)
        listener.onTracksChanged(Tracks(listOf(group(video, intArrayOf(C.FORMAT_HANDLED, C.FORMAT_HANDLED, C.FORMAT_EXCEEDS_CAPABILITIES)))))
        assertEquals(listOf(2), player.trackSelectionParameters.overrides[video]?.trackIndices)
    }

    private fun video(width: Int, height: Int, bitrate: Int) = Format.Builder()
        .setSampleMimeType(MimeTypes.VIDEO_H264).setWidth(width).setHeight(height).setAverageBitrate(bitrate).build()

    private fun group(group: TrackGroup, support: IntArray = IntArray(group.length) { C.FORMAT_HANDLED }) =
        Tracks.Group(group, false, support, BooleanArray(group.length))
}
