package com.flytech.juying

import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.widget.TextView
import androidx.navigation.fragment.NavHostFragment
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.data.HistoryRepository
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.ui.Appearance
import coil.imageLoader
import java.io.File
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.first
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun vodLoadsNextPageWhenScrolledNearEnd(): Unit = runBlocking {
        MockWebServer().use { server ->
            val pages = java.util.concurrent.CopyOnWriteArrayList<Int>()
            val covers = java.util.concurrent.CopyOnWriteArrayList<Int>()
            val image = instrumentation.context.assets.open("design-hero.png").use { it.readBytes() }
            val firstPageSize = java.util.concurrent.atomic.AtomicInteger(60)
            val releaseNextPage = java.util.concurrent.CountDownLatch(1)
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val url = request.requestUrl!!
                    if (url.encodedPath.startsWith("/cover/")) {
                        covers += url.pathSegments.last().toInt()
                        return MockResponse().setHeader("Content-Type", "image/png")
                            .setBody(okio.Buffer().write(image)).setBodyDelay(100, java.util.concurrent.TimeUnit.MILLISECONDS)
                    }
                    if (url.queryParameter("ac") == null) return MockResponse().setBody("""{"class":[{"type_id":"all","type_name":"All"}]}""")
                    val page = url.queryParameter("pg")!!.toInt()
                    pages += page
                    if (page == 2) check(releaseNextPage.await(20, java.util.concurrent.TimeUnit.SECONDS))
                    val rows = org.json.JSONArray()
                    val ids = when (page) { 1 -> 1..firstPageSize.get(); 2 -> (firstPageSize.get() + 1)..(firstPageSize.get() + 1); else -> IntRange.EMPTY }
                    ids.forEach { rows.put(org.json.JSONObject().put("vod_id", it.toString()).put("vod_name", "Item $it")
                        .put("vod_pic", server.url("/cover/$it").toString())) }
                    return MockResponse().setBody(org.json.JSONObject().put("list", rows).toString())
                }
            }
            server.start()
            val source = SourceConfig("pagination-ui-test", "Pagination", SourceType.TVBOX, server.url("/cms").toString())
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                lateinit var repository: SourceRepository
                var previousSource: String? = null
                scenario.onActivity { repository = it.sources; previousSource = it.memory.selected(SourceCapability.VOD) }
                try {
                    repository.upsert(source)
                    scenario.onActivity {
                        it.memory.select(source.id, SourceCapability.VOD)
                        (it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment).navController.navigate(R.id.nav_vod)
                    }
                    waitFor(scenario) { it.findViewById<androidx.recyclerview.widget.RecyclerView>(com.flytech.juying.feature.vod.R.id.posters)?.adapter?.itemCount == 60 }
                    waitFor(scenario) {
                        val list = it.findViewById<androidx.recyclerview.widget.RecyclerView>(com.flytech.juying.feature.vod.R.id.posters)
                        val grid = list.layoutManager as androidx.recyclerview.widget.GridLayoutManager
                        val children = (0 until grid.childCount).map { index -> grid.getChildAt(index)!! }
                        children.isNotEmpty() && grid.getDecoratedBottom(children.last()) >= list.height * 2 - list.paddingTop - list.paddingBottom * 2 &&
                            children.all { child -> child.findViewById<android.widget.ImageView>(com.flytech.juying.core.ui.R.id.cover).drawable is android.graphics.drawable.BitmapDrawable }
                    }
                    scenario.onActivity {
                        val list = it.findViewById<androidx.recyclerview.widget.RecyclerView>(com.flytech.juying.feature.vod.R.id.posters)
                        val grid = list.layoutManager as androidx.recyclerview.widget.GridLayoutManager
                        val loaded = (0 until grid.childCount).map { index -> grid.getChildAt(index)!! }.associate { child ->
                            grid.getPosition(child) to child.findViewById<android.widget.ImageView>(com.flytech.juying.core.ui.R.id.cover).drawable
                        }
                        assertTrue("One screen of covers is ready before scrolling", loaded.keys.max() > grid.findLastVisibleItemPosition())
                        assertTrue("Prefetch stays bounded instead of loading all covers", covers.size < 60)
                        instrumentation.sendStatus(0, Bundle().apply { putString("stream",
                            "Cover prefetch: visible=${grid.findLastVisibleItemPosition() + 1}, prepared=${loaded.size}, requests=${covers.size}\n") })
                        list.scrollBy(0, list.height - list.paddingTop - list.paddingBottom)
                        for (position in grid.findFirstVisibleItemPosition()..grid.findLastVisibleItemPosition()) {
                            assertSame("Preloaded covers must not flash a placeholder", loaded[position],
                                grid.findViewByPosition(position)!!.findViewById<android.widget.ImageView>(com.flytech.juying.core.ui.R.id.cover).drawable)
                        }
                        list.scrollBy(0, -1)
                        assertTrue("Reverse scrolling prepares the previous screen", grid.getDecoratedTop(grid.getChildAt(0)!!) < list.paddingTop)
                        pages.clear()
                        val host = it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
                        val model = androidx.lifecycle.ViewModelProvider(host.childFragmentManager.primaryNavigationFragment!!)
                            .get(com.flytech.juying.feature.vod.VodViewModel::class.java)
                        model.selectCategory(model.ui.value.category!!.id)
                    }
                    waitFor(scenario) {
                        val list = it.findViewById<androidx.recyclerview.widget.RecyclerView>(com.flytech.juying.feature.vod.R.id.posters)
                        val grid = list.layoutManager as androidx.recyclerview.widget.GridLayoutManager
                        val last = grid.getChildAt(grid.childCount - 1)
                        pages == listOf(1) && last != null && grid.findFirstVisibleItemPosition() == 0 &&
                            grid.getDecoratedBottom(last) >= list.height * 2 - list.paddingTop - list.paddingBottom * 2 &&
                            last.findViewById<android.widget.ImageView>(com.flytech.juying.core.ui.R.id.cover).drawable is android.graphics.drawable.BitmapDrawable
                    }
                    capture("15-vod-cover-prefetch")
                    scenario.onActivity {
                        val bar = it.findViewById<com.google.android.material.appbar.AppBarLayout>(com.flytech.juying.feature.vod.R.id.category_bar)
                        val grid = it.findViewById<androidx.recyclerview.widget.RecyclerView>(com.flytech.juying.feature.vod.R.id.posters)
                        assertEquals("Single-site VOD has no redundant heading", 0, bar.totalScrollRange)
                        grid.startNestedScroll(androidx.core.view.ViewCompat.SCROLL_AXIS_VERTICAL, androidx.core.view.ViewCompat.TYPE_TOUCH)
                        grid.dispatchNestedPreScroll(0, bar.totalScrollRange, IntArray(2), null, androidx.core.view.ViewCompat.TYPE_TOUCH)
                        grid.stopNestedScroll(androidx.core.view.ViewCompat.TYPE_TOUCH)
                        val behavior = (bar.layoutParams as androidx.coordinatorlayout.widget.CoordinatorLayout.LayoutParams).behavior as com.google.android.material.appbar.AppBarLayout.Behavior
                        assertEquals(-bar.totalScrollRange, behavior.topAndBottomOffset)
                        val categories = it.findViewById<View>(com.flytech.juying.feature.vod.R.id.categories)
                        assertTrue("Categories remain visible above the grid", categories.isShown)
                    }
                    scenario.onActivity {
                        assertFalse(allTexts(it.window.decorView).contains("加载下一页"))
                        val list = it.findViewById<androidx.recyclerview.widget.RecyclerView>(com.flytech.juying.feature.vod.R.id.posters)
                        val grid = list.layoutManager as androidx.recyclerview.widget.GridLayoutManager
                        val bounds = android.graphics.Rect()
                        grid.getDecoratedBoundsWithMargins(grid.getChildAt(0)!!, bounds)
                        val screenRows = kotlin.math.ceil((list.height - list.paddingTop - list.paddingBottom).toDouble() / bounds.height()).toInt()
                        grid.scrollToPositionWithOffset(60 - screenRows * grid.spanCount * 2, 0)
                    }
                    waitFor(scenario) { pages.contains(2) }
                    scenario.onActivity {
                        val list = it.findViewById<androidx.recyclerview.widget.RecyclerView>(com.flytech.juying.feature.vod.R.id.posters)
                        val grid = list.layoutManager as androidx.recyclerview.widget.GridLayoutManager
                        assertTrue("Request starts before the final row is visible", grid.findLastVisibleItemPosition() < 60 - grid.spanCount)
                        assertEquals("Existing items stay visible during prefetch", 60, list.adapter!!.itemCount)
                        assertFalse("Background prefetch must not show a loading animation", it.findViewById<View>(com.flytech.juying.feature.vod.R.id.progress).isShown)
                        list.scrollBy(0, 1)
                    }
                    assertEquals(listOf(1, 2), pages.toList())
                    releaseNextPage.countDown()
                    waitFor(scenario) { it.findViewById<androidx.recyclerview.widget.RecyclerView>(com.flytech.juying.feature.vod.R.id.posters).adapter!!.itemCount == 61 }
                    scenario.onActivity { it.findViewById<androidx.recyclerview.widget.RecyclerView>(com.flytech.juying.feature.vod.R.id.posters).scrollToPosition(60) }
                    waitFor(scenario) {
                        val host = it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
                        val model = androidx.lifecycle.ViewModelProvider(host.childFragmentManager.primaryNavigationFragment!!)
                            .get(com.flytech.juying.feature.vod.VodViewModel::class.java)
                        model.ui.value.page == 3 && !model.ui.value.hasMore
                    }
                    assertEquals(listOf(1, 2, 3), pages.toList())
                    firstPageSize.set(1)
                    pages.clear()
                    scenario.onActivity {
                        val host = it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
                        val model = androidx.lifecycle.ViewModelProvider(host.childFragmentManager.primaryNavigationFragment!!)
                            .get(com.flytech.juying.feature.vod.VodViewModel::class.java)
                        model.selectCategory(model.ui.value.category!!.id)
                    }
                    waitFor(scenario) { pages.contains(3) }
                    assertEquals("Short pages preload without another scroll", listOf(1, 2, 3), pages.toList())
                } finally {
                    releaseNextPage.countDown()
                    scenario.onActivity { activity -> previousSource?.let { activity.memory.select(it, SourceCapability.VOD) } }
                    repository.delete(source.id)
                }
            }
        }
    }

    @Test fun designCoverLoadsThroughAppImageLoader(): Unit = runBlocking {
        MockWebServer().use { server ->
            val hero = instrumentation.context.assets.open("design-hero.png").use { it.readBytes() }
            server.enqueue(MockResponse().setHeader("Content-Type", "image/png").setBody(okio.Buffer().write(hero)))
            val result = context.imageLoader.execute(coil.request.ImageRequest.Builder(context)
                .data(server.url("/hero.png").toString()).size(256).build())
            if (result is coil.request.ErrorResult) throw AssertionError("Design cover failed to decode", result.throwable)
            assertTrue(result is coil.request.SuccessResult)
        }
    }

    @Test fun qualifiersSelectPhoneTabletAndTv() {
        for ((smallestWidth, mode, qualifier) in listOf(
            Triple(360, android.content.res.Configuration.UI_MODE_TYPE_NORMAL, "layout/"),
            Triple(800, android.content.res.Configuration.UI_MODE_TYPE_NORMAL, "layout-sw600dp"),
            Triple(720, android.content.res.Configuration.UI_MODE_TYPE_TELEVISION, "television"),
        )) {
            val configuration = android.content.res.Configuration(context.resources.configuration).apply {
                smallestScreenWidthDp = smallestWidth
                screenWidthDp = if (smallestWidth == 360) 360 else 1280
                screenHeightDp = if (smallestWidth == 360) 800 else smallestWidth
                orientation = if (smallestWidth == 360) android.content.res.Configuration.ORIENTATION_PORTRAIT else android.content.res.Configuration.ORIENTATION_LANDSCAPE
                uiMode = (uiMode and android.content.res.Configuration.UI_MODE_TYPE_MASK.inv()) or mode
            }
            val resources = context.createConfigurationContext(configuration).resources
            val value = android.util.TypedValue()
            resources.getValue(R.layout.activity_main, value, true)
            assertTrue("Expected $qualifier, got ${value.string}", value.string.toString().contains(qualifier))
            if (mode == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION) {
                assertEquals(32f, resources.getDimension(com.flytech.juying.core.designsystem.R.dimen.jy_padding) / resources.displayMetrics.density, .1f)
            }
            assertEquals(if (mode == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION) 56f else 48f,
                resources.getDimension(com.flytech.juying.feature.player.R.dimen.player_control_size) / resources.displayMetrics.density, .1f)
        }
    }

    @Test fun pagesThemesAndSourcePickerRemainReachable(): Unit = runBlocking {
        val oldLanguage = Appearance.language(context)
        val oldTheme = Appearance.theme(context)
        val server = MockWebServer()
        val video = instrumentation.context.assets.open("design-preview.mp4").use { it.readBytes() }
        val hero = instrumentation.context.assets.open("design-hero.png").use { it.readBytes() }
        val sheet = instrumentation.context.assets.open("design-posters.png").use { android.graphics.BitmapFactory.decodeStream(it) }
        val posters = (0..5).map { index ->
            val tile = Bitmap.createBitmap(sheet, index % 3 * sheet.width / 3, index / 3 * sheet.height / 2, sheet.width / 3, sheet.height / 2)
            java.io.ByteArrayOutputStream().use { output ->
                tile.compress(Bitmap.CompressFormat.JPEG, 92, output); tile.recycle(); output.toByteArray()
            }
        }
        sheet.recycle()
        val titles = listOf("山海之间", "夏日来信", "夜行者", "远航", "无人之境", "潮汐", "林间")
        val episodeNames = listOf("第1集 · 初见群山", "第2集 · 湖泊的来信", "第3集 · 越过风口", "第4集 · 山的另一边")
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val url = request.requestUrl!!
                if (url.encodedPath == "/video.mp4") return MockResponse()
                    .setHeader("Content-Type", "video/mp4").setBody(okio.Buffer().write(video))
                if (url.encodedPath == "/hero.png") return MockResponse().setHeader("Content-Type", "image/png").setBody(okio.Buffer().write(hero))
                if (url.encodedPath.startsWith("/poster/")) return MockResponse().setHeader("Content-Type", "image/jpeg")
                    .setBody(okio.Buffer().write(posters[url.pathSegments.last().toInt()]))
                if (url.queryParameter("ac") == null) return MockResponse().setBody("""{"class":[{"type_id":"test","type_name":"精选"}]}""")
                val rows = org.json.JSONArray()
                titles.forEachIndexed { index, title ->
                    if ((url.queryParameter("ids") == null || url.queryParameter("ids") == index.toString()) &&
                        (url.queryParameter("pg")?.toIntOrNull() ?: 1) == 1) {
                        rows.put(org.json.JSONObject().put("vod_id", index.toString()).put("vod_name", title)
                            .put("vod_pic", server.url(if (index == 0) "/hero.png" else "/poster/${index - 1}").toString())
                            .put("vod_year", "2026").put("vod_remarks", "原创设计示例")
                            .put("vod_content", "从清晨的第一束光，到山谷深处的回声。跟随镜头，走进群山、湖泊与生活在这里的人。")
                            .put("vod_play_from", "主线路")
                            .put("vod_play_url", episodeNames.joinToString("#") { "$it${'$'}${server.url("/video.mp4")}" }))
                    }
                }
                return MockResponse().setBody(org.json.JSONObject().put("list", rows).toString())
            }
        }
        server.start()
        var repository: SourceRepository? = null
        var history: HistoryRepository? = null
        lateinit var playRequest: PlayRequest
        val source = SourceConfig("native-ui-test", "影视仓库", SourceType.TVBOX, server.url("/cms").toString())
        try {
            Appearance.setLanguage(context, "zh-Hans")
            Appearance.setTheme(context, "dark")
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { repository = it.sources }
                scenario.onActivity {
                    for (id in listOf(R.id.source_switch, R.id.global_search, R.id.global_history)) {
                        val button = it.findViewById<android.widget.Button>(id)
                        assertNotNull("Toolbar action keeps its icon", button.compoundDrawablesRelative[0])
                        assertTrue(button.text.isNotBlank())
                    }
                    assertNotNull(it.findViewById<android.widget.Button>(R.id.source_switch).compoundDrawablesRelative[2])
                }
                repository!!.upsert(source)
                scenario.onActivity { it.memory.select(source.id, SourceCapability.VOD) }
                navigate(scenario, R.id.nav_home, "01-home")
                scenario.onActivity {
                    val host = it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
                    history = (host.childFragmentManager.primaryNavigationFragment as com.flytech.juying.feature.home.HomeFragment).history
                }
                navigate(scenario, R.id.nav_live, "02-live")
                navigate(scenario, R.id.nav_vod, "03-vod")
                waitFor(scenario) { activity -> allTexts(activity.window.decorView).any { it == "山海之间" } }
                waitFor(scenario) {
                    it.findViewById<android.widget.ImageView>(com.flytech.juying.core.ui.R.id.cover)?.drawable is android.graphics.drawable.BitmapDrawable
                }
                capture("03-vod-loaded")
                scenario.onActivity { activity ->
                    val host = activity.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
                    val model = androidx.lifecycle.ViewModelProvider(host.childFragmentManager.primaryNavigationFragment!!)
                        .get(com.flytech.juying.feature.vod.VodViewModel::class.java)
                    host.navController.navigate(R.id.vod_detail, Bundle().apply {
                        putString("sourceId", source.id); putString("itemId", model.ui.value.items.first().id)
                    })
                }
                waitFor(scenario) { allTexts(it.window.decorView).any { text -> text.contains("初见群山") } }
                waitFor(scenario) {
                    it.findViewById<android.widget.ImageView>(com.flytech.juying.feature.vod.R.id.cover)?.drawable is android.graphics.drawable.BitmapDrawable
                }
                capture("04-detail")
                scenario.onActivity {
                    val play = it.findViewById<View>(com.flytech.juying.feature.vod.R.id.play)
                    val visible = android.graphics.Rect()
                    assertTrue(play.getGlobalVisibleRect(visible))
                    assertEquals(play.height, visible.height())
                }
                scenario.onActivity {
                    val host = it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
                    val detail = androidx.lifecycle.ViewModelProvider(host.childFragmentManager.primaryNavigationFragment!!)
                        .get(com.flytech.juying.feature.vod.VodDetailViewModel::class.java).ui.value.detail!!
                    val episode = detail.playGroups.first().episodes[1]
                    playRequest = PlayRequest(PlayKind.VOD, source.id, episode.ref, episode.name,
                        mapOf("cover" to detail.item.cover.orEmpty(), "itemId" to detail.item.id,
                            "mediaTitle" to detail.item.title, "episodeTitle" to episode.name))
                }
                for (index in 3 downTo 0) {
                    val ref = org.json.JSONObject(playRequest.ref).apply {
                        getJSONObject("item").put("id", index.toString())
                        put("episodeName", episodeNames.first()); put("episodeIndex", 0)
                    }.toString()
                    history!!.record(com.flytech.juying.core.model.HistoryEntry("${source.id}:$ref", PlayKind.VOD, source.id, ref,
                        titles[index], 18_000L, 60_000L, System.currentTimeMillis() + 4 - index,
                        server.url(if (index == 0) "/hero.png" else "/poster/${index - 1}").toString()))
                }
                navigate(scenario, R.id.nav_home, "01-home")
                waitFor(scenario) {
                    it.findViewById<androidx.recyclerview.widget.RecyclerView>(com.flytech.juying.feature.home.R.id.recommendations)
                        ?.getChildAt(0)?.findViewById<android.widget.ImageView>(com.flytech.juying.core.ui.R.id.cover)?.drawable is android.graphics.drawable.BitmapDrawable
                }
                capture("01-home")
                navigate(scenario, R.id.nav_browse, "05-files-empty")
                navigate(scenario, R.id.search, "06-search")
                navigate(scenario, R.id.history, "07-history")
                navigate(scenario, R.id.sources, "08-sources")
                navigate(scenario, com.flytech.juying.feature.settings.R.id.playback_settings, "09-playback-settings")
                navigate(scenario, R.id.nav_settings, "10-appearance-dark")
                scenario.onActivity {
                    it.findViewById<View>(com.flytech.juying.feature.settings.R.id.manage).performClick()
                }
                waitFor(scenario, "Settings opens source manager") { (it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment).navController.currentDestination?.id == R.id.sources }
                scenario.onActivity {
                    val host = it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
                    val editor = androidx.lifecycle.ViewModelProvider(host.childFragmentManager.primaryNavigationFragment!!)
                        .get(com.flytech.juying.feature.settings.SettingsViewModel::class.java).ui.value
                    assertFalse("No pending save should block navigation", editor.saving)
                    assertNull("Source list has no unsaved editor", editor.editor)
                    val nav = it.findViewById<com.google.android.material.navigation.NavigationBarView>(R.id.nav_bar)
                    val before = nav.selectedItemId
                    nav.selectedItemId = R.id.nav_home
                    instrumentation.sendStatus(0, Bundle().apply { putString("stream",
                        "Navigation: selected=$before -> ${nav.selectedItemId}, destination=${host.navController.currentDestination}\n") })
                }
                waitFor(scenario, "Source manager returns to home") { (it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment).navController.currentDestination?.id == R.id.nav_home }
                scenario.onActivity { it.findViewById<com.google.android.material.navigation.NavigationBarView>(R.id.nav_bar).selectedItemId = R.id.nav_settings }
                waitFor(scenario, "Settings returns to overview") { (it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment).navController.currentDestination?.id == R.id.nav_settings }
                for (theme in listOf("light", "black", "dark")) {
                    scenario.onActivity { Appearance.setTheme(it, theme) }
                    scenario.recreate()
                    waitFor(scenario) { it.findViewById<View>(R.id.shell)?.isShown == true }
                    scenario.onActivity { assertEquals("zh-Hans", Appearance.language(it)) }
                    scenario.onActivity {
                        assertEquals(theme == "dark", it.findViewById<android.widget.RadioButton>(com.flytech.juying.feature.settings.R.id.theme_dark).isChecked)
                        assertEquals(theme == "light", it.findViewById<android.widget.RadioButton>(com.flytech.juying.feature.settings.R.id.theme_light).isChecked)
                    }
                    capture("11-appearance-$theme")
                }
                scenario.onActivity { Appearance.setLanguage(it, "en") }
                scenario.recreate()
                waitFor(scenario) { allTexts(it.window.decorView).any { text -> text == "Settings" } }
                scenario.onActivity { assertEquals("dark", Appearance.theme(it)) }
                scenario.onActivity {
                    assertTrue(it.findViewById<android.widget.RadioButton>(com.flytech.juying.feature.settings.R.id.language_english).isChecked)
                    assertFalse(it.findViewById<android.widget.RadioButton>(com.flytech.juying.feature.settings.R.id.language_hans).isChecked)
                }
                capture("12-appearance-english")
                scenario.onActivity { Appearance.setLanguage(it, "zh-Hans") }
                scenario.recreate()
                waitFor(scenario) { Appearance.language(it) == "zh-Hans" }
                instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_DOWN)
                scenario.onActivity { it.findViewById<View>(R.id.source_switch).apply { requestFocus(); performClick() } }
                waitFor(scenario) { (it.supportFragmentManager.findFragmentByTag("source-picker") as? SourcePickerDialog)?.dialog?.isShowing == true }
                delay(500)
                capture("13-source-picker")
                scenario.onActivity {
                    val picker = it.supportFragmentManager.findFragmentByTag("source-picker") as SourcePickerDialog
                    assertNotNull(picker.dialog!!.currentFocus)
                    val manage = picker.dialog!!.findViewById<View>(R.id.manage)
                    val visible = android.graphics.Rect()
                    assertTrue(manage.getGlobalVisibleRect(visible))
                    assertEquals(manage.height, visible.height())
                }
                instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
                waitFor(scenario) { it.supportFragmentManager.findFragmentByTag("source-picker") == null }
                scenario.onActivity { assertNotNull(it.currentFocus) }
            }
            checkPlayer(playRequest)
        } finally {
            history?.let { repo -> repo.observeRecent(500).first().filter { it.sourceId == source.id }.forEach { repo.delete(it.id) } }
            repository?.delete(source.id)
            Appearance.setLanguage(context, oldLanguage)
            Appearance.setTheme(context, oldTheme)
            server.shutdown()
        }
    }

    private suspend fun checkPlayer(request: PlayRequest) {
        ActivityScenario.launch<com.flytech.juying.feature.player.PlayerActivity>(
            com.flytech.juying.feature.player.PlayerActivity.intent(context, request)
        ).use { scenario ->
            lateinit var model: com.flytech.juying.feature.player.PlayerViewModel
            scenario.onActivity { model = androidx.lifecycle.ViewModelProvider(it).get(com.flytech.juying.feature.player.PlayerViewModel::class.java) }
            kotlinx.coroutines.withTimeout(15_000) {
                while (!model.ui.value.playback.isPlaying) delay(100)
            }
            scenario.onActivity {
                assertTrue(it.findViewById<android.view.SurfaceView>(com.flytech.juying.feature.player.R.id.surface).isShown)
                assertEquals(1280, model.ui.value.playback.videoWidth)
            }
            delay(1_200)
            val position = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) { model.positionMs() }
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
            delay(350)
            assertFalse(model.ui.value.playback.isPlaying)
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                kotlinx.coroutines.withTimeout(8_000) {
                    while (!model.ui.value.playback.isPlaying || model.positionMs() <= position) delay(100)
                }
            }
            scenario.onActivity { activity ->
                val root = activity.findViewById<View>(android.R.id.content) as android.view.ViewGroup
                val content = root.getChildAt(0)
                val actual = androidx.core.view.ViewCompat.getRootWindowInsets(content)!!
                val simulated = androidx.core.view.WindowInsetsCompat.Builder(actual)
                    .setInsets(androidx.core.view.WindowInsetsCompat.Type.systemBars(), androidx.core.graphics.Insets.of(0, 0, 120, 0)).build()
                androidx.core.view.ViewCompat.dispatchApplyWindowInsets(content, simulated)
                assertEquals(120, content.paddingRight)
                androidx.core.view.ViewCompat.dispatchApplyWindowInsets(content, actual)
            }
            instrumentation.waitForIdleSync()
            delay(400) // Let the resumed SurfaceView and inset layout reach the compositor before capture.
            scenario.onActivity {
                if (!it.findViewById<View>(com.flytech.juying.feature.player.R.id.controls).isShown)
                    it.findViewById<View>(com.flytech.juying.feature.player.R.id.video_stage).performClick()
                it.findViewById<View>(com.flytech.juying.feature.player.R.id.play_pause).requestFocus()
            }
            instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_RIGHT)
            scenario.onActivity { assertEquals(com.flytech.juying.feature.player.R.id.next, it.currentFocus?.id) }
            instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_RIGHT)
            scenario.onActivity { assertEquals(com.flytech.juying.feature.player.R.id.quality, it.currentFocus?.id) }
            instrumentation.waitForIdleSync()
            capture("14-player")
            scenario.onActivity {
                val transport = it.findViewById<View>(com.flytech.juying.feature.player.R.id.transport)
                val controls = it.findViewById<View>(com.flytech.juying.feature.player.R.id.controls)
                val transportRect = android.graphics.Rect()
                val controlsRect = android.graphics.Rect()
                assertTrue(transport.getGlobalVisibleRect(transportRect))
                assertTrue(controls.getGlobalVisibleRect(controlsRect))
                val progressRect = android.graphics.Rect()
                it.findViewById<View>(com.flytech.juying.feature.player.R.id.progress).getGlobalVisibleRect(progressRect)
                assertTrue("Transport belongs below the timeline", transportRect.top >= progressRect.bottom)
                assertTrue("Transport stays inside the bottom controls", controlsRect.contains(transportRect))
                assertTrue(it.findViewById<View>(com.flytech.juying.feature.player.R.id.previous) is android.widget.ImageButton)
                it.findViewById<View>(com.flytech.juying.feature.player.R.id.previous).performClick()
            }
            kotlinx.coroutines.withTimeout(15_000) { while (model.currentRequest?.ref == request.ref || !model.ui.value.playback.isPlaying) delay(100) }
            scenario.onActivity {
                assertFalse("First episode has no previous episode", it.findViewById<View>(com.flytech.juying.feature.player.R.id.previous).isEnabled)
                it.findViewById<View>(com.flytech.juying.feature.player.R.id.next).performClick()
            }
            kotlinx.coroutines.withTimeout(15_000) { while (model.currentRequest?.ref != request.ref || !model.ui.value.playback.isPlaying) delay(100) }
            scenario.onActivity {
                it.findViewById<View>(com.flytech.juying.feature.player.R.id.episodes).performClick()
            }
            instrumentation.withDialogWindows {
                kotlinx.coroutines.withTimeout(8_000) {
                    while (true) {
                        val choice = instrumentation.findDialogListChoice("第3集 · 越过风口")
                        if (choice != null) {
                            instrumentation.clickDialogListChoice(choice)
                            break
                        }
                        delay(100)
                    }
                }
            }
            kotlinx.coroutines.withTimeout(15_000) {
                while (model.currentRequest?.ref == request.ref || !model.ui.value.playback.isPlaying) delay(100)
            }
            assertEquals("第3集 · 越过风口", model.currentRequest!!.extra["episodeTitle"])
            scenario.onActivity { it.findViewById<View>(com.flytech.juying.feature.player.R.id.next).performClick() }
            kotlinx.coroutines.withTimeout(15_000) { while (model.currentRequest!!.extra["episodeTitle"] != "第4集 · 山的另一边" || !model.ui.value.playback.isPlaying) delay(100) }
            scenario.onActivity { assertFalse("Last episode has no next episode", it.findViewById<View>(com.flytech.juying.feature.player.R.id.next).isEnabled) }
            val activeRef = model.currentRequest!!.ref
            instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_MENU)
            delay(500)
            scenario.onActivity {
                assertTrue((it.supportFragmentManager.findFragmentByTag("source-picker") as SourcePickerDialog).dialog!!.isShowing)
                assertEquals(activeRef, model.currentRequest!!.ref)
                assertTrue(model.ui.value.playback.isPlaying)
            }
            capture("15-player-source-picker")
            instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
            delay(300)
            scenario.onActivity {
                assertNull(it.supportFragmentManager.findFragmentByTag("source-picker"))
                assertTrue(model.ui.value.playback.isPlaying)
                it.findViewById<View>(com.flytech.juying.feature.player.R.id.play_pause).performClick()
            }
            delay(200)
            assertFalse(model.ui.value.playback.isPlaying)
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
            delay(350)
            assertFalse("Manual pause must survive background and foreground", model.ui.value.playback.isPlaying)
        }
    }

    private suspend fun navigate(scenario: ActivityScenario<MainActivity>, destination: Int, snapshot: String) {
        scenario.onActivity {
            (it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment).navController.navigate(destination)
        }
        instrumentation.waitForIdleSync()
        delay(650)
        scenario.onActivity {
            val host = it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
            assertEquals(destination, host.navController.currentDestination!!.id)
            assertTrue(host.childFragmentManager.primaryNavigationFragment!!.requireView().isShown)
        }
        capture(snapshot)
    }

    private suspend fun waitFor(scenario: ActivityScenario<MainActivity>, step: String = "UI", condition: (MainActivity) -> Boolean) {
        repeat(80) {
            var ready = false
            scenario.onActivity { ready = condition(it) }
            if (ready) { instrumentation.waitForIdleSync(); delay(250); return }
            delay(100)
        }
        var destination = ""
        scenario.onActivity { destination = (it.supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment).navController.currentDestination.toString() }
        capture("failure")
        fail("$step did not become ready; $destination")
    }

    private fun allTexts(view: View): List<String> = buildList {
        if (view is TextView && view.isShown) add(view.text.toString())
        if (view is android.view.ViewGroup) for (index in 0 until view.childCount) addAll(allTexts(view.getChildAt(index)))
    }

    private fun capture(name: String) {
        val directory = File(context.getExternalFilesDir(null), "ui-check").apply { mkdirs() }
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: error("Screenshot unavailable")
        File(directory, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }
}
