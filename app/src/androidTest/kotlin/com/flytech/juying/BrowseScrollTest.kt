package com.flytech.juying

import android.os.Bundle
import android.view.View
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentManager
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.NavHostFragment
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.BrowseRepository
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.*
import com.flytech.juying.feature.browse.BrowseFragment
import com.flytech.juying.feature.browse.BrowseViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import com.flytech.juying.feature.browse.R as B

@RunWith(AndroidJUnit4::class)
class BrowseScrollTest {
    @Test fun sourceDiscoveryAndRefreshKeepCurrentScrollButDirectoryEntryRestoresItsOwnPosition(): Unit = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val prefs = instrumentation.targetContext.getSharedPreferences("source_browse", 0)
        val previous = prefs.all
        val source = SourceConfig("browse-scroll-test", "Directory fixture", SourceType.SMB, "smb://fixture/share")
        val configs = MutableStateFlow(listOf(source))
        val sources = object : SourceRepository {
            override fun observeSources(capability: SourceCapability?) = configs
            override suspend fun get(id: String) = configs.value.firstOrNull { it.id == id }
            override suspend fun upsert(config: SourceConfig) { configs.value = configs.value.filterNot { it.id == config.id } + config }
            override suspend fun delete(id: String) { configs.value = configs.value.filterNot { it.id == id } }
        }
        var failNextRead = false
        val browse = object : BrowseRepository {
            override suspend fun list(sourceId: String, path: String): List<FileEntry> {
                delay(100)
                if (failNextRead) {
                    failNextRead = false
                    error("Temporary directory failure")
                }
                return List(120) { FileEntry("Folder %03d".format(it), "$path/$it", true) }
            }
            override suspend fun playItem(sourceId: String, entry: FileEntry): PlayItem = error("Not used")
        }
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                lateinit var model: BrowseViewModel
                scenario.onActivity { activity ->
                    activity.memory.select(source.id, SourceCapability.BROWSE)
                    activity.memory.put(source.id, "path", "")
                    activity.memory.put(source.id, "parents", "[]")
                    activity.memory.put(source.id, "scroll.", "8")
                    val host = activity.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
                    host.childFragmentManager.registerFragmentLifecycleCallbacks(object : FragmentManager.FragmentLifecycleCallbacks() {
                        override fun onFragmentCreated(fm: FragmentManager, fragment: Fragment, savedInstanceState: Bundle?) {
                            if (fragment is BrowseFragment) {
                                model = ViewModelProvider(fragment, object : ViewModelProvider.Factory {
                                    override fun <T : ViewModel> create(modelClass: Class<T>): T =
                                        modelClass.cast(BrowseViewModel(sources, browse, activity.memory, Dispatchers.Default))!!
                                })[BrowseViewModel::class.java]
                                fm.unregisterFragmentLifecycleCallbacks(this)
                            }
                        }
                    }, false)
                    host.navController.navigate(R.id.nav_browse)
                }
                waitFor(scenario) { it.findViewById<RecyclerView>(B.id.files)?.adapter?.itemCount == 120 }
                instrumentation.setInTouchMode(false)
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(B.id.add_storage).requestFocus())
                    manager(activity).scrollToPositionWithOffset(60, 0)
                }
                waitFor(scenario) { manager(it).findFirstVisibleItemPosition() == 60 }
                sources.upsert(source.copy(id = "discovered", name = "Another storage"))
                waitFor(scenario) { model.ui.value.sources.size == 2 }
                delay(300)
                scenario.onActivity { assertEquals(60, manager(it).findFirstVisibleItemPosition()) }
                scenario.onActivity { model.retry() }
                waitFor(scenario) { !model.ui.value.loading && it.findViewById<RecyclerView>(B.id.files).adapter?.itemCount == 120 }
                delay(150)
                scenario.onActivity { activity ->
                    assertEquals(60, manager(activity).findFirstVisibleItemPosition())
                    failNextRead = true
                    model.retry()
                }
                waitFor(scenario) { model.ui.value.failed && it.findViewById<RecyclerView>(B.id.files).adapter?.itemCount == 0 }
                delay(150)
                scenario.onActivity { model.retry() }
                waitFor(scenario) { !model.ui.value.loading && it.findViewById<RecyclerView>(B.id.files).adapter?.itemCount == 120 }
                delay(150)
                scenario.onActivity { activity ->
                    assertEquals(60, manager(activity).findFirstVisibleItemPosition())
                    val folder = model.ui.value.files.first()
                    activity.memory.put(source.id, "scroll.${folder.path}", "12")
                    model.enter(folder)
                }
                waitFor(scenario) { !model.ui.value.loading && manager(it).findFirstVisibleItemPosition() == 12 }
            }
        } finally {
            prefs.edit().clear().also { editor -> previous.forEach { (key, value) -> editor.putString(key, value as String) } }.commit()
        }
    }

    private fun manager(activity: MainActivity) = activity.findViewById<RecyclerView>(B.id.files).layoutManager as LinearLayoutManager

    private suspend fun waitFor(scenario: ActivityScenario<MainActivity>, condition: (MainActivity) -> Boolean) {
        withTimeout(10_000) {
            while (true) {
                var ready = false
                scenario.onActivity { ready = condition(it) }
                if (ready) return@withTimeout
                delay(25)
            }
        }
    }
}
