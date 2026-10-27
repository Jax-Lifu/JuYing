package com.flytech.juying

import android.os.Bundle
import android.view.SurfaceView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.PlaybackRoute
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.player.media3.JuyingDataSourceFactory
import com.flytech.juying.player.media3.Media3Engine
import com.flytech.juying.source.tvbox.TvboxSource
import com.flytech.juying.source.tvbox.spider.SpiderClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import javax.inject.Provider

/** Opt-in field check: supply probeUrl/probeSites; never runs a public subscription in ordinary CI. */
@RunWith(AndroidJUnit4::class)
class TvboxPublicProbeTest {
    @Test fun inspectExplicitDownloadTransport() {
        val url = InstrumentationRegistry.getArguments().getString("probeDownload").orEmpty()
        assumeTrue(url.isNotBlank())
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        for (http1 in listOf(false, true)) for ((label, ua) in listOf(
            "default" to "Mozilla/5.0 (Linux; Android 9) AppleWebKit/537.36 JuYing/0.1",
            "browser" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36")) {
            val client = OkHttpClient.Builder().callTimeout(20, java.util.concurrent.TimeUnit.SECONDS).apply {
                if (http1) protocols(listOf(okhttp3.Protocol.HTTP_1_1))
            }.build()
            val result = try {
                client.newCall(okhttp3.Request.Builder().url(url).header("User-Agent", ua).build()).execute().use {
                    "code=${it.code} protocol=${it.protocol} bytes=${it.body!!.bytes().size}"
                }
            } catch (error: Exception) { error.javaClass.simpleName }
            instrumentation.sendStatus(0, Bundle().apply { putString("stream", "TRANSPORT http1=$http1 ua=$label $result\n") })
        }
    }

    @Test fun selectedSubscriptionReachesNativePlayback() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val url = args.getString("probeUrl").orEmpty()
        assumeTrue("Public probe requires an explicit subscription", url.isNotBlank())
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext.applicationContext as JuyingApplication
        fun report(value: String) = instrumentation.sendStatus(0, Bundle().apply { putString("stream", "PROBE $value\n") })
        val client = OkHttpClient.Builder().callTimeout(25, java.util.concurrent.TimeUnit.SECONDS).build()
        val spider = SpiderClient(app)
        val source = TvboxSource(Provider { client }, Dispatchers.Default, Provider { spider })
        val config = SourceConfig("public-probe", "订阅验证", SourceType.TVBOX, url)
        val sites = withTimeout(30_000) { source.subSources(config) }
        report("config sites=${sites.size}")
        val selected = args.getString("probeSites").orEmpty().split(',').filter(String::isNotBlank)
        require(selected.isNotEmpty()) { "Choose explicit site keys" }
        var played = 0
        for (key in selected) {
            var stage = "home"
            try {
                withTimeout(120_000) {
                    val categories = source.categories(config, key)
                    report("$key categories=${categories.size}")
                    stage = "list"
                    val item = categories.take(3).firstNotNullOfOrNull { source.list(config, it.id, 1).firstOrNull() }
                        ?: error("No content")
                    if (sites.first { it.id == key }.searchable) {
                        stage = "search"
                        val found = source.search(config, item.title, 1, key)
                        report("$key search=${found.size}")
                        check(found.isNotEmpty()) { "Search returned no items" }
                    } else report("$key search=unsupported-by-config")
                    stage = "detail"
                    val detail = source.detail(config, item.id)
                    report("$key groups=${detail.playGroups.size}")
                    stage = "resolve"
                    val play = source.resolve(config, detail.playGroups.first().episodes.first().ref)
                    report("$key route=${play.route}")
                    check(play.route == PlaybackRoute.NATIVE) { "Requires web playback" }
                    stage = "decode"
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
                                withTimeout(25_000) {
                                    while (!engine.state.value.isPlaying || engine.positionMs() < 2_000 || engine.state.value.videoWidth <= 0) {
                                        check(engine.state.value.error == null) { "Playback error" }
                                        delay(100)
                                    }
                                }
                                report("$key PLAYED ${engine.state.value.videoWidth}x${engine.state.value.videoHeight} position=${engine.positionMs()}")
                            }
                            played++
                        } finally { withContext(Dispatchers.Main) { engine.release() } }
                    }
                }
            } catch (error: Exception) { report("$key FAILED stage=$stage type=${error.javaClass.simpleName}") }
        }
        assertTrue("Every selected site must complete native playback: $played/${selected.size}", played == selected.size)
    }
}
