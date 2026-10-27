package com.flytech.juying.feature.player

import android.os.Looper
import android.view.SurfaceView
import androidx.lifecycle.ViewModelStore
import com.flytech.juying.core.data.BrowseRepository
import com.flytech.juying.core.data.HistoryRepository
import com.flytech.juying.core.data.LiveRepository
import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.datastore.SettingsDataSource
import com.flytech.juying.core.domain.GetPlayItemUseCase
import com.flytech.juying.core.domain.ZapChannelUseCase
import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.FileEntry
import com.flytech.juying.core.model.HistoryEntry
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayLine
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.PlaybackRoute
import com.flytech.juying.core.model.Episode
import com.flytech.juying.core.model.PlayGroup
import com.flytech.juying.core.model.VodDetail
import com.flytech.juying.core.model.VodItem
import com.flytech.juying.core.testing.MainDispatcherRule
import com.flytech.juying.player.api.PlaybackManager
import com.flytech.juying.player.api.PlayerEngine
import com.flytech.juying.player.api.PlayerState
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.advanceUntilIdle
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import kotlin.concurrent.thread
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class PlayerViewModelTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private val engine = FakePlayerEngine()
    private val live = ControlledLiveRepository()
    private val vod = ControlledVodRepository()
    private val history = RecordingHistoryRepository()
    private val store = ViewModelStore()
    private lateinit var vm: PlayerViewModel

    @Before
    fun setUp() {
        val playback = PlaybackManager({ engine }, SettingsDataSource(RuntimeEnvironment.getApplication()))
        // Resolve the real settings store before testing main-thread request ordering.
        runBlocking { playback.acquire() }
        vm = PlayerViewModel(GetPlayItemUseCase(live, vod, unusedBrowse, history), ZapChannelUseCase(live), history, playback, vod)
        store.put("player", vm)
    }

    @After
    fun tearDown() = store.clear()

    @Test
    fun `late cancelled resolution cannot prepare over a newer request`() = runTest {
        lateinit var oldResult: Continuation<PlayItem>
        live.resolveItem = { channel ->
            if (channel.id == "old") suspendCoroutine { oldResult = it } else item(channel.id)
        }

        vm.start(request("old"))
        vm.start(request("new"))
        oldResult.resume(item("old"))

        assertEquals(listOf("new"), engine.prepared.map { it.id })
        assertEquals("new", vm.ui.value.title)
        assertEquals(listOf("source:new"), history.entries.map { it.id })
    }

    @Test
    fun `late cancelled resolution failure cannot overwrite newer state`() = runTest {
        lateinit var oldResult: Continuation<PlayItem>
        live.resolveItem = { channel ->
            if (channel.id == "old") suspendCoroutine { oldResult = it } else item(channel.id)
        }

        vm.start(request("old"))
        vm.start(request("new"))
        oldResult.resumeWithException(IllegalStateException("old failure"))

        assertEquals("new", vm.ui.value.title)
        assertNull(vm.ui.value.error)
        assertEquals(listOf("new"), engine.prepared.map { it.id })
    }

    @Test
    fun `pending channel zap cannot replace an explicit newer request`() = runTest {
        val groupsReady = CompletableDeferred<Unit>()
        live.groups = flow {
            groupsReady.await()
            emit(listOf(ChannelGroup("test", listOf(Channel("old", "old"), Channel("next", "next")))))
        }

        vm.start(request("old"))
        vm.zap(1)
        vm.start(request("new"))
        groupsReady.complete(Unit)

        assertEquals(listOf("old", "new"), engine.prepared.map { it.id })
        assertEquals("new", vm.ui.value.title)
    }

    @Test
    fun `pause during a new resolution does not save the old item under the new request`() = runTest {
        val newItem = CompletableDeferred<PlayItem>()
        live.resolveItem = { channel -> if (channel.id == "new") newItem.await() else item(channel.id) }
        vm.start(request("old"))

        vm.start(request("new"))
        vm.pause()

        assertEquals(listOf("source:old", "source:old"), history.entries.map { it.id })
        newItem.complete(item("new"))
        assertEquals("new", vm.ui.value.title)
    }

    @Test
    fun `old engine error does not consume the new requests backup line`() = runTest {
        val backup = PlayLine("https://example.test/new-backup", "backup", mapOf("Referer" to "new"))
        live.resolveItem = { channel -> item(channel.id).copy(backupLines = if (channel.id == "new") listOf(backup) else emptyList()) }
        vm.start(request("old"))
        engine.state.value = PlayerState(error = "old failure")

        vm.start(request("new"))

        assertEquals(listOf("old", "new"), engine.prepared.map { it.id })
        engine.state.value = PlayerState(error = "new failure")
        assertEquals(backup.url, engine.prepared.last().url)
        assertEquals(backup.headers, engine.prepared.last().headers)
        assertEquals(3, engine.prepared.size)
    }

    @Test
    fun `official web route releases native decoder and ignores its late state`() = runTest {
        live.resolveItem = { channel -> item(channel.id).copy(
            route = if (channel.id == "web") PlaybackRoute.WEB else PlaybackRoute.NATIVE) }
        vm.start(request("native"))
        vm.start(request("web"))
        assertEquals(1, engine.releaseCount)
        assertEquals(listOf("native"), engine.prepared.map { it.id })
        assertEquals("web", vm.ui.value.webPage?.id)
        engine.state.value = PlayerState(error = "late native failure")
        assertNull(vm.ui.value.error)
        vm.start(request("new-native"))
        vm.ui.first { it.title == "new-native" && it.playback.isBuffering }
        assertNull(vm.ui.value.webPage)
        assertEquals(listOf("native", "new-native"), engine.prepared.map { it.id })
    }

    @Test
    fun `vod web route fails without opening a web player or writing history`() = runTest {
        vod.resolveItem = { PlayItem(it, it, "https://example.test/$it", route = PlaybackRoute.WEB) }

        vm.start(PlayRequest(PlayKind.VOD, "source", "web", "Web episode"))

        assertNull(vm.ui.value.webPage)
        assertEquals("该点播暂无可用的原生播放地址，请尝试其他线路或片源", vm.ui.value.error)
        assertEquals(vm.ui.value.error, vm.ui.value.resolutionError)
        assertEquals(false, vm.ui.value.loading)
        assertEquals(emptyList<PlayItem>(), engine.prepared)
        assertEquals(emptyList<PlayLine>(), vm.availableLines())
        assertEquals(emptyList<HistoryEntry>(), history.entries)
        assertEquals(0, engine.releaseCount)
    }

    @Test
    fun `rejected vod web switch preserves current playback lines and history`() = runTest {
        val backup = PlayLine("https://example.test/native-backup", "backup")
        vod.resolveItem = { id -> PlayItem(id, id, "https://example.test/$id",
            route = if (id == "web") PlaybackRoute.WEB else PlaybackRoute.NATIVE,
            backupLines = if (id == "native") listOf(backup) else emptyList()) }
        vm.start(PlayRequest(PlayKind.VOD, "source", "native", "Native episode"))
        val originalLines = vm.availableLines()
        val originalHistory = history.entries.toList()

        vm.start(PlayRequest(PlayKind.VOD, "source", "web", "Web episode"))

        assertNull(vm.ui.value.webPage)
        assertNull(vm.ui.value.error)
        assertEquals(true, vm.ui.value.switchError)
        assertEquals("该点播暂无可用的原生播放地址，请尝试其他线路或片源", vm.ui.value.resolutionError)
        assertEquals("native", vm.currentRequest?.ref)
        assertEquals("native", vm.ui.value.title)
        assertEquals(originalLines, vm.availableLines())
        assertEquals(originalHistory, history.entries)
        assertEquals(listOf("native"), engine.prepared.map { it.id })
        assertEquals(0, engine.releaseCount)
        engine.state.value = PlayerState(error = "native primary failed")
        assertEquals(backup.url, engine.prepared.last().url)
        vm.cancelSwitch()
        assertNull(vm.ui.value.resolutionError)
        vm.pause()
        assertEquals(setOf("source:native"), history.entries.map { it.id }.toSet())
    }

    @Test
    fun `rejected vod web switch keeps the current episode lookup active`() = runTest {
        val detail = CompletableDeferred<VodDetail>()
        val episodes = listOf(Episode("Episode 1", "native"), Episode("Episode 2", "next"))
        vod.resolveDetail = { detail.await() }
        vod.resolveItem = { PlayItem(it, it, "https://example.test/$it",
            route = if (it == "web") PlaybackRoute.WEB else PlaybackRoute.NATIVE) }
        vm.start(PlayRequest(PlayKind.VOD, "source", "native", extra = mapOf("itemId" to "album")))

        vm.start(PlayRequest(PlayKind.VOD, "source", "web"))
        detail.complete(VodDetail(VodItem("album", "source", "Series"), playGroups = listOf(PlayGroup("Native", episodes))))
        advanceUntilIdle()

        assertEquals("native", vm.currentRequest?.ref)
        assertEquals(episodes, vm.ui.value.episodes)
        assertEquals(1, vod.detailCalls)
    }

    @Test
    @LooperMode(LooperMode.Mode.PAUSED)
    fun `asynchronous resolution on Main immediate does not replay the previous error`() {
        // Resume through Android's Handler, where Main.immediate can start a child inline.
        Dispatchers.resetMain()
        val backup = PlayLine("https://example.test/new-backup", "backup")
        lateinit var newResult: Continuation<PlayItem>
        live.resolveItem = { channel ->
            if (channel.id == "new") suspendCoroutine { newResult = it } else item(channel.id)
        }
        vm.start(request("old"))
        engine.state.value = PlayerState(error = "old failure")
        vm.start(request("new"))

        thread { newResult.resume(item("new").copy(backupLines = listOf(backup))) }.join()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(listOf("https://example.test/old", "https://example.test/new"), engine.prepared.map { it.url })
        engine.state.value = PlayerState(error = "new failure")
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(backup.url, engine.prepared.last().url)
        assertEquals(3, engine.prepared.size)
    }

    @Test
    fun `pending switch keeps current programme and decoder until resolution succeeds`() = runTest {
        val target = CompletableDeferred<PlayItem>()
        live.resolveItem = { if (it.id == "target") target.await() else item(it.id) }
        vm.start(request("old"))
        vm.start(request("target"))
        assertEquals("old", vm.ui.value.title)
        assertEquals(listOf("old"), engine.prepared.map { it.id })
        target.complete(item("target"))
        assertEquals("target", vm.ui.value.title)
        assertEquals(listOf("old", "target"), engine.prepared.map { it.id })
    }

    @Test
    fun `failed target resolution preserves current programme`() = runTest {
        live.resolveItem = { if (it.id == "broken") error("unavailable") else item(it.id) }
        vm.start(request("old"))
        vm.start(request("broken"))
        assertEquals("old", vm.ui.value.title)
        assertNull(vm.ui.value.error)
        assertNull(vm.ui.value.resolutionError)
        assertEquals(listOf("old"), engine.prepared.map { it.id })
    }

    @Test
    fun `cancelled switch ignores late target and keeps original progress owner`() = runTest {
        lateinit var target: Continuation<PlayItem>
        live.resolveItem = { if (it.id == "target") suspendCoroutine { continuation -> target = continuation } else item(it.id) }
        vm.start(request("old"))
        vm.start(request("target"))
        vm.cancelSwitch()
        target.resume(item("target"))
        vm.pause()
        assertNull(vm.ui.value.pendingTitle)
        assertEquals("old", vm.currentRequest?.ref)
        assertEquals(listOf("old"), engine.prepared.map { it.id })
        assertEquals(setOf("source:old"), history.entries.map { it.id }.toSet())
    }

    @Test
    fun `failed committed stream can return to previous programme`() = runTest {
        vm.start(request("old"))
        vm.start(request("new"))
        engine.state.value = PlayerState(error = "stream failed")
        assertEquals(true, vm.ui.value.canReturn)
        vm.returnPrevious()
        assertEquals(listOf("old", "new", "old"), engine.prepared.map { it.id })
        assertEquals("old", vm.currentRequest?.ref)
        assertNull(vm.ui.value.error)
    }

    @Test
    fun `background resolution stays paused and resumes only when requested`() = runTest {
        val result = CompletableDeferred<PlayItem>()
        live.resolveItem = { result.await() }
        vm.start(request("late"))
        vm.onBackground()
        result.complete(item("late"))
        assertEquals(0, engine.playCount)
        vm.onForeground()
        assertEquals(1, engine.playCount)
        vm.togglePlay()
        vm.onBackground()
        vm.onForeground()
        assertEquals(1, engine.playCount)
        vm.onBackground()
    }

    @Test
    fun `exit captures progress and content context before engine release`() = runTest {
        vm.start(request("episode").copy(extra = mapOf("itemId" to "album", "mediaTitle" to "Series", "Cookie" to "secret")))
        engine.position = 42_000
        val write = CompletableDeferred<Unit>()
        history.writeGate = write
        vm.onBackground()
        engine.position = 0
        store.clear()
        write.complete(Unit)
        advanceUntilIdle()
        assertEquals(42_000L, history.entries.last().positionMs)
        assertEquals("Series", history.entries.last().title)
        assertEquals(mapOf("itemId" to "album", "mediaTitle" to "Series"), history.entries.last().extra)
        assertEquals(1, engine.releaseCount)
    }

    @Test
    fun `episode navigation stays on the selected line and stops at both ends`() = runTest {
        val episodes = (1..3).map { Episode("Episode $it", "line-b-$it") }
        vod.result = VodDetail(VodItem("album", "source", "Series"), playGroups = listOf(
            PlayGroup("Other line", listOf(Episode("Episode 1", "line-a-1"))), PlayGroup("Selected", episodes)))
        vm.start(PlayRequest(PlayKind.VOD, "source", "line-b-1", "Episode 1", mapOf("itemId" to "album", "mediaTitle" to "Series")))
        assertEquals(episodes, vm.ui.value.episodes)
        vm.changeEpisode(-1)
        assertEquals("line-b-1", vm.currentRequest!!.ref)
        vm.changeEpisode(1)
        assertEquals("line-b-2", vm.currentRequest!!.ref)
        assertEquals("Episode 2", vm.currentRequest!!.extra["episodeTitle"])
        vm.changeEpisode(1)
        vm.changeEpisode(1)
        assertEquals("line-b-3", vm.currentRequest!!.ref)
        vm.changeEpisode(-1)
        assertEquals("line-b-2", vm.currentRequest!!.ref)
        assertEquals(1, vod.detailCalls)
    }

    @Test
    fun `legacy episode history resumes in its original group and next uses canonical ref`() = runTest {
        val episodes = listOf(Episode("Episode 1", "native-1", listOf("legacy-1")), Episode("Episode 2", "native-2"))
        vod.result = VodDetail(VodItem("album", "source", "Series"), playGroups = listOf(
            PlayGroup("Other site", listOf(Episode("Episode 1", "other-1"))), PlayGroup("Native", episodes)))
        history.restored = HistoryEntry("source:legacy-1", PlayKind.VOD, "source", "legacy-1", "Series",
            42_000, 300_000, 0)

        vm.start(PlayRequest(PlayKind.VOD, "source", "legacy-1", "Episode 1", mapOf("itemId" to "album")))

        assertEquals(42_000L, engine.prepared.single().startPositionMs)
        assertEquals("legacy-1", vm.currentRequest?.ref)
        assertEquals(episodes, vm.ui.value.episodes)
        vm.refreshEpisodes()
        assertEquals(1, vod.detailCalls)
        vm.changeEpisode(1)
        assertEquals("native-2", vm.currentRequest?.ref)
        assertEquals(listOf("legacy-1", "native-2"), engine.prepared.map { it.id })
        assertEquals("source:legacy-1", history.entries.first().id)
    }

    @Test
    fun `late episode list cannot replace a newer source`() = runTest {
        val delayed = CompletableDeferred<VodDetail>()
        vod.resolveDetail = { id -> if (id == "old") kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) { delayed.await() } else vod.result }
        vm.start(PlayRequest(PlayKind.VOD, "source", "old-1", extra = mapOf("itemId" to "old")))
        vod.result = VodDetail(VodItem("new", "source", "New"), playGroups = listOf(PlayGroup("New", listOf(Episode("New", "new-1")))))
        vm.start(PlayRequest(PlayKind.VOD, "source", "new-1", extra = mapOf("itemId" to "new")))
        delayed.complete(VodDetail(VodItem("old", "source", "Old"), playGroups = listOf(PlayGroup("Old", listOf(Episode("Old", "old-1"))))))
        advanceUntilIdle()
        assertEquals(listOf(Episode("New", "new-1")), vm.ui.value.episodes)
    }

    private class ControlledVodRepository : VodRepository by unusedVod {
        var result = VodDetail(VodItem("album", "source", "Series"))
        var detailCalls = 0
        var resolveDetail: suspend (String) -> VodDetail = { result }
        var resolveItem: suspend (String) -> PlayItem = { PlayItem(it, it, "https://example.test/$it") }
        override suspend fun detail(sourceId: String, itemId: String): VodDetail { detailCalls++; return resolveDetail(itemId) }
        override suspend fun resolve(sourceId: String, episodeRef: String) = resolveItem(episodeRef)
    }

    private class ControlledLiveRepository : LiveRepository {
        var groups: Flow<List<ChannelGroup>> = flowOf(emptyList())
        var resolveItem: suspend (Channel) -> PlayItem = { item(it.id) }
        override fun channelGroups(sourceId: String) = groups
        override suspend fun findChannel(sourceId: String, channelId: String) = Channel(channelId, channelId)
        override suspend fun resolve(sourceId: String, channel: Channel) = resolveItem(channel)
    }

    private class RecordingHistoryRepository : HistoryRepository {
        val entries = mutableListOf<HistoryEntry>()
        var restored: HistoryEntry? = null
        var writeGate: CompletableDeferred<Unit>? = null
        override fun observeRecent(limit: Int) = flowOf(entries.toList())
        override suspend fun get(id: String): HistoryEntry? = restored?.takeIf { it.id == id }
        override suspend fun record(entry: HistoryEntry) { writeGate?.await(); entries += entry }
        override suspend fun delete(id: String) = Unit
        override suspend fun clear() = Unit
    }

    private class FakePlayerEngine : PlayerEngine {
        override val state = MutableStateFlow(PlayerState())
        val prepared = mutableListOf<PlayItem>()
        var releaseCount = 0
        var playCount = 0
        var position = 0L
        override fun setSurfaceView(view: SurfaceView?) = Unit
        override fun prepare(item: PlayItem) {
            // Media3Engine synchronously clears the previous error at prepare entry.
            state.value = PlayerState(isBuffering = true)
            prepared += item
        }
        override fun play() { playCount++ }
        override fun pause() = Unit
        override fun seekTo(positionMs: Long) = Unit
        override fun seekBy(deltaMs: Long) = Unit
        override fun positionMs() = position
        override fun durationMs() = 0L
        override fun release() { releaseCount++ }
    }

    private companion object {
        fun request(id: String) = PlayRequest(PlayKind.LIVE, "source", id, id)
        fun item(id: String) = PlayItem(id, id, "https://example.test/$id", isLive = true)

        val unusedVod = object : VodRepository {
            override suspend fun subSources(sourceId: String) = error("not used")
            override suspend fun categories(sourceId: String) = error("not used")
            override suspend fun list(sourceId: String, categoryId: String, page: Int) = error("not used")
            override suspend fun detail(sourceId: String, itemId: String) = error("not used")
            override suspend fun search(sourceId: String, keyword: String, page: Int) = error("not used")
            override suspend fun searchAll(keyword: String, page: Int) = error("not used")
            override fun searchUpdates(keyword: String, page: Int): kotlinx.coroutines.flow.Flow<com.flytech.juying.core.model.SearchUpdate> = error("not used")
            override suspend fun resolve(sourceId: String, episodeRef: String) = error("not used")
        }
        val unusedBrowse = object : BrowseRepository {
            override suspend fun list(sourceId: String, path: String) = error("not used")
            override suspend fun playItem(sourceId: String, entry: FileEntry) = error("not used")
        }
    }
}
