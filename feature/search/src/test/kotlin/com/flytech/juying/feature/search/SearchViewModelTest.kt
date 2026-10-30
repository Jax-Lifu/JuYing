package com.flytech.juying.feature.search

import com.flytech.juying.core.model.*
import com.flytech.juying.core.testing.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SearchViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val target = SearchTarget("one", "One")

    @Test fun showsEarlyResultsAndCancelsPreviousKeyword() = runTest {
        var cancelled = false
        val repository = object : FakeVodRepository() {
            override fun searchUpdates(keyword: String, page: Int) = flow {
                emit(SearchUpdate.Discovered(listOf(target)))
                emit(SearchUpdate.Finished(target, SearchOutcome.SUCCESS, listOf(VodItem(keyword, "one", keyword))))
                if (keyword == "old") try { awaitCancellation() } finally { cancelled = true }
            }
        }
        val vm = SearchViewModel(repository)
        vm.search("old")
        runCurrent()
        assertEquals("old", vm.ui.value.posters.single().item.title)
        assertTrue(vm.ui.value.loading)
        vm.search("new")
        runCurrent()
        assertTrue(cancelled)
        assertEquals("new", vm.ui.value.posters.single().item.title)
        assertFalse(vm.ui.value.loading)
    }

    @Test fun partialFailureRetryKeepsPageAndDeduplicatesPerSource() = runTest {
        val pages = mutableListOf<Int>()
        var fail = true
        val other = SearchTarget("two", "Two")
        val repository = object : FakeVodRepository() {
            override fun searchUpdates(keyword: String, page: Int) = flow {
                pages += page
                emit(SearchUpdate.Discovered(listOf(target, other)))
                emit(SearchUpdate.Finished(target, SearchOutcome.SUCCESS, listOf(VodItem("same", "one", keyword))))
                emit(if (fail) SearchUpdate.Finished(other, SearchOutcome.FAILED)
                    else SearchUpdate.Finished(other, SearchOutcome.SUCCESS, listOf(VodItem("same", "two", keyword))))
            }
        }
        val vm = SearchViewModel(repository)
        vm.search("film")
        runCurrent()
        fail = false
        vm.retry()
        runCurrent()
        assertEquals(listOf(1, 1), pages)
        assertEquals(2, vm.ui.value.posters.size)
        assertFalse(vm.ui.value.failed)
        assertTrue(vm.ui.value.hasMore)
    }

    @Test fun emptyOrRepeatedUnknownPageStopsPagination() = runTest {
        for (repeat in listOf(false, true)) {
            val pages = mutableListOf<Int>()
            val repository = object : FakeVodRepository() {
                override fun searchUpdates(keyword: String, page: Int) = flow {
                    pages += page
                    emit(SearchUpdate.Finished(target, SearchOutcome.SUCCESS,
                        if (page == 1 || repeat) listOf(VodItem("one", "one", keyword)) else emptyList()))
                }
            }
            val vm = SearchViewModel(repository)
            vm.search("film")
            runCurrent()
            vm.more()
            vm.more()
            runCurrent()
            assertEquals(listOf(1, 2), pages)
            assertFalse(vm.ui.value.hasMore)
            assertEquals(1, vm.ui.value.posters.size)
        }
    }

    @Test fun searchCrossesEmptyPagesUntilResultsThenWaitsForMore() = runTest {
        val pages = mutableListOf<Int>()
        val repository = object : FakeVodRepository() {
            override fun searchUpdates(keyword: String, page: Int) = flow {
                pages += page
                emit(SearchUpdate.Finished(target, SearchOutcome.SUCCESS,
                    if (page >= 3) listOf(VodItem("result-$page", "one", keyword)) else emptyList(), hasMore = page < 4))
            }
        }
        val vm = SearchViewModel(repository)
        vm.search("film")
        runCurrent()
        assertEquals("result-3", vm.ui.value.posters.single().item.id)
        assertFalse(vm.ui.value.loading)
        assertTrue(vm.ui.value.hasMore)
        assertEquals(listOf(1, 2, 3), pages)
        vm.more()
        runCurrent()
        assertEquals(2, vm.ui.value.posters.size)
        assertFalse(vm.ui.value.hasMore)
        vm.more()
        runCurrent()
        assertEquals(listOf(1, 2, 3, 4), pages)
    }

    @Test fun emptySearchStopsAtDeclaredEndOrUnknownPagination() = runTest {
        for (declared in listOf(false, true)) {
            val pages = mutableListOf<Int>()
            val repository = object : FakeVodRepository() {
                override fun searchUpdates(keyword: String, page: Int) = flow {
                    pages += page
                    emit(SearchUpdate.Finished(target, SearchOutcome.SUCCESS,
                        hasMore = if (declared) page < 3 else null))
                }
            }
            val vm = SearchViewModel(repository)
            vm.search("film")
            runCurrent()
            assertEquals(if (declared) listOf(1, 2, 3) else listOf(1), pages)
            assertTrue(vm.ui.value.posters.isEmpty())
            assertFalse(vm.ui.value.loading)
            assertFalse(vm.ui.value.hasMore)
        }
    }

    @Test fun emptyPageContinuationStopsOnFailureAndRetriesThatPage() = runTest {
        val pages = mutableListOf<Int>()
        var fail = true
        val repository = object : FakeVodRepository() {
            override fun searchUpdates(keyword: String, page: Int) = flow {
                pages += page
                emit(when {
                    page == 1 -> SearchUpdate.Finished(target, SearchOutcome.SUCCESS, hasMore = true)
                    fail -> SearchUpdate.Finished(target, SearchOutcome.TIMED_OUT)
                    else -> SearchUpdate.Finished(target, SearchOutcome.SUCCESS,
                        listOf(VodItem("recovered", "one", keyword)), false)
                })
            }
        }
        val vm = SearchViewModel(repository)
        vm.search("film")
        runCurrent()
        assertEquals(listOf(1, 2), pages)
        assertTrue(vm.ui.value.failed)
        assertFalse(vm.ui.value.loading)
        assertEquals(1, vm.ui.value.page)
        vm.more()
        runCurrent()
        assertEquals(listOf(1, 2), pages)
        fail = false
        vm.retry()
        runCurrent()
        assertEquals(listOf(1, 2, 2), pages)
        assertEquals("recovered", vm.ui.value.posters.single().item.id)
        assertFalse(vm.ui.value.failed)
    }

    @Test fun newQueryCancelsEmptyPageContinuation() = runTest {
        val calls = mutableListOf<Pair<String, Int>>()
        var cancelled = false
        val repository = object : FakeVodRepository() {
            override fun searchUpdates(keyword: String, page: Int) = flow {
                calls += keyword to page
                if (keyword == "old") {
                    if (page == 2) try { awaitCancellation() } finally { cancelled = true }
                    emit(SearchUpdate.Finished(target, SearchOutcome.SUCCESS, hasMore = true))
                } else emit(SearchUpdate.Finished(target, SearchOutcome.SUCCESS,
                    listOf(VodItem("new", "one", keyword)), false))
            }
        }
        val vm = SearchViewModel(repository)
        vm.search("old")
        runCurrent()
        assertTrue(vm.ui.value.loading)
        vm.search("new")
        runCurrent()
        assertTrue(cancelled)
        assertEquals(listOf("old" to 1, "old" to 2, "new" to 1), calls)
        assertEquals("new", vm.ui.value.posters.single().item.id)
        assertFalse(vm.ui.value.loading)
    }

    @Test fun partialFailureMustRetryCurrentPageBeforeLoadingMore() = runTest {
        val pages = mutableListOf<Int>()
        val repository = object : FakeVodRepository() {
            override fun searchUpdates(keyword: String, page: Int) = flow {
                pages += page
                emit(SearchUpdate.Finished(target, SearchOutcome.SUCCESS, listOf(VodItem("one", "one", keyword))))
                emit(SearchUpdate.Finished(SearchTarget("two", "Two"), SearchOutcome.TIMED_OUT))
            }
        }
        val vm = SearchViewModel(repository)
        vm.search("film")
        runCurrent()
        assertTrue(vm.ui.value.failed)
        assertTrue(vm.ui.value.posters.isNotEmpty())
        vm.more()
        runCurrent()
        assertEquals(listOf(1), pages)
        vm.retry()
        runCurrent()
        assertEquals(listOf(1, 1), pages)
    }
}
