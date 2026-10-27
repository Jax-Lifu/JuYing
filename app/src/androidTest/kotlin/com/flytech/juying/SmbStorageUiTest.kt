package com.flytech.juying

import android.content.Context
import android.graphics.Rect
import android.net.Uri
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.SurfaceView
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.NavHostFragment
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.ui.MediaRowAdapter
import com.flytech.juying.feature.browse.BrowseFragment
import com.flytech.juying.feature.browse.BrowseViewModel
import com.flytech.juying.feature.browse.NasError
import com.flytech.juying.feature.browse.NasFragment
import com.flytech.juying.feature.browse.NasStage
import com.flytech.juying.feature.browse.NasViewModel
import com.flytech.juying.feature.player.PlayerActivity
import com.flytech.juying.feature.player.PlayerViewModel
import com.flytech.juying.player.api.PlayerTrackType
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import com.flytech.juying.feature.browse.R as BrowseR
import com.flytech.juying.feature.player.R as PlayerR

/** Opt-in LAN fixture: smbFixtureUrl, user and password are runner arguments and are never logged. */
@RunWith(AndroidJUnit4::class)
class SmbStorageUiTest {
    @Test fun nasKeyboardKeepsLoginFormVisible(): Unit = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.setInTouchMode(true)
        val prefs = instrumentation.targetContext.getSharedPreferences("source_browse", Context.MODE_PRIVATE)
        val previousPrefs = prefs.all
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                lateinit var main: MainActivity
                scenario.onActivity { main = it }
                val model = openNas(main)
                clickVisible(main, BrowseR.id.manual_address, "manual NAS login entry")
                waitUntil("NAS login window") { model.ui.value.stage == NasStage.LOGIN && main.hasWindowFocus() }
                val keyboard = main.getSystemService(InputMethodManager::class.java)
                try {
                    for ((id, label) in listOf(BrowseR.id.address to "address", BrowseR.id.username to "username", BrowseR.id.password to "password")) {
                        withContext(Dispatchers.Main) {
                            val field = main.findViewById<EditText>(id)
                            field.requestFocus()
                            keyboard.showSoftInput(field, InputMethodManager.SHOW_IMPLICIT)
                        }
                        waitUntil("visible keyboard for $label") {
                            keyboard.isFullscreenMode || ViewCompat.getRootWindowInsets(main.window.decorView)
                                ?.isVisible(WindowInsetsCompat.Type.ime()) == true
                        }
                        capture("27-nas-keyboard-$label")
                        withContext(Dispatchers.Main) {
                            assertFalse("NAS $label must not open the keyboard's full-screen editor", keyboard.isFullscreenMode)
                            assertTrue("The keyboard must still be visible while editing $label",
                                ViewCompat.getRootWindowInsets(main.window.decorView)?.isVisible(WindowInsetsCompat.Type.ime()) == true)
                            assertTrue("The $label input must keep focus", main.findViewById<EditText>(id).hasFocus())
                            assertTrue("The focused $label must remain visible above the keyboard",
                                main.findViewById<EditText>(id).getGlobalVisibleRect(Rect()))
                        }
                    }
                } finally {
                    withContext(Dispatchers.Main) { keyboard.hideSoftInputFromWindow(main.window.decorView.windowToken, 0) }
                }
            }
        } finally {
            prefs.edit().clear().also { editor -> previousPrefs.forEach { (key, value) -> editor.putString(key, value as String) } }.commit()
        }
    }

    @Test fun manualNasLoginSupportsDpadAndBack(): Unit = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val prefs = instrumentation.targetContext.getSharedPreferences("source_browse", Context.MODE_PRIVATE)
        val previousPrefs = prefs.all
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                lateinit var main: MainActivity
                scenario.onActivity { main = it }
                val previousSources = main.sources.observeSources().first().filterNot { it.isReadOnly }.associateBy { it.id }
                val model = openNas(main)
                clickVisible(main, BrowseR.id.manual_address, "manual NAS login entry")
                waitUntil("manual address focus") {
                    model.ui.value.stage == NasStage.LOGIN && main.hasWindowFocus() &&
                        main.findViewById<View>(BrowseR.id.address)?.hasFocus() == true
                }
                val focusOrder = listOf(BrowseR.id.username to "username", BrowseR.id.password to "password",
                    BrowseR.id.domain to "domain", BrowseR.id.read_shares to "read shares")
                for ((id, label) in focusOrder) {
                    var reached = false
                    val focusTrace = mutableListOf<String>()
                    // A short ScrollView may consume a direction press to scroll before moving focus.
                    repeat(FOCUS_NAVIGATION_ATTEMPTS) {
                        if (!reached) {
                            // Keyboard arrows stay in EditText; a remote uses the D-pad input source.
                            val downTime = SystemClock.uptimeMillis()
                            for (action in listOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
                                instrumentation.sendKeySync(KeyEvent(downTime, SystemClock.uptimeMillis(), action,
                                    KeyEvent.KEYCODE_DPAD_DOWN, 0, 0, -1, 0, 0, InputDevice.SOURCE_DPAD))
                            }
                            instrumentation.waitForIdleSync()
                            delay(POLL_INTERVAL_MS)
                            reached = withContext(Dispatchers.Main) {
                                val focused = main.currentFocus
                                val focusId = focused?.let { runCatching { main.resources.getResourceName(it.id) }.getOrDefault(it.id.toString()) }
                                focusTrace += "${focusId ?: "none"} (${focused?.javaClass?.name ?: "none"})"
                                main.findViewById<View>(id).hasFocus()
                            }
                        }
                    }
                    if (!reached) capture("26-nas-dpad-failure")
                    assertTrue("D-pad down must reach $label; focus after each key: ${focusTrace.joinToString(" -> ")}", reached)
                }
                waitUntil("focused read shares action fully visible") {
                    val action = main.findViewById<View>(BrowseR.id.read_shares)
                    val bounds = Rect()
                    action.hasFocus() && action.isShown && action.width > 0 && action.height > 0 &&
                        action.getGlobalVisibleRect(bounds) && bounds.width() >= action.width && bounds.height() >= action.height
                }
                instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
                waitUntil("D-pad login returns to NAS scanner") {
                    page(main) is NasFragment && model.ui.value.stage == NasStage.DEVICES &&
                        main.findViewById<View>(BrowseR.id.manual_address)?.isShown == true
                }
                assertTrue("Focus navigation must not save or modify sources",
                    previousSources == main.sources.observeSources().first().filterNot { it.isReadOnly }.associateBy { it.id })
            }
        } finally {
            prefs.edit().clear().also { editor -> previousPrefs.forEach { (key, value) -> editor.putString(key, value as String) } }.commit()
        }
    }

    @Test fun connectNasOpensScanPageAndReturnsToFiles(): Unit = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("source_browse", Context.MODE_PRIVATE)
        val previousPrefs = prefs.all
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                lateinit var main: MainActivity
                scenario.onActivity { main = it }
                val model = openNas(main)
                withContext(Dispatchers.Main) {
                    assertEquals(NasStage.DEVICES, model.ui.value.stage)
                    assertTrue(main.findViewById<View>(BrowseR.id.rescan).isShown)
                    assertTrue(main.findViewById<View>(BrowseR.id.manual_address).isShown)
                    assertTrue(main.findViewById<View>(BrowseR.id.back).performClick())
                }
                waitUntil("return from NAS scanner to files") { page(main) is BrowseFragment }
            }
        } finally {
            prefs.edit().clear().also { editor -> previousPrefs.forEach { (key, value) -> editor.putString(key, value as String) } }.commit()
        }
    }

    @Test fun smbFolderOpensNativePlayerAndRestoresDirectory(): Unit = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val url = args.getString("smbFixtureUrl")
        val user = args.getString("user")
        val password = args.getString("password")
        assumeTrue("SMB fixture arguments are required", !url.isNullOrBlank() && user != null && password != null)
        val fixtureName = args.getString("scanFixtureName") ?: "Juying Test NAS"
        val fixtureUri = Uri.parse(checkNotNull(url))
        val fixtureHost = checkNotNull(fixtureUri.host).removeSurrounding("[", "]")
        val fixturePort = fixtureUri.port.takeIf { it > 0 } ?: DEFAULT_SMB_PORT
        val fixtureAddress = "${if (':' in fixtureHost) "[$fixtureHost]" else fixtureHost}:$fixturePort"
        val share = fixtureUri.pathSegments.single()
        val fixtureUser = checkNotNull(user)
        val fixturePassword = checkNotNull(password)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("source_browse", Context.MODE_PRIVATE)
        val previousPrefs = prefs.all
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        lateinit var main: MainActivity
        scenario.onActivity { main = it }
        // Derive only the cleanup identity; the UI must authenticate, validate and save the connection.
        val expected = main.sources.networkConfiguration(main.sources.networkDevice(fixtureAddress), share, fixtureUser, fixturePassword, "")
        val previousSource = main.sources.get(expected.id)
        val previousSources = main.sources.observeSources().first().filterNot { it.isReadOnly }.associateBy { it.id }
        var player: PlayerActivity? = null
        try {
            prefs.edit().also { editor -> prefs.all.keys.filter { it.startsWith("${expected.id}.") }.forEach { editor.remove(it) } }.commit()
            val nas = openNas(main)
            waitUntil("named NAS discovered on the fixture address") {
                row(main, fixtureName, BrowseR.id.devices, fixtureAddress) != null
            }
            capture("21-nas-scan")
            withContext(Dispatchers.Main) {
                assertTrue(checkNotNull(row(main, fixtureName, BrowseR.id.devices, fixtureAddress)).itemView.performClick())
            }
            waitUntil("NAS login form") {
                nas.ui.value.stage == NasStage.LOGIN && main.findViewById<View>(BrowseR.id.login_form)?.isShown == true
            }
            withContext(Dispatchers.Main) {
                assertEquals(fixtureHost, nas.ui.value.device?.host)
                assertEquals(fixturePort, nas.ui.value.device?.port)
                assertTrue(main.findViewById<EditText>(BrowseR.id.password).text.isEmpty())
            }
            capture("22-nas-login")
            withContext(Dispatchers.Main) {
                main.findViewById<EditText>(BrowseR.id.username).setText(fixtureUser)
                main.findViewById<EditText>(BrowseR.id.password).setText("$fixturePassword-wrong")
            }
            clickVisible(main, BrowseR.id.read_shares, "visible login action for wrong password")
            waitUntil("wrong NAS password rejected") { !nas.ui.value.busy && nas.ui.value.error != null }
            withContext(Dispatchers.Main) {
                assertEquals(NasError.ACCESS_DENIED, nas.ui.value.error)
                assertEquals(NasStage.LOGIN, nas.ui.value.stage)
            }
            waitUntil("controlled login error message") {
                val status = main.findViewById<TextView>(BrowseR.id.status)
                status.isShown && status.text.toString() == main.getString(BrowseR.string.nas_access_denied)
            }
            assertTrue("Failed login must not save or modify sources",
                previousSources == main.sources.observeSources().first().filterNot { it.isReadOnly }.associateBy { it.id })
            withContext(Dispatchers.Main) {
                main.findViewById<EditText>(BrowseR.id.password).setText(fixturePassword)
            }
            clickVisible(main, BrowseR.id.read_shares, "visible login action for correct password")
            waitUntil("NAS shared folder list") {
                nas.ui.value.stage == NasStage.SHARES && !nas.ui.value.busy && row(main, share, BrowseR.id.shares) != null
            }
            capture("23-nas-shares")
            assertTrue("Listing shares must not save or modify sources",
                previousSources == main.sources.observeSources().first().filterNot { it.isReadOnly }.associateBy { it.id })
            withContext(Dispatchers.Main) { assertTrue(checkNotNull(row(main, share, BrowseR.id.shares)).itemView.performClick()) }
            waitUntil("saved NAS opens file browser") { page(main) is BrowseFragment && row(main, "Movies") != null }
            val source = checkNotNull(main.sources.observeSources().first().singleOrNull {
                it.id == expected.id && it.type == SourceType.SMB && it.url == expected.url
            }) { "The NAS wizard did not save the fixture connection" }
            withContext(Dispatchers.Main) { assertEquals(source.id, main.memory.selected(SourceCapability.BROWSE)) }
            withContext(Dispatchers.Main) { assertTrue(checkNotNull(row(main, "Movies")).itemView.performClick()) }
            waitUntil("SMB Movies directory and subtitle") {
                currentDirectory(main) == "Movies" && row(main, "test-pattern.zh.srt") != null
            }
            waitUntil("SMB video row") { row(main, "test-pattern.mp4") != null }
            capture("24-nas-files")
            withContext(Dispatchers.Main) { assertTrue(checkNotNull(row(main, "test-pattern.mp4")).itemView.performClick()) }
            waitUntil("SMB player activity") {
                player = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED)
                    .filterIsInstance<PlayerActivity>().singleOrNull()
                player != null
            }
            val activity = checkNotNull(player)
            val model = withContext(Dispatchers.Main) { ViewModelProvider(activity).get(PlayerViewModel::class.java) }
            waitUntil("SMB playback progress") {
                check(model.ui.value.error == null && model.ui.value.playback.error == null) { "SMB playback failed" }
                model.ui.value.playback.isPlaying && model.positionMs() >= 1_000
            }
            withContext(Dispatchers.Main) {
                assertEquals(320, model.ui.value.playback.videoWidth)
                assertEquals(240, model.ui.value.playback.videoHeight)
                assertTrue(activity.findViewById<SurfaceView>(PlayerR.id.surface).isShown)
                assertTrue(model.durationMs() >= 7_000)
            }
            waitUntil("SMB subtitle track") { model.tracks(PlayerTrackType.SUBTITLE).any { it.selected && it.label.contains("zh") } }
            withContext(Dispatchers.Main) { model.seekTo(3_000) }
            waitUntil("SMB seek") { model.ui.value.playback.isPlaying && model.positionMs() >= 3_000 }
            val afterSeek = withContext(Dispatchers.Main) { model.positionMs() }
            waitUntil("SMB progress after seek") { model.positionMs() >= afterSeek + 300 }
            withContext(Dispatchers.Main) {
                assertEquals(null, model.ui.value.error)
                assertEquals(null, model.ui.value.playback.error)
                activity.onBackPressedDispatcher.onBackPressed()
                if (!activity.isFinishing) activity.onBackPressedDispatcher.onBackPressed()
            }
            waitUntil("return to SMB Movies directory") {
                ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).contains(main) &&
                    currentDirectory(main) == "Movies" &&
                    row(main, "test-pattern.mp4") != null
            }
            withContext(Dispatchers.Main) {
                assertEquals(source.id, main.memory.selected(SourceCapability.BROWSE))
                assertTrue(main.findViewById<android.view.View>(BrowseR.id.parent).isEnabled)
            }
            clickVisible(main, BrowseR.id.add_storage, "return to storage locations")
            clickVisible(main, BrowseR.id.add_nas, "reconnect NAS entry")
            waitUntil("reconnect NAS scanner") { page(main) is NasFragment }
            clickVisible(main, BrowseR.id.manual_address, "manual NAS address entry")
            val reconnect = withContext(Dispatchers.Main) { ViewModelProvider(checkNotNull(page(main))).get(NasViewModel::class.java) }
            waitUntil("reconnect login form") {
                reconnect.ui.value.stage == NasStage.LOGIN && main.findViewById<View>(BrowseR.id.login_form)?.isShown == true
            }
            withContext(Dispatchers.Main) {
                main.findViewById<EditText>(BrowseR.id.address).setText(fixtureAddress)
                main.findViewById<EditText>(BrowseR.id.username).setText(fixtureUser)
                main.findViewById<EditText>(BrowseR.id.password).setText(fixturePassword)
            }
            clickVisible(main, BrowseR.id.read_shares, "reconnect shared folders action")
            waitUntil("reconnect shared folder list") {
                reconnect.ui.value.stage == NasStage.SHARES && !reconnect.ui.value.busy && row(main, share, BrowseR.id.shares) != null
            }
            withContext(Dispatchers.Main) { assertTrue(checkNotNull(row(main, share, BrowseR.id.shares)).itemView.performClick()) }
            waitUntil("same NAS connection restores Movies automatically") {
                page(main) is BrowseFragment && currentDirectory(main) == "Movies" && row(main, "test-pattern.mp4") != null
            }
            withContext(Dispatchers.Main) { assertEquals(source.id, main.memory.selected(SourceCapability.BROWSE)) }
            assertEquals(1, main.sources.observeSources().first().count { it.id == source.id })
            capture("25-nas-reconnect-files")
        } finally {
            withContext(Dispatchers.Main) { player?.takeUnless { it.isFinishing || it.isDestroyed }?.finish() }
            scenario.close()
            try {
                if (previousSource == null) main.sources.delete(expected.id) else main.sources.upsert(previousSource)
            } finally {
                prefs.edit().clear().also { editor -> previousPrefs.forEach { (key, value) -> editor.putString(key, value as String) } }.commit()
            }
        }
    }

    private suspend fun openNas(main: MainActivity): NasViewModel {
        withContext(Dispatchers.Main) { main.openSource(SourceCapability.BROWSE) }
        waitUntil("file page") { page(main) is BrowseFragment }
        val browse = withContext(Dispatchers.Main) { ViewModelProvider(checkNotNull(page(main))).get(BrowseViewModel::class.java) }
        waitUntil("initial storage selection") { browse.ui.value.source != null || !browse.ui.value.loading }
        withContext(Dispatchers.Main) { if (!browse.ui.value.showRoots) browse.showRoots() }
        waitUntil("visible connect NAS button") { main.findViewById<View>(BrowseR.id.add_nas)?.isShown == true }
        capture("20-nas-roots")
        withContext(Dispatchers.Main) { assertTrue(main.findViewById<View>(BrowseR.id.add_nas).performClick()) }
        waitUntil("NAS scan page") { page(main) is NasFragment && main.findViewById<View>(BrowseR.id.devices)?.isShown == true }
        return withContext(Dispatchers.Main) { ViewModelProvider(checkNotNull(page(main))).get(NasViewModel::class.java) }
    }

    private fun page(activity: MainActivity) =
        (activity.supportFragmentManager.findFragmentById(R.id.nav_host) as? NavHostFragment)?.childFragmentManager?.primaryNavigationFragment

    private fun currentDirectory(activity: MainActivity): String? =
        (activity.findViewById<RecyclerView>(BrowseR.id.breadcrumbs)?.adapter as? com.flytech.juying.core.ui.TextChoiceAdapter)
            ?.currentList?.singleOrNull { it.selected }?.label

    private fun row(activity: MainActivity, title: String, listId: Int = BrowseR.id.files, id: String? = null): RecyclerView.ViewHolder? {
        val list = activity.findViewById<RecyclerView>(listId) ?: return null
        val adapter = list.adapter as? MediaRowAdapter ?: return null
        val index = adapter.currentList.indexOfFirst { it.title == title && (id == null || it.id == id) }
        if (index < 0) return null
        return list.findViewHolderForAdapterPosition(index)?.takeIf {
            it.itemView.isShown && it.itemView.getGlobalVisibleRect(Rect())
        } ?: run { list.scrollToPosition(index); null }
    }

    private suspend fun waitUntil(stage: String, condition: () -> Boolean) = withContext(Dispatchers.Main) {
        try {
            withTimeout(READY_TIMEOUT_MS) { while (!condition()) delay(POLL_INTERVAL_MS) }
        } catch (timeout: TimeoutCancellationException) {
            throw AssertionError("Timed out waiting for $stage", timeout)
        }
    }

    private suspend fun clickVisible(activity: MainActivity, id: Int, stage: String) {
        waitUntil(stage) {
            val view = activity.findViewById<View>(id) ?: return@waitUntil false
            if (!view.isShown || view.height == 0) return@waitUntil false
            view.requestRectangleOnScreen(Rect(0, 0, view.width, view.height), true)
            val bounds = Rect()
            view.getGlobalVisibleRect(bounds) && bounds.height() >= view.height && view.isEnabled
        }
        withContext(Dispatchers.Main) { assertTrue(activity.findViewById<View>(id).performClick()) }
    }

    private suspend fun capture(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        delay(CAPTURE_SETTLE_MS)
        instrumentation.waitForIdleSync()
        val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            val output = File(instrumentation.targetContext.getExternalFilesDir(null), "ui-check/$name.png")
            output.parentFile!!.mkdirs()
            output.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        } finally { bitmap.recycle() }
    }

    private companion object {
        const val READY_TIMEOUT_MS = 30_000L
        const val POLL_INTERVAL_MS = 100L
        const val CAPTURE_SETTLE_MS = 500L
        const val FOCUS_NAVIGATION_ATTEMPTS = 4
        const val DEFAULT_SMB_PORT = 445
    }
}
