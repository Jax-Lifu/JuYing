package com.flytech.juying.core.data

import com.flytech.juying.core.model.*
import com.flytech.juying.source.api.VodSource
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DefaultVodRepositoryTest {
    private val config = SourceConfig("repo", "订阅", SourceType.TVBOX, "https://config.test")
    private val sources = object : SourceRepository {
        override fun observeSources(capability: SourceCapability?) = flowOf(listOf(config))
        override suspend fun get(id: String) = config.takeIf { it.id == id }
        override suspend fun upsert(config: SourceConfig) = error("not used")
        override suspend fun delete(id: String) = error("not used")
    }

    private fun repository(provider: VodSource) = DefaultVodRepository(SourceRegistry(setOf(provider)), sources,
        DeviceProfile(DeviceForm.TV, PerformanceTier.LOW, 2048))

    @Test fun fastSiteIsReturnedBeforeSlowSiteAndFailureDoesNotEraseIt() = runTest {
        val provider = TestVod(listOf("slow", "fast", "failed", "disabled")) { site, _, _ ->
            when (site) {
                "slow" -> delay(5_000)
                "failed" -> error("upstream unavailable")
            }
            listOf(VodItem(site, config.id, site))
        }
        val updates = mutableListOf<SearchUpdate>()
        val job = launch { repository(provider).searchUpdates("标题").toList(updates) }
        runCurrent()
        assertEquals(listOf("fast", "failed"), updates.filterIsInstance<SearchUpdate.Finished>().map { it.target.subSource!!.id })
        assertEquals(SearchOutcome.FAILED, updates.filterIsInstance<SearchUpdate.Finished>().last().outcome)
        advanceTimeBy(5_000); runCurrent(); job.join()
        assertEquals(listOf("fast", "slow"), updates.filterIsInstance<SearchUpdate.Finished>().flatMap { it.items }.map { it.id })
        assertEquals(3, (updates.first() as SearchUpdate.Discovered).targets.size)
    }

    @Test fun lowTierBoundsActiveRequestsAndCancellationReachesEveryActiveSite() = runTest {
        var active = 0
        var peak = 0
        val provider = TestVod((1..10).map { it.toString() }) { _, _, _ ->
            active++; peak = maxOf(peak, active)
            try { awaitCancellation() } finally { active-- }
        }
        val job = launch { repository(provider).searchUpdates("标题").toList() }
        runCurrent()
        assertEquals(2, peak)
        job.cancelAndJoin()
        assertEquals(0, active)
    }

    @Test fun timeoutIsVisibleAndRequestedPageReachesSubsite() = runTest {
        var receivedPage = 0
        val provider = TestVod(listOf("timeout")) { _, keyword, page ->
            assertEquals("标题", keyword); receivedPage = page
            awaitCancellation()
        }
        val result = repository(provider).searchUpdates(" 标题 ", 3).toList().filterIsInstance<SearchUpdate.Finished>().single()
        assertEquals(3, receivedPage)
        assertEquals(SearchOutcome.TIMED_OUT, result.outcome)
    }

    @Test fun emptySearchPageKeepsProviderContinuationFlag() = runTest {
        val provider = object : TestVod(listOf("site"), { _, _, _ -> emptyList() }) {
            override suspend fun searchPage(config: SourceConfig, keyword: String, page: Int, subSourceId: String?): VodPage {
                assertEquals("site", subSourceId)
                assertEquals(2, page)
                return VodPage(emptyList(), true)
            }
        }
        val result = repository(provider).searchUpdates("标题", 2).toList().filterIsInstance<SearchUpdate.Finished>().single()
        assertEquals(SearchOutcome.SUCCESS, result.outcome)
        assertTrue(result.items.isEmpty())
        assertEquals(true, result.hasMore)
    }

    @Test fun scriptExecutionBudgetStartsAfterPlaybackAndEarlierSearchReleaseTheSlot() = runTest {
        val gate = Mutex()
        val playback = launch { gate.withLock { delay(20_000) } }
        runCurrent()
        val provider = object : TestVod(listOf("first", "second"), { site, _, _ ->
            delay(18_000)
            listOf(VodItem(site, config.id, site))
        }) {
            override suspend fun searchPageWithTimeout(config: SourceConfig, keyword: String, page: Int, subSourceId: String?, timeoutMillis: Long): VodPage? =
                gate.withLock { super.searchPageWithTimeout(config, keyword, page, subSourceId, timeoutMillis) }
        }
        val updates = repository(provider).searchUpdates("标题").toList().filterIsInstance<SearchUpdate.Finished>()
        playback.join()
        assertEquals(listOf(SearchOutcome.SUCCESS, SearchOutcome.SUCCESS), updates.map { it.outcome })
        assertEquals(listOf("first", "second"), updates.flatMap { it.items }.map { it.id })
        assertEquals(56_000L, testScheduler.currentTime)
    }

    @Test fun cancellingSearchWhileWaitingForScriptSlotDoesNotRunItOrCancelPlayback() = runTest {
        val gate = Mutex()
        var calls = 0
        val playback = launch { gate.withLock { awaitCancellation() } }
        runCurrent()
        val provider = object : TestVod(listOf("waiting"), { _, _, _ ->
            calls++
            emptyList()
        }) {
            override suspend fun searchPageWithTimeout(config: SourceConfig, keyword: String, page: Int, subSourceId: String?, timeoutMillis: Long): VodPage? =
                gate.withLock { super.searchPageWithTimeout(config, keyword, page, subSourceId, timeoutMillis) }
        }
        val search = launch { repository(provider).searchUpdates("标题").toList() }
        runCurrent()
        advanceTimeBy(35_000); runCurrent()
        assertTrue(search.isActive)
        search.cancelAndJoin()
        assertEquals(0, calls)
        assertTrue(playback.isActive)
        playback.cancelAndJoin()
    }

    private open class TestVod(
        private val sites: List<String>,
        private val result: suspend (String, String, Int) -> List<VodItem>,
    ) : VodSource {
        override val type = SourceType.TVBOX
        override suspend fun subSources(config: SourceConfig) = sites.map { SubSource(it, it, it != "disabled") }
        override suspend fun search(config: SourceConfig, keyword: String, page: Int, subSourceId: String?) = result(requireNotNull(subSourceId), keyword, page)
        override suspend fun search(config: SourceConfig, keyword: String, page: Int) = error("must route subsite")
        override suspend fun categories(config: SourceConfig): List<VodCategory> = error("not used")
        override suspend fun list(config: SourceConfig, categoryId: String, page: Int): List<VodItem> = error("not used")
        override suspend fun detail(config: SourceConfig, itemId: String): VodDetail = error("not used")
        override suspend fun resolve(config: SourceConfig, episodeRef: String): PlayItem = error("not used")
    }
}
