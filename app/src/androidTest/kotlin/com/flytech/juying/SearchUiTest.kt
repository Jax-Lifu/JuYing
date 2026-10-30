package com.flytech.juying

import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.widget.EditText
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentManager
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.NavHostFragment
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.model.*
import com.flytech.juying.feature.search.SearchFragment
import com.flytech.juying.feature.search.SearchViewModel
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import com.flytech.juying.feature.search.R as S

@RunWith(AndroidJUnit4::class)
class SearchUiTest {
    @Test fun partialFailureRetryAndAutomaticEmptyPageSearchRemainReachable(): Unit = runBlocking {
        val calls = CopyOnWriteArrayList<Pair<String, Int>>()
        val finishEmptyPage = CompletableDeferred<Unit>()
        val first = SearchTarget("one", "First")
        val second = SearchTarget("two", "Second")
        val repository = object : VodRepository {
            override suspend fun subSources(sourceId: String): List<SubSource> = emptyList()
            override suspend fun categories(sourceId: String): List<VodCategory> = emptyList()
            override suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem> = emptyList()
            override suspend fun detail(sourceId: String, itemId: String): VodDetail = error("Not used")
            override suspend fun search(sourceId: String, keyword: String, page: Int): List<VodItem> = emptyList()
            override suspend fun searchAll(keyword: String, page: Int): List<VodItem> = emptyList()
            override suspend fun resolve(sourceId: String, episodeRef: String): PlayItem = error("Not used")
            override fun searchUpdates(keyword: String, page: Int) = flow {
                calls += keyword to page
                if (keyword == "部分") {
                    emit(SearchUpdate.Discovered(listOf(first, second)))
                    emit(SearchUpdate.Finished(first, SearchOutcome.SUCCESS, listOf(VodItem("one", "one", "Result")), false))
                    emit(if (calls.count { it.first == keyword } == 1) SearchUpdate.Finished(second, SearchOutcome.TIMED_OUT)
                        else SearchUpdate.Finished(second, SearchOutcome.SUCCESS, listOf(VodItem("two", "two", "Recovered")), false))
                } else if (keyword == "无结果") {
                    emit(SearchUpdate.Finished(first, SearchOutcome.SUCCESS, hasMore = false))
                } else {
                    val items = when (page) {
                        1 -> emptyList()
                        2 -> (1..60).map { VodItem(it.toString(), "one", "Result $it") }
                        3 -> listOf(VodItem("next", "one", "Next result"))
                        else -> listOf(VodItem("last", "one", "Last result"))
                    }
                    emit(SearchUpdate.Finished(first, SearchOutcome.SUCCESS, items, page < 4))
                    if (page == 1) finishEmptyPage.await()
                }
            }
        }
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val host = activity.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
                host.childFragmentManager.registerFragmentLifecycleCallbacks(object : FragmentManager.FragmentLifecycleCallbacks() {
                    override fun onFragmentCreated(fm: FragmentManager, fragment: Fragment, savedInstanceState: Bundle?) {
                        if (fragment is SearchFragment) {
                            ViewModelProvider(fragment, object : ViewModelProvider.Factory {
                                override fun <T : ViewModel> create(modelClass: Class<T>): T = modelClass.cast(SearchViewModel(repository))!!
                            })[SearchViewModel::class.java]
                            fm.unregisterFragmentLifecycleCallbacks(this)
                        }
                    }
                }, false)
                host.navController.navigate(R.id.search)
            }
            waitFor(scenario, "search screen", calls) { it.findViewById<EditText>(S.id.query) != null }
            scenario.onActivity {
                it.findViewById<EditText>(S.id.query).setText("部分")
                it.findViewById<View>(S.id.submit).performClick()
            }
            waitFor(scenario, "partial failure and retry", calls) {
                it.findViewById<RecyclerView>(S.id.posters).adapter!!.itemCount == 1 && it.findViewById<View>(S.id.retry).isShown
            }
            scenario.onActivity {
                assertTrue(it.findViewById<TextView>(S.id.status).text.contains("Second"))
                assertTrue(it.findViewById<View>(S.id.posters).isShown)
                it.findViewById<View>(S.id.retry).performClick()
            }
            waitFor(scenario, "retry recovers second result", calls) { it.findViewById<RecyclerView>(S.id.posters).adapter!!.itemCount == 2 }
            scenario.onActivity {
                assertFalse(it.findViewById<View>(S.id.retry).isShown)
                assertFalse(it.findViewById<View>(S.id.more).isShown)
                it.findViewById<EditText>(S.id.query).setText("目录")
                it.findViewById<View>(S.id.submit).performClick()
            }
            waitFor(scenario, "empty first page still searching", calls) {
                calls.contains("目录" to 1) && it.findViewById<View>(S.id.progress).isShown &&
                    it.findViewById<RecyclerView>(S.id.posters).adapter!!.itemCount == 0
            }
            scenario.onActivity { assertFalse(it.findViewById<View>(S.id.more).isShown) }
            finishEmptyPage.complete(Unit)
            waitFor(scenario, "automatic page 2 finds results", calls) { it.findViewById<RecyclerView>(S.id.posters).adapter!!.itemCount == 60 }
            delay(300)
            assertEquals(listOf(1, 2), calls.filter { it.first == "目录" }.map { it.second })
            scenario.onActivity {
                assertFalse(it.findViewById<View>(S.id.emptyContainer).isShown)
                assertTrue(it.findViewById<View>(S.id.more).isShown)
            }
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            // 触屏设备可能仍处于触摸模式；遥控导航前先进入焦点模式。
            instrumentation.setInTouchMode(false)
            waitFor(scenario, "D-pad focus mode", calls) { !it.findViewById<View>(S.id.more).isInTouchMode }
            scenario.onActivity {
                val more = it.findViewById<View>(S.id.more)
                assertTrue("Load more accepts D-pad focus", more.requestFocus())
                assertTrue("Load more holds D-pad focus", more.isFocused)
            }
            instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_CENTER)
            waitFor(scenario, "page 3 after D-pad confirmation", calls) { it.findViewById<RecyclerView>(S.id.posters).adapter!!.itemCount == 61 }
            waitFor(scenario, "scrollable page 3 layout", calls) {
                val list = it.findViewById<RecyclerView>(S.id.posters)
                list.height > 0 && list.childCount > 0 && !list.isLayoutRequested && list.canScrollVertically(1)
            }
            scenario.onActivity { it.findViewById<RecyclerView>(S.id.posters).let { list -> list.scrollBy(0, list.height * 50) } }
            waitFor(scenario, "page 4 after scrolling", calls) { it.findViewById<RecyclerView>(S.id.posters).adapter!!.itemCount == 62 }
            scenario.onActivity { assertFalse(it.findViewById<View>(S.id.more).isShown) }
            assertEquals(listOf(1, 2, 3, 4), calls.filter { it.first == "目录" }.map { it.second })
            scenario.onActivity {
                it.findViewById<EditText>(S.id.query).setText("无结果")
                it.findViewById<View>(S.id.submit).performClick()
            }
            waitFor(scenario, "finished empty search", calls) { it.findViewById<View>(S.id.emptyContainer).isShown }
            scenario.onActivity {
                assertFalse(it.findViewById<View>(S.id.more).isShown)
                assertFalse(it.findViewById<View>(S.id.retry).isShown)
            }
        }
    }

    private suspend fun waitFor(scenario: ActivityScenario<MainActivity>, stage: String,
        calls: List<Pair<String, Int>>, condition: (MainActivity) -> Boolean) {
        repeat(80) {
            var ready = false
            scenario.onActivity { ready = condition(it) }
            if (ready) { InstrumentationRegistry.getInstrumentation().waitForIdleSync(); return }
            delay(100)
        }
        var snapshot = ""
        scenario.onActivity { activity ->
            val list = activity.findViewById<RecyclerView>(S.id.posters)
            val grid = list?.layoutManager as? GridLayoutManager
            val more = activity.findViewById<View>(S.id.more)
            val focus = activity.currentFocus
            snapshot = "items=${list?.adapter?.itemCount}, listShown=${list?.isShown}, " +
                "listSize=${list?.width}x${list?.height}, layoutRequested=${list?.isLayoutRequested}, " +
                "lastVisible=${grid?.findLastVisibleItemPosition()}, canScrollDown=${list?.canScrollVertically(1)}, " +
                "moreShown=${more?.isShown}, moreEnabled=${more?.isEnabled}, moreFocused=${more?.isFocused}, " +
                "touchMode=${more?.isInTouchMode}, windowFocus=${more?.hasWindowFocus()}, " +
                "focus=${focus?.javaClass?.simpleName}:${focus?.id}, moreId=${more?.id}, " +
                "emptyShown=${activity.findViewById<View>(S.id.emptyContainer)?.isShown}, " +
                "status=${activity.findViewById<TextView>(S.id.status)?.text}"
        }
        fail("Search UI timeout at '$stage'; calls=$calls; $snapshot")
    }
}
