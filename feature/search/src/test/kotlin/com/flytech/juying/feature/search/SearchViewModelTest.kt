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
    }
}
