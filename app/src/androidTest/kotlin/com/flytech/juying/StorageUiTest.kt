package com.flytech.juying

import android.content.Context
import android.graphics.Rect
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.view.SurfaceView
import android.view.ViewGroup
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.ui.MediaRowAdapter
import com.flytech.juying.feature.player.PlayerActivity
import com.flytech.juying.feature.player.PlayerViewModel
import com.flytech.juying.player.api.PlayerTrackType
import com.flytech.juying.player.media3.JuyingDataSourceFactory
import com.flytech.juying.player.media3.Media3Engine
import com.flytech.juying.source.local.LocalSource
import com.flytech.juying.source.local.LocalStorage
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import com.flytech.juying.feature.browse.R as BrowseR
import com.flytech.juying.feature.player.R as PlayerR

@RunWith(AndroidJUnit4::class)
class StorageUiTest {
    @Test fun deviceStorageUsesOwnBrowserAndRestoresDirectoryAfterPlayback(): Unit = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        assertTrue("Grant file access before running the device-storage test", LocalStorage.hasFileAccess(context))
        val sourceId = "storage:volume:primary"
        val prefs = context.getSharedPreferences("source_browse", Context.MODE_PRIVATE)
        fun ownedKey(key: String) = key == "selected.BROWSE" || key.startsWith("$sourceId.")
        val saved = prefs.all.filterKeys(::ownedKey)
        prefs.edit().also { editor -> saved.keys.forEach { editor.remove(it) } }.commit()
        val folder = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "JuyingTest-${UUID.randomUUID()}")
        val video = File(folder, "test-pattern.mp4")
        val subtitle = File(folder, "test-pattern.zh.srt")
        var scenario: ActivityScenario<MainActivity>? = null
        var player: PlayerActivity? = null
        try {
            assertTrue(folder.mkdirs())
            instrumentation.context.assets.open("test-pattern.mp4").use { input -> video.outputStream().use { output -> input.copyTo(output) } }
            subtitle.writeText("1\n00:00:00,000 --> 00:00:07,000\nNative storage subtitle\n")
            lateinit var main: MainActivity
            scenario = ActivityScenario.launch(MainActivity::class.java)
            scenario.onActivity { main = it; it.openSource(SourceCapability.BROWSE) }
            waitUntil("storage page") { main.findViewById<android.view.View>(BrowseR.id.add_storage) != null }
            withContext(Dispatchers.Main) { main.findViewById<android.view.View>(BrowseR.id.add_storage).takeIf { it.isShown }?.performClick() }
            waitUntil("storage root") { row(main, sourceId, byId = true) != null }
            capture("17-storage-roots")
            withContext(Dispatchers.Main) { assertTrue(checkNotNull(row(main, sourceId, byId = true)).itemView.performClick()) }
            waitUntil("Download directory") { row(main, Environment.DIRECTORY_DOWNLOADS) != null }
            withContext(Dispatchers.Main) { assertTrue(checkNotNull(row(main, Environment.DIRECTORY_DOWNLOADS)).itemView.performClick()) }
            waitUntil("fixture directory") { row(main, folder.name) != null }
            withContext(Dispatchers.Main) { assertTrue(checkNotNull(row(main, folder.name)).itemView.performClick()) }
            // A short landscape viewport may show only one row at a time.
            waitUntil("subtitle row") { row(main, subtitle.name) != null }
            waitUntil("video row") { row(main, video.name) != null }
            capture("18-storage-files")
            withContext(Dispatchers.Main) {
                assertEquals(folder.name, currentDirectory(main))
                assertTrue(checkNotNull(row(main, video.name)).itemView.performClick())
            }
            waitUntil("player activity") {
                player = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED)
                    .filterIsInstance<PlayerActivity>().singleOrNull()
                player != null
            }
            val activity = checkNotNull(player)
            val model = withContext(Dispatchers.Main) { ViewModelProvider(activity).get(PlayerViewModel::class.java) }
            waitUntil("local playback") {
                check(model.ui.value.error == null && model.ui.value.playback.error == null) { "Local playback failed" }
                model.ui.value.playback.isPlaying && model.positionMs() >= 1_000
            }
            withContext(Dispatchers.Main) {
                assertEquals(320, model.ui.value.playback.videoWidth)
                assertEquals(240, model.ui.value.playback.videoHeight)
                assertTrue(activity.findViewById<SurfaceView>(PlayerR.id.surface).isShown)
            }
            waitUntil("subtitle track") { model.tracks(PlayerTrackType.SUBTITLE).any { it.selected && it.label.contains("zh") } }
            withContext(Dispatchers.Main) { model.seekTo(3_000) }
            waitUntil("seek") { model.ui.value.playback.isPlaying && model.positionMs() >= 3_000 }
            val afterSeek = withContext(Dispatchers.Main) { model.positionMs() }
            waitUntil("progress after seek") { model.positionMs() >= afterSeek + 300 }
            withContext(Dispatchers.Main) {
                assertEquals(null, model.ui.value.playback.error)
                activity.onBackPressedDispatcher.onBackPressed()
                if (!activity.isFinishing) activity.onBackPressedDispatcher.onBackPressed()
            }
            waitUntil("return to directory") {
                ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).contains(main) &&
                    currentDirectory(main) == folder.name && row(main, video.name) != null
            }
            withContext(Dispatchers.Main) { assertEquals(sourceId, main.memory.selected(SourceCapability.BROWSE)) }
            capture("19-storage-return")
        } finally {
            withContext(Dispatchers.Main) { player?.takeUnless { it.isFinishing || it.isDestroyed }?.finish() }
            scenario?.close()
            video.delete(); subtitle.delete(); folder.delete()
            val editor = prefs.edit()
            prefs.all.keys.filter(::ownedKey).forEach { editor.remove(it) }
            saved.forEach { (key, value) -> editor.putString(key, value as String) }
            editor.commit()
        }
    }

    @Test fun documentTreeVideoAndSidecarDecodeOnNativeSurface() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val app = context.applicationContext as JuyingApplication
        val tree = DocumentsContract.buildTreeDocumentUri("com.flytech.juying.test.storage", "root")
        val config = LocalStorage.configForTree(context, tree)
        val source = LocalSource(context, Dispatchers.IO)
        val folder = source.list(config, "").single()
        assertTrue(folder.isDirectory)
        val files = source.list(config, folder.path)
        val video = files.single { it.isVideo }
        val play = source.playItem(config, video, files)
        assertEquals("content", Uri.parse(play.url).scheme)
        assertEquals("root/Movies/test-pattern.zh.srt", DocumentsContract.getDocumentId(Uri.parse(play.subtitles.single().url)))
        ActivityScenario.launch(MainActivity::class.java).use { activity ->
            lateinit var engine: Media3Engine
            activity.onActivity {
                val surface = SurfaceView(it)
                it.addContentView(surface, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
                engine = Media3Engine(it, app.deviceProfile.get(), AppSettings(), JuyingDataSourceFactory(it, OkHttpClient(), emptyMap()))
                engine.setSurfaceView(surface)
                engine.prepare(play)
            }
            try {
                withContext(Dispatchers.Main) {
                    withTimeout(PLAYBACK_TIMEOUT_MS) {
                        while (!engine.state.value.isPlaying || engine.positionMs() < 1_000) {
                            check(engine.state.value.error == null) { engine.state.value.error.orEmpty() }
                            delay(POLL_INTERVAL_MS)
                        }
                    }
                    assertEquals(320, engine.state.value.videoWidth)
                    assertEquals(240, engine.state.value.videoHeight)
                    engine.seekTo(3_000)
                    withTimeout(PLAYBACK_TIMEOUT_MS) {
                        while (!engine.state.value.isPlaying || engine.positionMs() < 3_000) delay(POLL_INTERVAL_MS)
                    }
                    assertEquals(null, engine.state.value.error)
                }
            } finally { withContext(Dispatchers.Main) { engine.release() } }
        }
    }

    private fun currentDirectory(activity: MainActivity): String? =
        (activity.findViewById<RecyclerView>(BrowseR.id.breadcrumbs)?.adapter as? com.flytech.juying.core.ui.TextChoiceAdapter)
            ?.currentList?.singleOrNull { it.selected }?.label

    private fun row(activity: MainActivity, value: String, byId: Boolean = false): RecyclerView.ViewHolder? {
        val list = activity.findViewById<RecyclerView>(BrowseR.id.files) ?: return null
        val adapter = list.adapter as? MediaRowAdapter ?: return null
        val index = adapter.currentList.indexOfFirst { if (byId) it.id == value else it.title == value }
        if (index < 0) return null
        return list.findViewHolderForAdapterPosition(index)?.takeIf {
            it.itemView.isShown && it.itemView.getGlobalVisibleRect(Rect())
        } ?: run { list.scrollToPosition(index); null }
    }

    private suspend fun waitUntil(stage: String, condition: () -> Boolean) = withContext(Dispatchers.Main) {
        try {
            withTimeout(PLAYBACK_TIMEOUT_MS) { while (!condition()) delay(POLL_INTERVAL_MS) }
        } catch (timeout: TimeoutCancellationException) {
            throw AssertionError("Timed out waiting for $stage", timeout)
        }
    }

    private suspend fun capture(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        delay(500) // Wait for list drawing and Activity transitions to reach the compositor.
        instrumentation.waitForIdleSync()
        val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            val output = File(instrumentation.targetContext.getExternalFilesDir(null), "ui-check/$name.png")
            output.parentFile!!.mkdirs()
            output.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        } finally { bitmap.recycle() }
    }

    private companion object {
        const val PLAYBACK_TIMEOUT_MS = 15_000L
        const val POLL_INTERVAL_MS = 100L
    }
}
