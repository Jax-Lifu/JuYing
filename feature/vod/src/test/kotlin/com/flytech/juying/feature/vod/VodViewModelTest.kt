package com.flytech.juying.feature.vod

import com.flytech.juying.core.model.*
import com.flytech.juying.core.testing.*
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class VodViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val first = SourceConfig("first", "First", SourceType.TVBOX, "https://example.test")
    private val second = first.copy(id = "second")

    @Test fun declaredNextPageSurvivesAnOverlappingPage() = runTest {
        val pages = mutableListOf<Int>()
        val repository = object : FakeVodRepository() {
            override suspend fun categories(sourceId: String) = listOf(VodCategory("all", "All"))
            override suspend fun listPage(sourceId: String, categoryId: String, page: Int): VodPage {
                pages += page
                return VodPage(listOf(VodItem(if (page < 3) "same" else "next", sourceId, "Item")), page < 3)
            }
        }
        val vm = VodViewModel(FakeSourceRepository(listOf(first)), repository)
        runCurrent()
        vm.more(); runCurrent()
        assertTrue("A repeated page with more pages is not the end", vm.ui.value.hasMore)
        vm.more(); runCurrent()
        assertEquals(listOf(1, 2, 3), pages)
        assertEquals(listOf("same", "next"), vm.ui.value.items.map { it.id })
        assertFalse(vm.ui.value.hasMore)
    }

    @Test fun incorrectPageCountCannotCreateAnUnboundedBackgroundLoop() = runTest {
        val repository = object : FakeVodRepository() {
            override suspend fun categories(sourceId: String) = listOf(VodCategory("all", "All"))
            override suspend fun listPage(sourceId: String, categoryId: String, page: Int) = VodPage(emptyList(), true)
        }
        val vm = VodViewModel(FakeSourceRepository(listOf(first)), repository)
        runCurrent()
        repeat(20) { vm.more(); runCurrent() }
        assertEquals(3, vm.ui.value.page)
        assertTrue(vm.ui.value.failed)
        assertTrue("A stalled source must not pretend it reached the end", vm.ui.value.hasMore)
        vm.retry(); runCurrent()
        assertEquals(4, vm.ui.value.page)
        assertFalse(vm.ui.value.failed)
    }

    @Test fun switchingSourceCancelsOldListAndKeepsNewResult() = runTest {
        var cancelled = false
        val repository = object : FakeVodRepository() {
            override suspend fun categories(sourceId: String) = listOf(VodCategory("all", "All"))
            override suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem> {
                if (sourceId == first.id) try { awaitCancellation() } finally { cancelled = true }
                return listOf(VodItem("new", sourceId, "New"))
            }
        }
        val vm = VodViewModel(FakeSourceRepository(listOf(first, second)), repository)
        runCurrent()
        vm.selectSource(second)
        runCurrent()
        assertTrue(cancelled)
        assertEquals(listOf("second"), vm.ui.value.items.map { it.sourceId })
        assertFalse(vm.ui.value.loading)
    }

    @Test fun failedNextPageRetriesSamePageWithoutLosingExistingItems() = runTest {
        val pages = mutableListOf<Int>()
        var fail = true
        val repository = object : FakeVodRepository() {
            override suspend fun categories(sourceId: String) = listOf(VodCategory("all", "All"))
            override suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem> {
                pages += page
                if (page == 2 && fail) error("offline")
                return listOf(VodItem(page.toString(), sourceId, "Episode $page"))
            }
        }
        val vm = VodViewModel(FakeSourceRepository(listOf(first)), repository)
        runCurrent()
        vm.more()
        runCurrent()
        assertTrue(vm.ui.value.failed)
        assertEquals(1, vm.ui.value.items.size)
        vm.more()
        runCurrent()
        assertEquals("Scrolling must not repeatedly retry a failed page", listOf(1, 2), pages)
        fail = false
        vm.retry()
        runCurrent()
        assertEquals(listOf(1, 2, 2), pages)
        assertEquals(2, vm.ui.value.items.size)
    }

    @Test fun paginationIgnoresRepeatedTriggersAndStopsOnDuplicatePage() = runTest {
        val pages = mutableListOf<Int>()
        val release = CompletableDeferred<Unit>()
        val repository = object : FakeVodRepository() {
            override suspend fun categories(sourceId: String) = listOf(VodCategory("all", "All"))
            override suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem> {
                pages += page
                if (page == 2) release.await()
                return listOf(VodItem(page.coerceAtMost(2).toString(), sourceId, "Episode"))
            }
        }
        val vm = VodViewModel(FakeSourceRepository(listOf(first)), repository)
        runCurrent()
        repeat(5) { vm.more() }
        runCurrent()
        assertEquals(listOf(1, 2), pages)
        release.complete(Unit)
        runCurrent()
        vm.more()
        runCurrent()
        assertFalse(vm.ui.value.hasMore)
        repeat(5) { vm.more() }
        runCurrent()
        assertEquals(listOf(1, 2, 3), pages)
        assertEquals(2, vm.ui.value.items.size)
    }

    @Test fun cancelledSourceCannotPublishLateSitesCategoriesItemsOrErrors() = runTest {
        for (stage in listOf("sites", "categories", "items", "error")) {
            val release = CompletableDeferred<Unit>()
            suspend fun lateResult(sourceId: String, at: String) {
                if (sourceId == first.id && stage == at) {
                    withContext(NonCancellable) { release.await() }
                    if (stage == "error") error("late failure from old source")
                }
            }
            val repository = object : FakeVodRepository() {
                override suspend fun subSources(sourceId: String): List<SubSource> {
                    lateResult(sourceId, "sites")
                    return listOf(SubSource(sourceId, sourceId))
                }
                override suspend fun categories(sourceId: String): List<VodCategory> {
                    lateResult(sourceId, "categories")
                    return listOf(VodCategory(sourceId, sourceId))
                }
                override suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem> {
                    lateResult(sourceId, "items")
                    lateResult(sourceId, "error")
                    return listOf(VodItem(sourceId, sourceId, sourceId))
                }
            }
            val vm = VodViewModel(FakeSourceRepository(listOf(first, second)), repository)
            runCurrent()
            vm.selectSource(second)
            runCurrent()
            val expected = vm.ui.value
            assertEquals(listOf(second.id), expected.items.map { it.sourceId })
            release.complete(Unit)
            runCurrent()
            assertEquals("Late $stage must not change the selected source", expected, vm.ui.value)
        }
    }
}
