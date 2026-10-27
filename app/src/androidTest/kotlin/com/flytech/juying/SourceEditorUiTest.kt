package com.flytech.juying

import android.os.Bundle
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.CheckBox
import android.widget.EditText
import android.widget.TextView
import androidx.navigation.fragment.NavHostFragment
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.feature.settings.R as S
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SourceEditorUiTest {
    @Test fun iptvCanBeCheckedSavedEditedAndDeletedThroughTheForm() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("#EXTM3U\n#EXTINF:-1,Test\nhttps://example.test/video.m3u8"))
            val playlistUrl = server.url("/playlist").toString()
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                lateinit var sources: SourceRepository
                var created: SourceConfig? = null
                suspend fun waitUntil(condition: (MainActivity) -> Boolean) = withTimeout(8_000) {
                    var ready = false
                    while (!ready) { scenario.onActivity { ready = condition(it) }; if (!ready) delay(100) }
                }
                fun navigate(id: String? = null) = scenario.onActivity {
                    val nav = (it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment).navController
                    nav.navigate(R.id.sources, id?.let { value -> Bundle().apply { putString("editSourceId", value) } })
                }
                suspend fun clickDialog(text: String) {
                    withTimeout(5_000) {
                        while (instrumentation.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText(text)?.isNotEmpty() != true) delay(100)
                    }
                    val node = instrumentation.uiAutomation.rootInActiveWindow.findAccessibilityNodeInfosByText(text).first()
                    assertTrue(node.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                }
                try {
                    scenario.onActivity { sources = it.sources }
                    navigate()
                    waitUntil { it.findViewById<View>(S.id.add)?.isShown == true }
                    scenario.onActivity { it.findViewById<View>(S.id.add).performClick() }
                    clickDialog("IPTV")
                    waitUntil { it.findViewById<View>(S.id.editor)?.isShown == true }
                    scenario.onActivity {
                        it.findViewById<EditText>(S.id.name).setText("IPTV form test")
                        it.findViewById<EditText>(S.id.url).setText(playlistUrl)
                        it.findViewById<EditText>(S.id.user_agent).setText("Form-test")
                        assertTrue(it.findViewById<View>(S.id.import_file).visibility == View.VISIBLE)
                        it.findViewById<View>(S.id.check).performClick()
                    }
                    waitUntil { it.findViewById<TextView>(S.id.status)?.text?.toString() == it.getString(S.string.sources_checked, 1) }
                    scenario.onActivity { it.findViewById<View>(S.id.save).performClick() }
                    withTimeout(8_000) {
                        while (created == null) { created = sources.observeSources().first().find { it.name == "IPTV form test" }; if (created == null) delay(100) }
                    }
                    assertEquals("Form-test", created!!.extra["userAgent"])
                    scenario.recreate()
                    navigate(created!!.id)
                    waitUntil { it.findViewById<View>(S.id.editor)?.isShown == true }
                    scenario.onActivity {
                        assertEquals("Form-test", it.findViewById<EditText>(S.id.user_agent).text.toString())
                        it.findViewById<CheckBox>(S.id.enabled).isChecked = false
                        it.findViewById<View>(S.id.save).performClick()
                    }
                    withTimeout(8_000) { while (sources.get(created!!.id)!!.enabled) delay(100) }
                    navigate(created!!.id)
                    waitUntil { it.findViewById<View>(S.id.editor)?.isShown == true }
                    scenario.onActivity { it.findViewById<View>(S.id.delete).performClick() }
                    clickDialog(instrumentation.targetContext.getString(com.flytech.juying.core.designsystem.R.string.ui_delete))
                    withTimeout(8_000) { while (sources.get(created!!.id) != null) delay(100) }
                } finally { created?.let { sources.delete(it.id) } }
            }
        }
    }
}
