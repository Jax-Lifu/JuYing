package com.flytech.juying

import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.PlaybackRoute
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.player.media3.JuyingDataSourceFactory
import com.flytech.juying.player.media3.Media3Engine
import com.flytech.juying.source.cctv.BUILTIN_CCTV_ID
import com.flytech.juying.source.cctv.CctvH5eDataSourceFactory
import com.flytech.juying.source.cctv.CctvSource
import com.flytech.juying.feature.player.PlayerActivity
import com.flytech.juying.feature.player.PlayerViewModel
import com.flytech.juying.player.api.PlayerTrackType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit
import java.util.concurrent.CountDownLatch
import javax.inject.Provider

/** Official-network opt-ins: cctvNativeLive=true for VOD; cctvLiveNative=true for live channels. */
@RunWith(AndroidJUnit4::class)
class CctvNativeHdTest {
    @Test fun officialLiveUsesNativeSurfaceRefreshesAndZapsChannels() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("cctvLiveNative") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext.applicationContext
        val request = PlayRequest(PlayKind.LIVE, BUILTIN_CCTV_ID, "cctv1", "CCTV-1 综合")
        ActivityScenario.launch<PlayerActivity>(PlayerActivity.intent(app, request)).use { scenario ->
            lateinit var model: PlayerViewModel
            lateinit var surface: SurfaceView
            scenario.onActivity {
                model = androidx.lifecycle.ViewModelProvider(it).get(PlayerViewModel::class.java)
                surface = it.findViewById(com.flytech.juying.feature.player.R.id.surface)
            }
            suspend fun playing(channel: String) = withContext(Dispatchers.Main) {
                withTimeout(60_000) {
                    while (model.currentRequest?.ref != channel || !model.ui.value.playback.isPlaying || model.positionMs() < 3_000 ||
                        model.ui.value.playback.videoHeight < 720) {
                        check(model.ui.value.error == null) { model.ui.value.error.orEmpty() }
                        check(model.ui.value.webPage == null) { "央视直播不应打开网页播放器" }
                        delay(200)
                    }
                }
                assertTrue(model.ui.value.playback.videoWidth >= 1280)
                assertTrue(model.ui.value.isLive)
                assertNull(model.ui.value.webPage)
                assertTrue(model.tracks(PlayerTrackType.AUDIO).any { it.selected })
                assertTrue(model.availableLines().first().url.startsWith("cctvcdrm+https://"))
                assertTrue(surface.isShown)
                instrumentation.sendStatus(0, Bundle().apply {
                    putString("stream", "CCTV_LIVE_UI channel=$channel width=${model.ui.value.playback.videoWidth} " +
                        "height=${model.ui.value.playback.videoHeight} position=${model.positionMs()}\n")
                })
            }
            playing("cctv1")
            assertRenderedFrame(surface)
            // Stay beyond the initial playlist window so stale/one-shot manifests cannot pass.
            repeat(4) { delay(20_000); playing("cctv1"); assertRenderedFrame(surface) }
            scenario.onActivity {
                if (!it.findViewById<View>(com.flytech.juying.feature.player.R.id.controls).isShown)
                    it.findViewById<View>(com.flytech.juying.feature.player.R.id.video_stage).performClick()
                assertFalse(it.findViewById<View>(com.flytech.juying.feature.player.R.id.web_container).isShown)
                it.findViewById<View>(com.flytech.juying.feature.player.R.id.next).performClick()
            }
            playing("cctv2")
            assertRenderedFrame(surface)
            withContext(Dispatchers.Main) { model.zap(3) }
            playing("cctv5")
            assertRenderedFrame(surface)
            withContext(Dispatchers.Main) { model.zap(9) }
            playing("cctv13")
            assertRenderedFrame(surface)
        }
    }

    @Test fun officialLiveQualityDefaultsHighSwitchesAndRestoresAuto() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("cctvLiveNative") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext.applicationContext
        val request = PlayRequest(PlayKind.LIVE, BUILTIN_CCTV_ID, "cctv1", "CCTV-1 综合")
        ActivityScenario.launch<PlayerActivity>(PlayerActivity.intent(app, request)).use { scenario ->
            lateinit var model: PlayerViewModel
            lateinit var surface: SurfaceView
            lateinit var autoLabel: String
            scenario.onActivity {
                model = androidx.lifecycle.ViewModelProvider(it).get(PlayerViewModel::class.java)
                surface = it.findViewById(com.flytech.juying.feature.player.R.id.surface)
                autoLabel = it.getString(com.flytech.juying.feature.player.R.string.player_auto_quality)
            }
            data class Quality(val id: String, val label: String, val width: Int, val height: Int)
            val qualities = withContext(Dispatchers.Main) {
                withTimeout(60_000) {
                    while (model.tracks(PlayerTrackType.VIDEO).size < 2) {
                        check(model.ui.value.error == null) { "央视直播清晰度加载失败" }
                        delay(100)
                    }
                }
                model.tracks(PlayerTrackType.VIDEO).map { track ->
                    val size = checkNotNull(Regex("""^(\d+)\s*×\s*(\d+)""").find(track.label)) { "视频档位缺少分辨率" }
                    Quality(track.id, track.label, size.groupValues[1].toInt(), size.groupValues[2].toInt())
                }.sortedWith(compareBy<Quality> { it.height }.thenBy { it.width })
            }
            val low = qualities.first()
            val high = qualities.last()
            assertTrue("央视直播应提供不同分辨率", high.height > low.height)
            assertTrue("默认最高档应至少为 720p", high.height >= 720)
            withContext(Dispatchers.Main) {
                withTimeout(60_000) { while (model.ui.value.playback.videoHeight == 0) delay(100) }
                assertEquals("首次解码应使用最高档", high.height, model.ui.value.playback.videoHeight)
                assertEquals(high.width, model.ui.value.playback.videoWidth)
            }
            suspend fun playingQuality(stage: String, quality: Quality? = null) {
                withContext(Dispatchers.Main) {
                    withTimeout(60_000) {
                        while (!model.ui.value.playback.isPlaying || model.ui.value.playback.videoHeight == 0 ||
                            (quality != null && (model.ui.value.playback.videoWidth != quality.width ||
                                model.ui.value.playback.videoHeight != quality.height))) {
                            check(model.ui.value.error == null) { "央视直播清晰度切换失败" }
                            check(model.ui.value.webPage == null) { "央视直播不应打开网页播放器" }
                            delay(100)
                        }
                    }
                    var previousPosition = model.positionMs()
                    var previousTime = SystemClock.elapsedRealtime()
                    var advancedMs = 0L
                    var advancingSamples = 0
                    // Live playlist refreshes move the window origin; require steady progress between resets.
                    withTimeout(10_000) {
                        while (advancedMs < 1_000 || advancingSamples < 5) {
                            delay(200)
                            val position = model.positionMs()
                            val now = SystemClock.elapsedRealtime()
                            val delta = position - previousPosition
                            val advancing = position >= 0 && delta in 1..((now - previousTime) * 2 + 100) &&
                                model.ui.value.playback.isPlaying
                            advancedMs = if (advancing) advancedMs + delta else 0L
                            advancingSamples = if (advancing) advancingSamples + 1 else 0
                            previousPosition = position
                            previousTime = now
                        }
                    }
                    assertTrue(surface.isShown)
                    assertTrue(model.ui.value.isLive)
                    assertNull(model.ui.value.error)
                    assertNull(model.ui.value.webPage)
                    instrumentation.sendStatus(0, Bundle().apply {
                        putString("stream", "CCTV_LIVE_QUALITY stage=$stage tracks=${qualities.size} " +
                            "width=${model.ui.value.playback.videoWidth} height=${model.ui.value.playback.videoHeight} " +
                            "position=${model.positionMs()}\n")
                    })
                }
                assertRenderedFrame(surface)
            }
            suspend fun selectQuality(label: String) {
                scenario.onActivity {
                    if (!it.findViewById<View>(com.flytech.juying.feature.player.R.id.controls).isShown)
                        it.findViewById<View>(com.flytech.juying.feature.player.R.id.video_stage).performClick()
                    it.findViewById<View>(com.flytech.juying.feature.player.R.id.quality).performClick()
                }
                withTimeout(5_000) {
                    while (true) {
                        val root = instrumentation.uiAutomation.rootInActiveWindow
                        val option = root?.findAccessibilityNodeInfosByText(label)?.firstOrNull { it.text?.toString() == label }
                        if (root != null && option != null) {
                            assertTrue("清晰度弹窗应显示自动项", root.findAccessibilityNodeInfosByText(autoLabel).isNotEmpty())
                            assertTrue("清晰度弹窗应显示多个档位", qualities.count {
                                root.findAccessibilityNodeInfosByText(it.label).isNotEmpty()
                            } >= 2)
                            val clickable = generateSequence(option) { it.parent }.firstOrNull { it.isClickable && it.isEnabled }
                            if (clickable?.performAction(AccessibilityNodeInfo.ACTION_CLICK) != true) {
                                // TV dialogs may expose the label without an accessibility click action.
                                val fresh = instrumentation.uiAutomation.rootInActiveWindow
                                    ?.findAccessibilityNodeInfosByText(label)?.firstOrNull { it.text?.toString() == label }
                                if (fresh == null) { delay(100); continue }
                                val bounds = Rect().also(fresh::getBoundsInScreen)
                                assertTrue("清晰度选项应在屏幕内可见", fresh.isVisibleToUser && !bounds.isEmpty)
                                val downTime = SystemClock.uptimeMillis()
                                for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
                                    val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action,
                                        bounds.exactCenterX(), bounds.exactCenterY(), 0)
                                    try { instrumentation.sendPointerSync(event) } finally { event.recycle() }
                                }
                            }
                            break
                        }
                        delay(100)
                    }
                }
            }
            playingQuality("initial-high", high)
            scenario.onActivity {
                assertEquals("单线路央视直播不显示线路按钮", View.GONE,
                    it.findViewById<View>(com.flytech.juying.feature.player.R.id.lines).visibility)
            }
            for (quality in qualities.dropLast(1)) {
                selectQuality(quality.label)
                playingQuality("manual-${quality.height}p", quality)
                withContext(Dispatchers.Main) { assertEquals(quality.id, model.tracks(PlayerTrackType.VIDEO).single { it.selected }.id) }
            }
            selectQuality(high.label)
            playingQuality("manual-high", high)
            withContext(Dispatchers.Main) { assertEquals(high.id, model.tracks(PlayerTrackType.VIDEO).single { it.selected }.id) }
            selectQuality(autoLabel)
            playingQuality("auto")
            withContext(Dispatchers.Main) { assertTrue(model.tracks(PlayerTrackType.VIDEO).none { it.selected }) }
        }
    }

    @Test fun officialHdDecodesOnSurfaceSeeksBothWaysAndChangesEpisode() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("cctvNativeLive") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext.applicationContext as JuyingApplication
        val client = OkHttpClient.Builder().callTimeout(25, TimeUnit.SECONDS).build()
        val source = CctvSource(Provider { client }, Dispatchers.Default)
        val config = SourceConfig(BUILTIN_CCTV_ID, "央视", SourceType.CCTV, "")
        val album = args.getString("cctvAlbumId") ?: "VIDA8lgsyrdD1LuVvEdkr2Fd260625"
        val detail = withTimeout(60_000) { source.detail(config, album) }
        val episodes = detail.playGroups.first().episodes
        assertTrue("验收专辑需要至少两集", episodes.size >= 2)
        val first = source.resolve(config, episodes[0].ref)
        assertEquals(PlaybackRoute.NATIVE, first.route)
        assertTrue(first.url.startsWith("cctvh5e+https://"))
        val factory = CctvH5eDataSourceFactory(Provider { client })
        val schemes = mapOf("cctvh5e+https" to factory, "cctvh5e+http" to factory)
        ActivityScenario.launch(MainActivity::class.java).use { activity ->
            lateinit var engine: Media3Engine
            lateinit var surface: SurfaceView
            activity.onActivity {
                surface = SurfaceView(it)
                it.addContentView(surface, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
                engine = Media3Engine(it, app.deviceProfile.get(), AppSettings(), JuyingDataSourceFactory(it, client, schemes))
                engine.setSurfaceView(surface)
                engine.prepare(first)
            }
            suspend fun playingBeyond(positionMs: Long) = withContext(Dispatchers.Main) {
                withTimeout(60_000) {
                    while (!engine.state.value.isPlaying || engine.positionMs() < positionMs || engine.state.value.videoHeight < 720) {
                        check(engine.state.value.error == null) { engine.state.value.error.orEmpty() }
                        delay(200)
                    }
                }
                assertTrue(engine.state.value.videoWidth >= 1280)
                assertTrue("高清应保留整集时间轴", engine.durationMs() > 300_000)
                instrumentation.sendStatus(0, Bundle().apply {
                    putString("stream", "CCTV_HD width=${engine.state.value.videoWidth} height=${engine.state.value.videoHeight} " +
                        "position=${engine.positionMs()} duration=${engine.durationMs()}\n")
                })
            }
            try {
                playingBeyond(3_000)
                assertRenderedFrame(surface)
                withContext(Dispatchers.Main) { engine.seekTo(120_000) }
                playingBeyond(121_000)
                withContext(Dispatchers.Main) { engine.seekTo(20_000) }
                playingBeyond(21_000)
                withContext(Dispatchers.Main) { assertTrue(engine.positionMs() < 60_000) }
                val second = source.resolve(config, episodes[1].ref)
                assertEquals(PlaybackRoute.NATIVE, second.route)
                assertNotEquals(first.url, second.url)
                withContext(Dispatchers.Main) { engine.prepare(second) }
                playingBeyond(3_000)
                assertRenderedFrame(surface)
                withContext(Dispatchers.Main) { assertTrue(engine.positionMs() < 60_000) }
            } finally { withContext(Dispatchers.Main) { engine.release() } }
        }

        // Launch the real Hilt-backed screen: no manual engine or scheme map can mask a missing binding.
        val request = PlayRequest(PlayKind.VOD, BUILTIN_CCTV_ID, episodes[0].ref, episodes[0].name,
            mapOf("itemId" to album, "mediaTitle" to detail.item.title, "episodeTitle" to episodes[0].name))
        ActivityScenario.launch<PlayerActivity>(PlayerActivity.intent(app, request)).use { scenario ->
            lateinit var model: PlayerViewModel
            lateinit var surface: SurfaceView
            scenario.onActivity {
                model = androidx.lifecycle.ViewModelProvider(it).get(PlayerViewModel::class.java)
                surface = it.findViewById(com.flytech.juying.feature.player.R.id.surface)
            }
            suspend fun screenPlaying(ref: String) = withContext(Dispatchers.Main) {
                withTimeout(60_000) {
                    while (model.currentRequest?.ref != ref || !model.ui.value.playback.isPlaying ||
                        model.positionMs() < 3_000 || model.ui.value.playback.videoHeight < 720 || model.ui.value.episodes.size < 2) {
                        check(model.ui.value.error == null) { model.ui.value.error.orEmpty() }
                        check(model.ui.value.webPage == null) { "央视高清不应打开网页播放器" }
                        delay(200)
                    }
                }
                assertTrue(model.ui.value.playback.videoWidth >= 1280)
                assertTrue(model.durationMs() > 300_000)
                assertTrue(model.availableLines().first().url.startsWith("cctvh5e+https://"))
                assertTrue(surface.isShown)
                assertNull(model.ui.value.webPage)
                instrumentation.sendStatus(0, Bundle().apply {
                    putString("stream", "CCTV_HD_UI width=${model.ui.value.playback.videoWidth} height=${model.ui.value.playback.videoHeight} " +
                        "position=${model.positionMs()} duration=${model.durationMs()} episodes=${model.ui.value.episodes.size}\n")
                })
            }
            screenPlaying(episodes[0].ref)
            assertRenderedFrame(surface)
            scenario.onActivity {
                if (!it.findViewById<View>(com.flytech.juying.feature.player.R.id.controls).isShown)
                    it.findViewById<View>(com.flytech.juying.feature.player.R.id.video_stage).performClick()
                assertTrue(it.findViewById<View>(com.flytech.juying.feature.player.R.id.progress).isEnabled)
                assertTrue(it.findViewById<View>(com.flytech.juying.feature.player.R.id.episodes).isEnabled)
                assertFalse(it.findViewById<View>(com.flytech.juying.feature.player.R.id.web_container).isShown)
                it.findViewById<View>(com.flytech.juying.feature.player.R.id.next).performClick()
            }
            screenPlaying(episodes[1].ref)
            assertRenderedFrame(surface)
        }
    }

    private fun assertRenderedFrame(surface: SurfaceView) {
        val bitmap = Bitmap.createBitmap(96, 54, Bitmap.Config.ARGB_8888)
        val copied = CountDownLatch(1)
        var status = PixelCopy.ERROR_UNKNOWN
        try {
            PixelCopy.request(surface, bitmap, { status = it; copied.countDown() }, Handler(Looper.getMainLooper()))
            assertTrue("SurfaceView 截帧超时", copied.await(5, TimeUnit.SECONDS))
            assertEquals(PixelCopy.SUCCESS, status)
            val pixels = IntArray(bitmap.width * bitmap.height)
            bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            assertTrue("SurfaceView 未渲染有效画面", pixels.toSet().size > 16)
        } finally { bitmap.recycle() }
    }
}
