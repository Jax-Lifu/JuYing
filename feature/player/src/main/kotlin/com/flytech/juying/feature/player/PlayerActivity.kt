package com.flytech.juying.feature.player

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.WindowManager
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceError
import android.webkit.WebSettings
import android.webkit.PermissionRequest
import android.net.Uri
import androidx.activity.addCallback
import androidx.activity.viewModels
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.view.Gravity
import android.widget.SeekBar
import android.widget.LinearLayout
import com.flytech.juying.player.api.PlayerTrackType
import com.flytech.juying.core.data.LiveRepository
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.ui.JuyingActivity
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.core.ui.SourcePickerHost
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.first
import com.flytech.juying.core.designsystem.R as D
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.isVisible
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.feature.player.databinding.ActivityPlayerBinding
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.launch

/** 全屏播放器 Activity，绑定 SurfaceView 原生渲染并处理按键分发。 */
@AndroidEntryPoint
class PlayerActivity : JuyingActivity(), SourcePickerHost {
    @Inject lateinit var navigator: Navigator
    @Inject lateinit var sources: SourceRepository
    @Inject lateinit var live: LiveRepository
    private var sourceLabel: String? = null
    private var portrait = false
    private var dragging = false
    private var epgKey: String? = null
    private var epgUpdatedAt = 0L
    private var epgJob: kotlinx.coroutines.Job? = null
    private var programmes = emptyList<com.flytech.juying.core.model.EpgProgram>()

    private val vm: PlayerViewModel by viewModels()
    private lateinit var binding: ActivityPlayerBinding
    private var webView: WebView? = null
    private var webItem: PlayItem? = null
    private var fullscreenView: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null

    private val handler = Handler(Looper.getMainLooper())
    private val hideControls = Runnable {
        if (!portrait && !binding.recovery.isVisible && supportFragmentManager.findFragmentByTag("source-picker") == null) {
            binding.controls.isVisible = false; binding.topControls.isVisible = false; binding.transport.isVisible = false
        }
    }

    // 进度低频轮询：只在控制条可见且处于前台时运行，降低低配机 CPU 占用。
    private val tick = object : Runnable {
        override fun run() {
            val dur = vm.durationMs()
            binding.progress.isEnabled = dur > 0
            binding.progress.max = if (dur > 0) 1000 else 0
            if (!dragging) binding.progress.progress = if (dur > 0) (vm.positionMs() * 1000 / dur).toInt() else 0
            if (!vm.ui.value.isLive) {
                if (!dragging) binding.time.text = formatTime(vm.positionMs())
                binding.duration.text = if (dur > 0) formatTime(dur) else "--:--"
            } else renderProgramme()
            val height = vm.ui.value.playback.videoHeight
            binding.quality.text = if (height > 0) "${height}P" else getString(R.string.player_quality)
            binding.quality.contentDescription = "${getString(R.string.player_quality)} · ${binding.quality.text}"
            if (binding.controls.isVisible) handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        binding = ActivityPlayerBinding.inflate(layoutInflater)
        setContentView(binding.root)
        hideSystemBars()
        androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(binding.root) { view, insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            view.setPadding(safe.left, safe.top, safe.right, safe.bottom)
            layoutPlayer()
            insets
        }
        onBackPressedDispatcher.addCallback(this) {
            when {
                fullscreenView != null -> exitWebFullscreen()
                vm.ui.value.pendingTitle != null -> vm.cancelSwitch()
                binding.controls.isVisible && !portrait -> { binding.controls.isVisible = false; binding.topControls.isVisible = false; binding.transport.isVisible = false }
                else -> finish()
            }
        }
        // 兼容手机/平板触控屏点击唤出或隐藏控制条
        binding.videoStage.setOnClickListener {
            if (binding.controls.isVisible && !portrait) { binding.controls.isVisible = false; binding.topControls.isVisible = false; binding.transport.isVisible = false }
            else showControls()
        }
        binding.back.setOnClickListener { finish() }
        binding.switchSource.setOnClickListener { navigator.showSourcePicker(this, vm.currentRequest?.sourceId) }
        binding.playPause.setOnClickListener { vm.togglePlay(); showControls() }
        binding.previous.setOnClickListener { if (vm.ui.value.isLive) vm.zap(-1) else vm.changeEpisode(-1); showControls() }
        binding.next.setOnClickListener { if (vm.ui.value.isLive) vm.zap(1) else vm.changeEpisode(1); showControls() }
        binding.lines.setOnClickListener {
            val lines = vm.availableLines()
            MaterialAlertDialogBuilder(this).setTitle(D.string.ui_lines)
                .setItems(lines.mapIndexed { index, line -> line.label.ifBlank { "${getString(D.string.ui_lines)} ${index + 1}" } }.toTypedArray()) { _, index -> vm.selectLine(index) }.show()
        }
        binding.audio.setOnClickListener { showTracks(PlayerTrackType.AUDIO) }
        binding.subtitles.setOnClickListener { showTracks(PlayerTrackType.SUBTITLE) }
        binding.quality.setOnClickListener { showQuality() }
        binding.speed.setOnClickListener { showSpeed() }
        binding.channels.setOnClickListener { showChannels() }
        binding.episodes.setOnClickListener { showEpisodes() }
        binding.retry.setOnClickListener { vm.retry() }
        binding.cancelSwitch.setOnClickListener { vm.cancelSwitch() }
        binding.returnPrevious.setOnClickListener { vm.returnPrevious() }
        binding.fullscreen.setOnClickListener { requestedOrientation = if (portrait) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT }
        binding.progress.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, value: Int, fromUser: Boolean) {
                if (fromUser) {
                    binding.time.text = formatTime(vm.durationMs() * value / 1000)
                    if (!dragging) vm.seekTo(vm.durationMs() * value / 1000) // D-pad seeking has no touch callbacks.
                }
            }
            override fun onStartTrackingTouch(bar: SeekBar?) { dragging = true; handler.removeCallbacks(hideControls) }
            override fun onStopTrackingTouch(bar: SeekBar?) { vm.seekTo(vm.durationMs() * binding.progress.progress / 1000); dragging = false; showControls() }
        })
        binding.root.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            if (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop) layoutPlayer()
        }
        binding.controls.addOnLayoutChangeListener { _, _, top, _, bottom, _, oldTop, _, oldBottom ->
            if (bottom - top != oldBottom - oldTop) layoutPlayer()
        }

        parseRequest(intent)?.let(vm::start) ?: run { finish(); return }
        binding.root.post { layoutPlayer(); showControls() }

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) { vm.ui.collect(::render) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        parseRequest(intent)?.let(vm::start)
    }

    override fun onStart() {
        super.onStart()
        vm.attachSurface(binding.surface)
        vm.attachSubtitles(binding.subtitleContainer)
        vm.onForeground()
        if (binding.controls.isVisible) showControls()
    }

    override fun onStop() {
        vm.onBackground()
        vm.detachSurface()
        handler.removeCallbacksAndMessages(null)
        destroyWebPlayer() // 网页播放器由页面自身持有，离开时销毁以停止 iframe 内的音视频。
        super.onStop()
    }

    private fun render(s: PlayerUiState) {
        if (s.webPage != null) showWebPlayer(s.webPage) else destroyWebPlayer()
        binding.surface.isVisible = s.webPage == null
        binding.webContainer.isVisible = s.webPage != null
        binding.title.text = vm.currentRequest?.extra?.get("mediaTitle") ?: s.title
        binding.sourceName.text = vm.currentRequest?.extra?.get("episodeTitle").orEmpty()
        binding.sourceName.isVisible = binding.sourceName.text.isNotBlank()
        binding.loading.isVisible = s.loading && s.error == null
        binding.progress.isVisible = !s.isLive && s.webPage == null
        binding.progress.isEnabled = vm.durationMs() > 0
        binding.playPause.isVisible = s.webPage == null
        binding.previous.isVisible = s.webPage == null
        binding.next.isVisible = s.webPage == null
        binding.audio.isVisible = s.webPage == null
        binding.subtitles.isVisible = s.webPage == null
        binding.quality.isVisible = s.webPage == null
        binding.speed.isVisible = s.webPage == null && !s.isLive
        binding.speed.text = "${vm.playbackSpeed()}×"
        binding.lines.isVisible = s.webPage == null && vm.availableLines().size > 1
        binding.channels.isVisible = s.isLive
        binding.episodes.isVisible = s.episodes.isNotEmpty() || !vm.currentRequest?.extra?.get("itemId").isNullOrEmpty()
        binding.duration.isVisible = !s.isLive && s.webPage == null
        binding.programme.isVisible = s.isLive
        binding.programmeProgress.isVisible = s.isLive && programmes.isNotEmpty()
        val episodeRef = vm.currentRequest?.ref
        val episodeIndex = s.episodes.indexOfFirst { episodeRef != null && (it.ref == episodeRef || episodeRef in it.legacyRefs) }
        binding.previous.isEnabled = s.isLive || s.pendingTitle == null && episodeIndex > 0
        binding.next.isEnabled = s.isLive || s.pendingTitle == null && episodeIndex >= 0 && episodeIndex < s.episodes.lastIndex
        binding.previous.alpha = if (binding.previous.isEnabled) 1f else .35f
        binding.next.alpha = if (binding.next.isEnabled) 1f else .35f
        binding.previous.contentDescription = getString(if (s.isLive) D.string.ui_previous_channel else R.string.player_previous_episode)
        binding.next.contentDescription = getString(if (s.isLive) D.string.ui_next_channel else R.string.player_next_episode)
        binding.previous.tooltipText = binding.previous.contentDescription
        binding.next.tooltipText = binding.next.contentDescription
        binding.playPause.setImageResource(if (s.playback.isPlaying) R.drawable.ic_player_pause else D.drawable.ic_play)
        binding.playPause.contentDescription = getString(if (s.playback.isPlaying) D.string.ui_pause else D.string.ui_play)
        if (s.isLive) binding.time.setText(D.string.ui_live_now)
        val recoveryWasVisible = binding.recovery.isVisible
        binding.recovery.isVisible = s.error != null || s.pendingTitle != null || s.switchError
        binding.error.text = s.resolutionError ?: getString(when {
            s.switchError -> D.string.ui_resolve_error
            s.pendingTitle != null -> D.string.ui_resolving
            else -> D.string.ui_play_error
        })
        binding.pendingTitle.text = s.pendingTitle.orEmpty()
        binding.pendingTitle.isVisible = s.pendingTitle != null
        binding.cancelSwitch.isVisible = s.pendingTitle != null || s.switchError
        binding.cancelSwitch.setText(if (s.switchError) D.string.ui_keep_playing else D.string.ui_cancel_switch)
        binding.retry.isVisible = s.error != null || s.switchError
        binding.returnPrevious.isVisible = s.error != null && s.canReturn
        if (binding.recovery.isVisible && !recoveryWasVisible) {
            (if (s.pendingTitle != null || s.switchError) binding.cancelSwitch else if (s.canReturn) binding.returnPrevious else binding.retry).requestFocus()
        }
        val req = vm.currentRequest
        if (s.isLive && epgKey != "${req?.sourceId}:${req?.ref}") refreshProgramme()
        if (sourceLabel != req?.sourceId) {
            sourceLabel = req?.sourceId
            lifecycleScope.launch {
                val name = req?.let { sources.get(it.sourceId)?.name }.orEmpty()
                if (vm.currentRequest?.sourceId == req?.sourceId) binding.switchSource.contentDescription =
                    listOf(name, getString(D.string.ui_switch_source)).filter { it.isNotBlank() }.joinToString(" · ")
            }
        }
        fitSurface()
    }

    private fun layoutPlayer() {
        portrait = !resources.getBoolean(D.bool.jy_wide) && resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT
        val stage = binding.videoStage.layoutParams as FrameLayout.LayoutParams
        val controls = binding.controls.layoutParams as FrameLayout.LayoutParams
        if (portrait) {
            stage.height = (binding.root.width - binding.root.paddingLeft - binding.root.paddingRight) * 9 / 16; stage.topMargin = 0
            controls.gravity = Gravity.TOP; controls.topMargin = stage.height
            binding.controls.isVisible = true; binding.topControls.isVisible = true; binding.transport.isVisible = true
        } else {
            stage.height = ViewGroup.LayoutParams.MATCH_PARENT; stage.topMargin = 0
            controls.gravity = Gravity.BOTTOM; controls.topMargin = 0
        }
        binding.videoStage.layoutParams = stage; binding.controls.layoutParams = controls
        binding.actionRow.orientation = if (portrait) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
        val options = binding.options.layoutParams as LinearLayout.LayoutParams
        options.width = if (portrait) ViewGroup.LayoutParams.MATCH_PARENT else 0
        options.weight = if (portrait) 0f else 1f
        binding.options.layoutParams = options
        binding.fullscreen.isVisible = !resources.getBoolean(D.bool.jy_wide)
        binding.videoStage.post { fitSurface() }
    }
    private fun fitSurface() {
        val state = vm.ui.value.playback
        val width = binding.videoStage.width; val height = binding.videoStage.height
        if (width <= 0 || height <= 0 || state.videoWidth <= 0 || state.videoHeight <= 0) return
        val ratio = state.videoWidth.toDouble() / state.videoHeight
        val targetWidth = minOf(width, (height * ratio).toInt())
        val targetHeight = minOf(height, (width / ratio).toInt())
        val params = binding.surface.layoutParams as FrameLayout.LayoutParams
        if (params.width != targetWidth || params.height != targetHeight) {
            params.width = targetWidth; params.height = targetHeight; params.gravity = Gravity.CENTER
            binding.surface.layoutParams = params
        }
    }
    private fun showControls() {
        binding.controls.isVisible = true; binding.topControls.isVisible = true; binding.transport.isVisible = true
        handler.removeCallbacks(hideControls); handler.removeCallbacks(tick)
        handler.post(tick)
        if (vm.ui.value.isLive && System.currentTimeMillis() - epgUpdatedAt > 60_000) refreshProgramme()
        if (!portrait) handler.postDelayed(hideControls, 6000)
    }
    private fun refreshProgramme() {
        val request = vm.currentRequest ?: return
        val key = "${request.sourceId}:${request.ref}"
        if (epgKey != key) programmes = emptyList()
        epgKey = key; epgUpdatedAt = System.currentTimeMillis()
        epgJob?.cancel()
        epgJob = lifecycleScope.launch {
            try {
                val result = live.epg(request.sourceId, request.ref).sortedBy { it.startMs }
                if (epgKey == key) { programmes = result; renderProgramme() }
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { programmes = emptyList(); renderProgramme() }
        }
    }
    private fun renderProgramme() {
        val now = System.currentTimeMillis()
        val current = programmes.firstOrNull { now >= it.startMs && now < it.endMs }
        val next = programmes.firstOrNull { it.startMs > now }
        val time = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT)
        binding.time.text = current?.let { "${time.format(java.util.Date(it.startMs))} – ${time.format(java.util.Date(it.endMs))}" }
            ?: getString(D.string.ui_live_now)
        binding.programme.text = listOfNotNull(current?.title, next?.let { getString(D.string.ui_next_programme, it.title) })
            .joinToString("\n").ifEmpty { getString(D.string.ui_no_epg) }
        binding.programmeProgress.isVisible = current != null
        if (current != null) binding.programmeProgress.progress = ((now - current.startMs) * 1000 / (current.endMs - current.startMs)).toInt()
    }
    override fun playFromPicker(request: PlayRequest) { vm.start(request) }
    private fun showTracks(type: PlayerTrackType) {
        val subtitles = type == PlayerTrackType.SUBTITLE
        val tracks = vm.tracks(type)
        val labels = (if (subtitles) listOf(getString(D.string.ui_subtitles_off)) else emptyList()) + tracks.map { it.label }
        val builder = MaterialAlertDialogBuilder(this).setTitle(if (subtitles) D.string.ui_subtitles else D.string.ui_audio)
        if (labels.isEmpty()) builder.setMessage(D.string.ui_no_tracks).setPositiveButton(D.string.ui_close, null).show()
        else builder.setSingleChoiceItems(labels.toTypedArray(), tracks.indexOfFirst { it.selected } + if (subtitles) 1 else 0) { dialog, index ->
            vm.selectTrack(type, tracks.getOrNull(index - if (subtitles) 1 else 0)?.id); dialog.dismiss(); showControls()
        }.setNegativeButton(D.string.ui_close, null).show()
    }
    private fun showQuality() {
        val tracks = vm.tracks(PlayerTrackType.VIDEO)
        val dialog = MaterialAlertDialogBuilder(this).setTitle(R.string.player_quality)
        if (tracks.size <= 1) {
            dialog.setMessage(tracks.singleOrNull()?.let { "${it.label}\n${getString(R.string.player_single_quality)}" }
                ?: getString(R.string.player_quality_wait)).setPositiveButton(D.string.ui_close, null).show()
        } else {
            val labels = listOf(getString(R.string.player_auto_quality)) + tracks.map { it.label }
            dialog.setSingleChoiceItems(labels.toTypedArray(), tracks.indexOfFirst { it.selected } + 1) { picker, index ->
                vm.selectTrack(PlayerTrackType.VIDEO, tracks.getOrNull(index - 1)?.id)
                picker.dismiss(); showControls()
            }.setNegativeButton(D.string.ui_close, null).show()
        }
    }
    private fun showSpeed() {
        val speeds = listOf(.5f, .75f, 1f, 1.25f, 1.5f, 2f)
        MaterialAlertDialogBuilder(this).setTitle(R.string.player_speed)
            .setSingleChoiceItems(speeds.map { "${it}×" }.toTypedArray(), speeds.indexOf(vm.playbackSpeed())) { dialog, index ->
                vm.setPlaybackSpeed(speeds[index]); binding.speed.text = "${vm.playbackSpeed()}×"
                dialog.dismiss(); showControls()
            }.setNegativeButton(D.string.ui_close, null).show()
    }
    private fun showChannels() {
        val req = vm.currentRequest ?: return
        lifecycleScope.launch {
            try {
                val channels = live.channelGroups(req.sourceId).first().flatMap { it.channels }
                MaterialAlertDialogBuilder(this@PlayerActivity).setTitle(D.string.ui_channels)
                    .setSingleChoiceItems(channels.map { it.name }.toTypedArray(), channels.indexOfFirst { it.id == req.ref }) { dialog, index ->
                        val channel = channels[index]
                        vm.start(PlayRequest(PlayKind.LIVE, req.sourceId, channel.id, channel.name)); dialog.dismiss()
                    }.setNegativeButton(D.string.ui_close, null).show()
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { MaterialAlertDialogBuilder(this@PlayerActivity).setMessage(D.string.ui_failed).setPositiveButton(D.string.ui_close, null).show() }
        }
    }
    private fun showEpisodes() {
        val episodes = vm.ui.value.episodes
        val picker = MaterialAlertDialogBuilder(this).setTitle(R.string.player_episodes)
        if (episodes.isEmpty()) {
            picker.setMessage(if (vm.ui.value.episodeError) D.string.ui_failed else D.string.content_loading)
                .setPositiveButton(D.string.ui_retry) { _, _ -> vm.refreshEpisodes() }.setNegativeButton(D.string.ui_close, null).show()
        } else {
            val ref = vm.currentRequest?.ref
            picker.setSingleChoiceItems(episodes.map { it.name }.toTypedArray(), episodes.indexOfFirst {
                ref != null && (it.ref == ref || ref in it.legacyRefs)
            }) { dialog, index ->
                vm.selectEpisode(index); dialog.dismiss(); showControls()
            }.setNegativeButton(D.string.ui_close, null).show()
        }
    }
    private fun formatTime(ms: Long): String {
        val seconds = ms.coerceAtLeast(0) / 1000
        return if (seconds >= 3600) "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
            else "%02d:%02d".format(seconds / 60, seconds % 60)
    }
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_MENU) { navigator.showSourcePicker(this, vm.currentRequest?.sourceId); return true }
        if (webView != null) return super.onKeyDown(keyCode, event)
        val directional = keyCode in listOf(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN)
        if (directional && (binding.controls.isVisible || binding.recovery.isVisible)) {
            handler.removeCallbacks(hideControls)
            return super.onKeyDown(keyCode, event)
        }
        val isLive = vm.ui.value.isLive
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> { showControls(); binding.playPause.requestFocus(); return true }
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> vm.togglePlay()
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> if (isLive) vm.zap(-1) else vm.changeEpisode(-1)
            KeyEvent.KEYCODE_MEDIA_NEXT -> if (isLive) vm.zap(1) else vm.changeEpisode(1)
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT -> {
                showControls(); (if (isLive) binding.playPause else binding.progress).requestFocus(); return true
            }
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_CHANNEL_UP -> if (isLive) vm.zap(-1)
            KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_CHANNEL_DOWN -> if (isLive) vm.zap(1)
            else -> return super.onKeyDown(keyCode, event)
        }
        showControls()
        return true
    }

    @android.annotation.SuppressLint("SetJavaScriptEnabled")
    private fun showWebPlayer(item: PlayItem) {
        if (webItem == item && webView != null) return
        destroyWebPlayer()
        val uri = Uri.parse(item.url)
        if (uri.scheme != "https" && uri.scheme != "http") return
        webItem = item
        val browser = WebView(this)
        webView = browser
        browser.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        browser.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                request.url.scheme != "https" && request.url.scheme != "http"

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame && webView === view) {
                    binding.error.text = getString(R.string.web_playback_error)
                    binding.error.isVisible = true
                    binding.loading.isVisible = false
                }
            }
        }
        browser.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, progress: Int) {
                if (webView === view) binding.loading.isVisible = progress < WEB_PAGE_COMPLETE
            }

            override fun onPermissionRequest(request: PermissionRequest) {
                // 只允许当前页面的 DRM 标识请求；摄像头、麦克风等与播放无关。
                if (request.origin.host == browser.url?.let(Uri::parse)?.host &&
                    PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID in request.resources) {
                    request.grant(arrayOf(PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID))
                } else request.deny()
            }

            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                exitWebFullscreen()
                fullscreenView = view
                fullscreenCallback = callback
                binding.webContainer.addView(view, FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
                browser.isVisible = false
                view.requestFocus()
            }

            override fun onHideCustomView() = exitWebFullscreen()
        }
        binding.webContainer.addView(browser, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        browser.loadUrl(item.url, item.headers)
        browser.requestFocus()
    }

    private fun exitWebFullscreen() {
        fullscreenView?.let(binding.webContainer::removeView)
        fullscreenView = null
        val callback = fullscreenCallback
        fullscreenCallback = null
        callback?.onCustomViewHidden()
        webView?.isVisible = true
    }

    private fun destroyWebPlayer() {
        exitWebFullscreen()
        val browser = webView ?: return
        webView = null
        webItem = null
        binding.webContainer.removeView(browser)
        browser.stopLoading()
        browser.loadUrl("about:blank")
        browser.destroy()
    }

    private fun hideSystemBars() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).let { controller ->
            controller.hide(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    private fun parseRequest(intent: Intent): PlayRequest? {
        val kind = intent.getStringExtra(EXTRA_KIND)?.let { runCatching { PlayKind.valueOf(it) }.getOrNull() } ?: return null
        val sourceId = intent.getStringExtra(EXTRA_SOURCE) ?: return null
        val ref = intent.getStringExtra(EXTRA_REF) ?: return null
        val extraJson = intent.getStringExtra(EXTRA_EXTRA).orEmpty()
        val extraMap = if (extraJson.isNotEmpty()) {
            runCatching {
                val obj = org.json.JSONObject(extraJson)
                buildMap {
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        put(k, obj.optString(k, ""))
                    }
                }
            }.getOrDefault(emptyMap())
        } else {
            emptyMap()
        }
        return PlayRequest(kind, sourceId, ref, intent.getStringExtra(EXTRA_TITLE).orEmpty(), extraMap)
    }

    companion object {
        private const val WEB_PAGE_COMPLETE = 100
        private const val EXTRA_KIND = "kind"
        private const val EXTRA_SOURCE = "source"
        private const val EXTRA_REF = "ref"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_EXTRA = "extra"

        fun intent(context: Context, r: PlayRequest) = Intent(context, PlayerActivity::class.java)
            .putExtra(EXTRA_KIND, r.kind.name)
            .putExtra(EXTRA_SOURCE, r.sourceId)
            .putExtra(EXTRA_REF, r.ref)
            .putExtra(EXTRA_TITLE, r.title)
            .putExtra(EXTRA_EXTRA, if (r.extra.isEmpty()) "" else org.json.JSONObject(r.extra).toString())
    }
}
