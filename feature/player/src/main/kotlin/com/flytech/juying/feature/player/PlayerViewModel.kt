package com.flytech.juying.feature.player

import android.view.SurfaceView
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.HistoryRepository
import com.flytech.juying.core.data.BrowseRepository
import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.model.Episode
import com.flytech.juying.core.domain.GetPlayItemUseCase
import com.flytech.juying.core.domain.ZapChannelUseCase
import com.flytech.juying.core.model.HistoryEntry
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayLine
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.PlaybackRoute
import com.flytech.juying.player.api.PlaybackManager
import com.flytech.juying.player.api.PlayerEngine
import com.flytech.juying.player.api.PlayerState
import com.flytech.juying.player.api.PlayerTrackType
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/** 全屏播放器 UI 状态实体。 */
data class PlayerUiState(
    val title: String = "",
    val isLive: Boolean = false,
    val loading: Boolean = true,
    val playback: PlayerState = PlayerState(),
    val error: String? = null,
    val webPage: PlayItem? = null,
    val pendingTitle: String? = null,
    val switchError: Boolean = false,
    /** 仅保存受控的解析提示；底层异常仍由界面显示通用错误，避免泄露地址和凭据。 */
    val resolutionError: String? = null,
    val canReturn: Boolean = false,
    val episodes: List<Episode> = emptyList(),
    val episodeError: Boolean = false,
)

/**
 * 全屏播放器业务逻辑 ViewModel。
 *
 * **What**: 管理播放状态机、连续切台请求合并与旧解析隔离、多线路自动故障转移、分集切换及断点续播进度保存。
 *
 * **Why**: 深度隔离播放内核生命周期与 UI 视图；在低配 TV 盒子上，当遥控器连按快速换台时，
 * 累计正反偏移并即时取消未完成的旧网络/签名请求，确保仅最后一次目标生效，防止界面闪烁或音频串流。
 */
@HiltViewModel
class PlayerViewModel @Inject constructor(
    private val getPlayItem: GetPlayItemUseCase,
    private val zapChannel: ZapChannelUseCase,
    private val history: HistoryRepository,
    private val playback: PlaybackManager,
    private val vod: VodRepository,
    private val browse: BrowseRepository? = null,
) : ViewModel() {

    private val _ui = MutableStateFlow(PlayerUiState())
    val ui: StateFlow<PlayerUiState> = _ui.asStateFlow()

    private var request: PlayRequest? = null
    private var pending: PlayRequest? = null
    private var previous: PlayRequest? = null
    private var lines: List<PlayLine> = emptyList()
    val currentRequest: PlayRequest? get() = request ?: pending
    fun availableLines(): List<PlayLine> = lines
    private var currentItem: PlayItem? = null
    private var remainingBackupLines: ArrayDeque<PlayLine> = ArrayDeque()
    private var engine: PlayerEngine? = null
    private var surface: SurfaceView? = null
    private var subtitleContainer: android.view.ViewGroup? = null
    private var loadJob: Job? = null
    private var forwardJob: Job? = null
    private var zapJob: Job? = null
    // 列表查询未返回时合并方向键；pending 保留本轮基点，不排队创建播放器。
    private var zapDelta = 0
    private var checkpointJob: Job? = null
    private var episodeJob: Job? = null
    private var episodeKey: Pair<String, String>? = null
    private var cachedEpisodes = emptyList<Episode>()
    private var foreground = true
    private var playWhenForeground = true
    private val historyWrites = Mutex()

    fun start(req: PlayRequest) {
        zapJob?.cancel()
        zapDelta = 0
        if (request == req && currentItem != null && _ui.value.error == null) {
            cancelSwitch()
            return
        }
        load(req)
    }

    private fun load(req: PlayRequest) {
        loadJob?.cancel()
        pending = req
        _ui.value = if (currentItem == null) PlayerUiState(title = req.title, isLive = req.kind == PlayKind.LIVE, loading = true)
            else _ui.value.copy(pendingTitle = req.title, switchError = false, resolutionError = null)
        loadJob = viewModelScope.launch {
            try {
                val item = getPlayItem(req)
                // 部分源的回调不响应取消，提交解析结果前必须再次确认任务仍有效。
                ensureActive()
                if (req.kind == PlayKind.VOD && item.route == PlaybackRoute.WEB) throw NativeVodUnavailable()
                val oldRequest = request
                val oldItem = currentItem
                if (oldRequest != null && oldItem != null) saveHistory(oldRequest, oldItem)
                ensureActive()
                episodeJob?.cancel()
                if (oldRequest != req && oldItem != null) previous = oldRequest
                request = req
                playWhenForeground = true
                pending = null
                forwardJob?.cancel()
                lines = listOf(PlayLine(item.url, headers = item.headers)) + item.backupLines
                if (item.route == PlaybackRoute.WEB) {
                    engine?.let(playback::release)
                    engine = null
                    currentItem = item
                    remainingBackupLines.clear()
                    _ui.value = PlayerUiState(title = item.title.ifEmpty { req.title }, isLive = item.isLive,
                        loading = false, webPage = item, canReturn = previous != null)
                    refreshEpisodes()
                    saveHistory(req, item)
                    return@launch
                }
                val e = playback.acquire()
                ensureActive()
                currentItem = item
                remainingBackupLines = ArrayDeque(item.backupLines)
                engine = e
                e.setSurfaceView(surface)
                e.setSubtitleContainer(subtitleContainer)
                forwardJob?.cancel()
                _ui.value = PlayerUiState(title = item.title.ifEmpty { req.title }, isLive = item.isLive, canReturn = previous != null)
                refreshEpisodes()
                // 先清除旧引擎状态，避免 Main.immediate 同步重放旧错误并消耗新请求的备用线路。
                e.prepare(item)
                if (foreground) e.play() else e.pause()
                // 新请求解析失败或取消时，当前节目的状态与备用线路仍须继续工作。
                forwardJob = viewModelScope.launch {
                    e.state.collect { s ->
                        if (s.error != null && remainingBackupLines.isNotEmpty()) {
                            val nextLine = remainingBackupLines.removeFirst()
                            Timber.w("Primary line failed (%s), switching to backup line: %s", s.error, nextLine.label)
                            val nextItem = (currentItem ?: item).copy(
                                url = nextLine.url,
                                headers = nextLine.headers,
                                startPositionMs = e.positionMs().coerceAtLeast(0L),
                            )
                            currentItem = nextItem
                            e.prepare(nextItem)
                        } else {
                            _ui.value = _ui.value.copy(playback = s, loading = s.isBuffering, error = s.error)
                            if (s.ended && !_ui.value.isLive) {
                                val currentReq = request
                                val episodeRef = currentReq?.ref
                                val currentIndex = _ui.value.episodes.indexOfFirst {
                                    episodeRef != null && (it.ref == episodeRef || episodeRef in it.legacyRefs)
                                }
                                if (currentIndex in 0 until _ui.value.episodes.lastIndex) {
                                    Timber.i("Playback ended, auto-advancing to next episode: %d -> %d", currentIndex, currentIndex + 1)
                                    selectEpisode(currentIndex + 1)
                                }
                            }
                        }
                    }
                }
                saveHistory(req, item)
            } catch (t: Throwable) {
                if (t is CancellationException) throw t
                ensureActive()
                Timber.w("Playback resolution failed: %s", t.javaClass.simpleName)
                val resolutionError = (t as? NativeVodUnavailable)?.message
                if (currentItem != null && pending != null) _ui.value = _ui.value.copy(switchError = true, resolutionError = resolutionError)
                else _ui.value = _ui.value.copy(loading = false, error = t.message ?: "无法播放", resolutionError = resolutionError)
            }
        }
    }

    /** Cancel only the unresolved target; the original decoder and its callbacks stay active. */
    fun cancelSwitch() {
        loadJob?.cancel(); zapJob?.cancel(); pending = null
        zapDelta = 0
        _ui.value = _ui.value.copy(pendingTitle = null, switchError = false, resolutionError = null)
    }
    fun retry() {
        if (zapDelta != 0) zap(0) else (pending ?: request)?.let(::start)
    }
    fun returnPrevious() { previous?.let(::start) }
    fun selectLine(index: Int) {
        val line = lines.getOrNull(index) ?: return
        val item = currentItem ?: return
        val e = engine ?: return
        currentItem = item.copy(url = line.url, headers = line.headers, startPositionMs = e.positionMs().coerceAtLeast(0L))
        remainingBackupLines = ArrayDeque(lines.drop(index + 1))
        e.prepare(checkNotNull(currentItem))
        if (foreground && playWhenForeground) e.play() else e.pause()
    }
    fun tracks(type: PlayerTrackType) = engine?.tracks(type).orEmpty()
    fun selectTrack(type: PlayerTrackType, id: String?) = engine?.selectTrack(type, id)
    fun playbackSpeed() = engine?.playbackSpeed() ?: 1f
    fun setPlaybackSpeed(speed: Float) = engine?.setPlaybackSpeed(speed)
    fun seekTo(positionMs: Long) = engine?.seekTo(positionMs.coerceIn(0, durationMs().coerceAtLeast(0L)))

    fun refreshEpisodes() {
        val req = request ?: return
        when (req.kind) {
            PlayKind.VOD -> {
                val itemId = req.extra["itemId"]?.takeIf { it.isNotBlank() } ?: return
                val key = req.sourceId to itemId
                if (episodeKey == key && cachedEpisodes.any { it.ref == req.ref || req.ref in it.legacyRefs }) {
                    _ui.value = _ui.value.copy(episodes = cachedEpisodes)
                    return
                }
                episodeJob?.cancel()
                episodeJob = viewModelScope.launch {
                    try {
                        val detail = vod.detail(req.sourceId, itemId)
                        ensureActive()
                        if (request != req) return@launch
                        cachedEpisodes = detail.playGroups.firstOrNull { group ->
                            group.episodes.any { it.ref == req.ref || req.ref in it.legacyRefs }
                        }?.episodes.orEmpty()
                        episodeKey = key
                        _ui.value = _ui.value.copy(episodes = cachedEpisodes, episodeError = false)
                    } catch (e: CancellationException) { throw e }
                    catch (e: Exception) {
                        if (request == req) _ui.value = _ui.value.copy(episodeError = true)
                        Timber.w("Episode list failed: %s", e.javaClass.simpleName)
                    }
                }
            }
            PlayKind.FILE -> {
                val repo = browse ?: return
                val parentPath = req.ref.trim('/').substringBeforeLast('/', "")
                val key = req.sourceId to parentPath
                if (episodeKey == key && cachedEpisodes.any { it.ref == req.ref }) {
                    _ui.value = _ui.value.copy(episodes = cachedEpisodes)
                    return
                }
                episodeJob?.cancel()
                episodeJob = viewModelScope.launch {
                    try {
                        val files = repo.list(req.sourceId, parentPath)
                        ensureActive()
                        if (request != req) return@launch
                        val videoFiles = files.filter { it.isVideo }
                        cachedEpisodes = videoFiles.map { file ->
                            Episode(name = file.name, ref = file.path)
                        }
                        episodeKey = key
                        _ui.value = _ui.value.copy(episodes = cachedEpisodes, episodeError = false)
                    } catch (e: CancellationException) { throw e }
                    catch (e: Exception) {
                        if (request == req) _ui.value = _ui.value.copy(episodeError = true)
                        Timber.w("File episode list failed: %s", e.javaClass.simpleName)
                    }
                }
            }
            else -> return
        }
    }

    fun selectEpisode(index: Int) {
        if (pending != null) return
        val req = request ?: return
        val episode = _ui.value.episodes.getOrNull(index) ?: return
        start(req.copy(ref = episode.ref, title = episode.name, extra = req.extra + ("episodeTitle" to episode.name)))
    }

    fun changeEpisode(delta: Int) {
        val ref = request?.ref ?: return
        val index = _ui.value.episodes.indexOfFirst { it.ref == ref || ref in it.legacyRefs }
        if (index >= 0) selectEpisode(index + delta)
    }

    fun attachSurface(view: SurfaceView) {
        surface = view
        engine?.setSurfaceView(view)
    }

    fun attachSubtitles(container: android.view.ViewGroup) {
        subtitleContainer = container; engine?.setSubtitleContainer(container)
    }
    fun detachSurface() {
        engine?.setSubtitleContainer(null); subtitleContainer = null
        engine?.setSurfaceView(null)
        surface = null
    }

    fun togglePlay() {
        val e = engine ?: return
        playWhenForeground = !playWhenForeground
        if (playWhenForeground && foreground) e.play() else pause()
    }

    fun onForeground() {
        foreground = true
        if (playWhenForeground) engine?.play()
        checkpointJob?.cancel()
        checkpointJob = viewModelScope.launch {
            while (isActive) {
                delay(30_000)
                val req = request
                val item = currentItem
                if (req != null && item != null && !item.isLive && engine?.state?.value?.isPlaying == true) saveHistory(req, item)
            }
        }
    }

    fun onBackground() {
        foreground = false
        checkpointJob?.cancel()
        pause()
    }

    fun pause() {
        engine?.pause()
        val req = request
        val item = currentItem
        if (req != null && item != null) {
            // 退出时先捕获旧引擎的位置；仅这次短数据库写入允许跨越 ViewModel 销毁。
            val position = positionMs()
            val duration = durationMs()
            viewModelScope.launch(start = CoroutineStart.UNDISPATCHED) {
                withContext(NonCancellable) { saveHistory(req, item, position, duration) }
            }
        }
    }

    private suspend fun saveHistory(req: PlayRequest, item: PlayItem, position: Long = positionMs(), duration: Long = durationMs()) {
        try { historyWrites.withLock {
            val saved = history.get("${req.sourceId}:${req.ref}")
            history.record(
                HistoryEntry(
                    id = "${req.sourceId}:${req.ref}",
                    kind = req.kind,
                    sourceId = req.sourceId,
                    ref = req.ref,
                    title = req.extra["mediaTitle"] ?: item.title.ifEmpty { req.title },
                    positionMs = position.coerceAtLeast(0L),
                    durationMs = duration.coerceAtLeast(0L),
                    updatedAt = System.currentTimeMillis(),
                    cover = req.extra["cover"] ?: saved?.cover,
                    extra = saved?.extra.orEmpty() + req.extra.filterKeys { it in HISTORY_KEYS },
                ),
            )
        } } catch (error: Exception) {
            if (error is CancellationException) throw error
            Timber.w("Playback history save failed: %s", error.javaClass.simpleName)
        }
    }
    fun positionMs() = engine?.positionMs() ?: 0L
    fun durationMs() = engine?.durationMs() ?: 0L

    /** 直播换台：delta = +1 下一个 / -1 上一个。 */
    fun zap(delta: Int) {
        val req = pending ?: request ?: return
        if (req.kind != PlayKind.LIVE) return
        zapJob?.cancel()
        loadJob?.cancel()
        zapDelta += delta
        val offset = zapDelta
        if (offset == 0) {
            start(req)
            return
        }
        // 查询阶段尚不知道目标名称，也要允许返回键取消；首台没有可保留的播放，返回仍退出。
        _ui.value = if (currentItem == null) _ui.value.copy(loading = true, error = null)
            else _ui.value.copy(pendingTitle = "", switchError = false, resolutionError = null)
        zapJob = viewModelScope.launch {
            try {
                val next = zapChannel(req.sourceId, req.ref, offset)
                ensureActive()
                start(if (next == null) req else req.copy(ref = next.id, title = next.name))
            } catch (t: Throwable) {
                if (t is CancellationException) throw t
                ensureActive()
                Timber.w("Channel lookup failed: %s", t.javaClass.simpleName)
                _ui.value = if (currentItem == null) _ui.value.copy(loading = false, error = "无法播放")
                    else _ui.value.copy(switchError = true, resolutionError = null)
            }
        }
    }

    override fun onCleared() {
        engine?.let(playback::release) // 网页模式不持有引擎，不能释放其他播放页的实例。
        engine = null
        super.onCleared()
    }

    private class NativeVodUnavailable : IllegalStateException("该点播暂无可用的原生播放地址，请尝试其他线路或片源")

    private companion object {
        val HISTORY_KEYS = setOf("itemId", "mediaTitle", "episodeTitle", "cover")
    }
}
