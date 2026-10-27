package com.flytech.juying

import android.graphics.Rect
import android.view.View
import android.view.Window
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.NavHostFragment
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.feature.settings.SettingsViewModel
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import com.flytech.juying.feature.search.R as SearchR
import com.flytech.juying.feature.settings.R as SettingsR

@RunWith(AndroidJUnit4::class)
class KeyboardUiTest {
    @Test fun searchKeepsKeyboardInline() = withMain { main ->
        withContext(Dispatchers.Main) { host(main).navController.navigate(R.id.search) }
        waitUntil { main.findViewById<View>(SearchR.id.query)?.isShown == true }
        checkInput(main.window, SearchR.id.query, "search")
        withContext(Dispatchers.Main) {
            assertEquals(EditorInfo.IME_ACTION_SEARCH,
                main.findViewById<EditText>(SearchR.id.query).imeOptions and EditorInfo.IME_MASK_ACTION)
        }
    }

    @Test fun sourceSettingsKeepEveryKeyboardInline() = withMain { main ->
        withContext(Dispatchers.Main) { host(main).navController.navigate(R.id.sources) }
        waitUntil { main.findViewById<View>(SettingsR.id.add)?.isShown == true }
        val model = withContext(Dispatchers.Main) {
            ViewModelProvider(checkNotNull(host(main).childFragmentManager.primaryNavigationFragment))
                .get(SettingsViewModel::class.java)
        }
        val fields = listOf(
            SourceType.IPTV to listOf(SettingsR.id.name, SettingsR.id.url, SettingsR.id.epg_url,
                SettingsR.id.user_agent, SettingsR.id.referer),
            SourceType.SMB to listOf(SettingsR.id.username, SettingsR.id.password),
        )
        for ((type, ids) in fields) {
            withContext(Dispatchers.Main) { model.add(model.setups.single { it.type == type }) }
            for (id in ids) {
                waitUntil { main.findViewById<View>(id)?.isShown == true }
                checkInput(main.window, id, "sources-${main.resources.getResourceEntryName(id)}")
            }
            withContext(Dispatchers.Main) { model.cancel() }
        }
    }

    @Test fun sourcePickerKeepsKeyboardInline() = withMain { main ->
        withContext(Dispatchers.Main) { main.findViewById<View>(R.id.source_switch).performClick() }
        waitUntil { main.supportFragmentManager.fragments.filterIsInstance<SourcePickerDialog>()
            .singleOrNull()?.dialog?.window?.decorView?.hasWindowFocus() == true }
        val window = withContext(Dispatchers.Main) {
            checkNotNull(main.supportFragmentManager.fragments.filterIsInstance<SourcePickerDialog>().single().dialog?.window)
        }
        checkInput(window, R.id.query, "source-picker")
    }

    private fun withMain(block: suspend (MainActivity) -> Unit): Unit = runBlocking {
        InstrumentationRegistry.getInstrumentation().setInTouchMode(true)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var main: MainActivity
            scenario.onActivity { main = it }
            waitUntil { main.hasWindowFocus() }
            block(main)
        }
    }

    private suspend fun checkInput(window: Window, id: Int, label: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val keyboard = instrumentation.targetContext.getSystemService(InputMethodManager::class.java)
        val field = withContext(Dispatchers.Main) { window.findViewById<EditText>(id) }
        try {
            withContext(Dispatchers.Main) {
                assertTrue("$label must disable full-screen editing", field.imeOptions and EditorInfo.IME_FLAG_NO_FULLSCREEN != 0)
                field.requestFocus()
                keyboard.showSoftInput(field, InputMethodManager.SHOW_IMPLICIT)
            }
            waitUntil { keyboard.isFullscreenMode || keyboardVisible(window) }
            instrumentation.sendStringSync("keyboard")
            delay(500)
            instrumentation.waitForIdleSync()
            val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
            try {
                val output = File(instrumentation.targetContext.getExternalFilesDir(null), "ui-check/keyboard-$label.png")
                output.parentFile!!.mkdirs()
                output.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            } finally { bitmap.recycle() }
            withContext(Dispatchers.Main) {
                assertFalse("$label must not open the keyboard's full-screen editor", keyboard.isFullscreenMode)
                assertTrue("$label keyboard must remain visible", keyboardVisible(window))
                assertTrue("$label must keep focus", field.hasFocus())
                assertEquals("keyboard", field.text.toString())
                val bounds = Rect()
                assertTrue("$label must remain fully visible above the keyboard",
                    field.getGlobalVisibleRect(bounds) && bounds.height() >= field.height)
            }
        } finally {
            withContext(Dispatchers.Main) { keyboard.hideSoftInputFromWindow(window.decorView.windowToken, 0) }
            waitUntil { !keyboardVisible(window) }
        }
    }

    private fun keyboardVisible(window: Window) =
        ViewCompat.getRootWindowInsets(window.decorView)?.isVisible(WindowInsetsCompat.Type.ime()) == true

    private fun host(main: MainActivity) = main.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment

    private suspend fun waitUntil(condition: () -> Boolean) = withContext(Dispatchers.Main) {
        withTimeout(10_000) { while (!condition()) delay(100) }
    }
}
