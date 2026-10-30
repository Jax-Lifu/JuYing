package com.flytech.juying.feature.home

import com.flytech.juying.core.model.HistoryEntry
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.model.VodCategory
import com.flytech.juying.core.model.VodItem
import com.flytech.juying.core.testing.FakeVodRepository
import com.flytech.juying.core.testing.MainDispatcherRule
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelTest {
    @get:Rule val dispatcher = MainDispatcherRule()

    @Test
    fun `recommendations keep all unseen items in order without confusing sources`() {
        val items = listOf(
            VodItem("film", "a", "Viewed album"),
            VodItem("new", "a", "New film"),
            VodItem("film", "b", "Other source"),
            VodItem("direct", "a", "Viewed directly"),
            VodItem("last", "a", "Last film"),
        )
        val history = listOf(
            HistoryEntry("album", PlayKind.VOD, "a", "episode", "Viewed album", 0, 0, 0, extra = mapOf("itemId" to "film")),
            HistoryEntry("direct", PlayKind.VOD, "a", "direct", "Viewed directly", 0, 0, 0),
        )
        assertEquals(listOf(items[1], items[2], items[4]), HomeViewModel.recommendationsFor(items, history))
        assertEquals(items, HomeViewModel.recommendationsFor(items, emptyList()))
    }

    @Test
    fun `empty or fully watched candidates produce no recommendations`() {
        val item = VodItem("film", "a", "Viewed")
        val history = listOf(HistoryEntry("h", PlayKind.VOD, "a", "film", "Viewed", 0, 0, 0))
        assertEquals(emptyList<VodItem>(), HomeViewModel.recommendationsFor(listOf(item), history))
        assertEquals(emptyList<VodItem>(), HomeViewModel.recommendationsFor(emptyList(), history))
    }

    @Test
    fun `one source page is reused and a source switch cancels old recommendations`() = runTest {
        val pending = CompletableDeferred<List<VodItem>>()
        val calls = mutableListOf<String>()
        val repo = object : FakeVodRepository() {
            override suspend fun categories(sourceId: String) = listOf(VodCategory("category", "Category"))
            override suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem> {
                calls += sourceId
                assertEquals(1, page)
                return if (sourceId == "slow") pending.await() else listOf(VodItem("film", sourceId, "Film"))
            }
        }
        val vm = HomeViewModel(repo)
        vm.load(source("slow"))
        vm.load(source("next"))
        vm.load(source("next"))
        pending.complete(listOf(VodItem("old", "slow", "Old")))
        assertEquals(listOf("slow", "next"), calls)
        assertEquals("next", vm.recommendations.value.single().sourceId)
        vm.load(null)
        assertEquals(emptyList<VodItem>(), vm.recommendations.value)
    }

    @Test
    fun `recommendations keep at most 24 items from only the first category page`() = runTest {
        val items = (1..30).map { VodItem("film-$it", "source", "Film $it") }
        val calls = mutableListOf<Pair<String, Int>>()
        val vm = HomeViewModel(object : FakeVodRepository() {
            override suspend fun categories(sourceId: String) = listOf(VodCategory("first", "First"), VodCategory("second", "Second"))
            override suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem> {
                calls += categoryId to page
                return items
            }
        })
        vm.load(source("source"))
        assertEquals(listOf("first" to 1), calls)
        assertEquals(items.take(24), vm.recommendations.value)
    }

    @Test
    fun `unavailable recommendations leave an empty list`() = runTest {
        val vm = HomeViewModel(object : FakeVodRepository() {
            override suspend fun categories(sourceId: String): List<VodCategory> = error("offline")
        })
        vm.load(source("offline"))
        assertEquals(emptyList<VodItem>(), vm.recommendations.value)
    }

    @Test
    fun `same source id reloads changed configuration but reuses a successful result`() = runTest {
        var requests = 0
        val vm = HomeViewModel(object : FakeVodRepository() {
            override suspend fun categories(sourceId: String) = listOf(VodCategory("category", "Category"))
            override suspend fun list(sourceId: String, categoryId: String, page: Int) =
                listOf(VodItem("film-${++requests}", sourceId, "Film $requests"))
        })
        val original = source("same")
        vm.load(original)
        vm.load(original.copy())
        assertEquals(1, requests)
        vm.load(original.copy(url = "https://changed.test/config"))
        assertEquals(2, requests)
        assertEquals("film-2", vm.recommendations.value.single().id)
    }

    @Test
    fun `failed recommendation request can retry the same configuration`() = runTest {
        var attempts = 0
        val vm = HomeViewModel(object : FakeVodRepository() {
            override suspend fun categories(sourceId: String): List<VodCategory> {
                if (++attempts == 1) error("offline")
                return listOf(VodCategory("category", "Category"))
            }
            override suspend fun list(sourceId: String, categoryId: String, page: Int) = listOf(VodItem("film", sourceId, "Recovered"))
        })
        val config = source("retry")
        vm.load(config)
        assertEquals(emptyList<VodItem>(), vm.recommendations.value)
        vm.load(config)
        vm.load(config)
        assertEquals(2, attempts)
        assertEquals("Recovered", vm.recommendations.value.single().title)
    }

    @Test
    fun `successful empty recommendations are cached`() = runTest {
        var attempts = 0
        val vm = HomeViewModel(object : FakeVodRepository() {
            override suspend fun categories(sourceId: String): List<VodCategory> { attempts++; return emptyList() }
        })
        vm.load(source("empty"))
        vm.load(source("empty"))
        assertEquals(1, attempts)
    }

    @Test
    fun `late result from old configuration cannot replace the new result`() = runTest {
        var continuation: Continuation<List<VodItem>>? = null
        var attempts = 0
        val vm = HomeViewModel(object : FakeVodRepository() {
            override suspend fun categories(sourceId: String) = listOf(VodCategory("category", "Category"))
            override suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem> {
                if (++attempts == 1) return suspendCoroutine { continuation = it }
                return listOf(VodItem("new", sourceId, "New configuration"))
            }
        })
        val original = source("same")
        vm.load(original)
        vm.load(original)
        assertEquals(1, attempts)
        vm.load(original.copy(url = "https://changed.test/config"))
        continuation!!.resume(listOf(VodItem("old", original.id, "Old configuration")))
        assertEquals(2, attempts)
        assertEquals("new", vm.recommendations.value.single().id)
    }

    private fun source(id: String) = SourceConfig(id, id, SourceType.TVBOX, "https://$id.test/config")
}
