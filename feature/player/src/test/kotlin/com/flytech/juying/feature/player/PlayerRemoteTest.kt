package com.flytech.juying.feature.player

import android.os.Looper
import android.view.KeyEvent
import android.view.SurfaceView
import android.view.View
import androidx.lifecycle.ViewModelStore
import com.flytech.juying.core.data.HistoryRepository
import com.flytech.juying.core.data.LiveRepository
import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.datastore.SettingsDataSource
import com.flytech.juying.core.domain.GetPlayItemUseCase
import com.flytech.juying.core.domain.ZapChannelUseCase
import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.Episode
import com.flytech.juying.core.model.FileEntry
import com.flytech.juying.core.model.HistoryEntry
import com.flytech.juying.core.model.PlayGroup
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.VodDetail
import com.flytech.juying.core.model.VodItem
import com.flytech.juying.feature.player.databinding.ActivityPlayerBinding
import com.flytech.juying.player.api.PlaybackManager
import com.flytech.juying.player.api.PlayerEngine
import com.flytech.juying.player.api.PlayerState
import dagger.hilt.android.internal.managers.ActivityComponentManager
import java.lang.reflect.Proxy
import java.time.Duration
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], qualifiers = "w960dp-h540dp-land-television-xhdpi", shadows = [PlayerRemoteTest.ComponentManagerShadow::class])
class PlayerRemoteTest {
    private val engine = RecordingEngine()
    private val store = ViewModelStore()
    private lateinit var vm: PlayerViewModel
    private lateinit var activity: PlayerActivity
    private lateinit var binding: ActivityPlayerBinding
    private lateinit var controller: org.robolectric.android.controller.ActivityController<PlayerActivity>
    private var menuCalls = 0
    private var failResolution = false

    @Before fun setUp() {
        val history = object : HistoryRepository {
            override fun observeRecent(limit: Int) = flowOf(emptyList<HistoryEntry>())
            override suspend fun get(id: String): HistoryEntry? = null
            override suspend fun record(entry: HistoryEntry) = Unit
            override suspend fun delete(id: String) = Unit
            override suspend fun clear() = Unit
        }
        val vod = Proxy.newProxyInstance(VodRepository::class.java.classLoader, arrayOf(VodRepository::class.java)) { _, method, args ->
            when (method.name) {
                "resolve" -> {
                    check(!failResolution) { "Test resolution failed" }
                    PlayItem(args!![1] as String, "Episode", "https://example.test/video.mp4",
                        backupLines = listOf(com.flytech.juying.core.model.PlayLine("https://example.test/backup.mp4", "Backup")))
                }
                "detail" -> VodDetail(VodItem("album", "source", "Series"), playGroups = listOf(PlayGroup("Main",
                    listOf(Episode("First", "1"), Episode("Second", "2"), Episode("Third", "3")))))
                else -> error("Unexpected repository call: ${method.name}")
            }
        } as VodRepository
        val live = object : LiveRepository {
            val channels = listOf(Channel("1", "One"), Channel("2", "Two"), Channel("3", "Three"))
            override fun channelGroups(sourceId: String) = flowOf(listOf(ChannelGroup("All", channels)))
            override suspend fun findChannel(sourceId: String, channelId: String) = channels.firstOrNull { it.id == channelId }
            override suspend fun resolve(sourceId: String, channel: Channel) =
                PlayItem(channel.id, channel.name, "https://example.test/live", isLive = true)
        }
        val playback = PlaybackManager({ engine }, SettingsDataSource(RuntimeEnvironment.getApplication()))
        runBlocking { playback.acquire() }
        val browse = object : com.flytech.juying.core.data.BrowseRepository {
            override suspend fun list(sourceId: String, path: String) = emptyList<FileEntry>()
            override suspend fun playItem(sourceId: String, entry: FileEntry): PlayItem = error("Unexpected browse call")
        }
        vm = PlayerViewModel(GetPlayItemUseCase(live, vod, browse, history), ZapChannelUseCase(live), history, playback, vod)
        store.put("player", vm)
        vm.start(PlayRequest(PlayKind.VOD, "source", "2", extra = mapOf("itemId" to "album")))
        idle()
        controller = Robolectric.buildActivity(PlayerActivity::class.java)
        activity = controller.get()
        // Exercise the real activity and layout with a controlled player; only Hilt assembly is bypassed.
        ReflectionHelpers.setField(activity, "injected", true)
        ReflectionHelpers.setField(activity, "vm\$delegate", lazyOf(vm))
        activity.sources = Proxy.newProxyInstance(com.flytech.juying.core.data.SourceRepository::class.java.classLoader,
            arrayOf(com.flytech.juying.core.data.SourceRepository::class.java)) { _, method, _ ->
            if (method.name == "get") null else error("Unexpected source call: ${method.name}")
        } as com.flytech.juying.core.data.SourceRepository
        activity.live = live
        activity.navigator = Proxy.newProxyInstance(com.flytech.juying.core.ui.Navigator::class.java.classLoader,
            arrayOf(com.flytech.juying.core.ui.Navigator::class.java)) { _, method, _ ->
            check(method.name == "showSourcePicker")
            menuCalls++
            Unit
        } as com.flytech.juying.core.ui.Navigator
        controller.create().start().resume().visible()
        idle()
        binding = ActivityPlayerBinding.bind(activity.findViewById<View>(android.R.id.content).let { (it as android.view.ViewGroup).getChildAt(0) })
        controller.windowFocusChanged(true)
        layout()
        idle()
    }

    @After fun tearDown() {
        if (::controller.isInitialized) controller.pause().stop().destroy()
        store.clear()
    }

    @Test fun hiddenControlsSeekOnTheFirstLeftAndRightPress() {
        hideControls()
        press(KeyEvent.KEYCODE_DPAD_RIGHT)
        assertEquals(70_000L, engine.position)
        assertTrue(binding.controls.isShown)
        hideControls()
        press(KeyEvent.KEYCODE_DPAD_LEFT)
        assertEquals(60_000L, engine.position)
    }

    @Test fun dedicatedSeekKeysWorkWhileAButtonHasFocusAndClampAtTheEnds() {
        binding.next.requestFocus()
        press(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
        assertEquals(70_000L, engine.position)
        press(KeyEvent.KEYCODE_MEDIA_REWIND)
        assertEquals(60_000L, engine.position)
        engine.position = 1_000L
        press(KeyEvent.KEYCODE_MEDIA_REWIND)
        assertEquals(0L, engine.position)
        engine.position = 119_000L
        press(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
        assertEquals(120_000L, engine.position)
    }

    @Test fun revealingControlsWithCenterDoesNotActivateTheFocusedButton() {
        hideControls()
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertTrue("Focused view: ${binding.root.findFocus()}; playing: ${engine.state.value}", binding.playPause.hasFocus())
        assertTrue(engine.state.value.playWhenReady)
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertFalse(engine.state.value.playWhenReady)
    }

    @Test fun remoteCanNavigateToAndActivateBothEpisodeButtons() {
        hideControls()
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertTrue("Play must have focus before navigation", binding.playPause.hasFocus())
        assertSame(binding.next, binding.playPause.focusSearch(View.FOCUS_RIGHT))
        press(KeyEvent.KEYCODE_DPAD_RIGHT)
        assertTrue("Right from play must focus next episode: focus=${binding.root.findFocus()}, nextEnabled=${binding.next.isEnabled}, episodes=${vm.ui.value.episodes}", binding.next.hasFocus())
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("3", vm.currentRequest?.ref)
        binding.playPause.requestFocus()
        press(KeyEvent.KEYCODE_DPAD_LEFT)
        assertTrue(binding.previous.hasFocus())
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("2", vm.currentRequest?.ref)
    }

    @Test
    @Config(qualifiers = "w960dp-h540dp-land-xhdpi")
    fun landscapeBoxesWithoutTelevisionUiModeStartOnPlayback() {
        assertTrue(binding.playPause.hasFocus())
        press(KeyEvent.KEYCODE_DPAD_RIGHT)
        assertTrue(binding.next.hasFocus())
    }

    @Test fun initialControlsGiveTheRemoteAPlaybackFocus() {
        assertTrue("Initial focus: ${binding.root.findFocus()}", binding.playPause.hasFocus())
        press(KeyEvent.KEYCODE_DPAD_RIGHT)
        assertTrue(binding.next.hasFocus())
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("3", vm.currentRequest?.ref)
    }

    @Test fun progressAndTransportAreReachableInBothDirections() {
        hideControls()
        press(KeyEvent.KEYCODE_DPAD_RIGHT)
        assertTrue(binding.progress.hasFocus())
        press(KeyEvent.KEYCODE_DPAD_RIGHT)
        assertEquals(80_000L, engine.position)
        press(KeyEvent.KEYCODE_DPAD_DOWN)
        assertTrue(binding.playPause.hasFocus())
        press(KeyEvent.KEYCODE_DPAD_UP)
        assertTrue(binding.progress.hasFocus())
        press(KeyEvent.KEYCODE_DPAD_LEFT)
        assertEquals(70_000L, engine.position)
    }

    @Test fun holdingMediaButtonsDoesNotSkipMultipleEpisodesOrToggleRepeatedly() {
        hold(KeyEvent.KEYCODE_MEDIA_PREVIOUS, 3)
        assertEquals("1", vm.currentRequest?.ref)
        hold(KeyEvent.KEYCODE_MEDIA_NEXT, 3)
        assertEquals("2", vm.currentRequest?.ref)
        hold(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 3)
        assertFalse(engine.state.value.playWhenReady)
        press(KeyEvent.KEYCODE_MEDIA_PLAY)
        press(KeyEvent.KEYCODE_MEDIA_PLAY)
        assertTrue(engine.state.value.playWhenReady)
        press(KeyEvent.KEYCODE_MEDIA_PAUSE)
        press(KeyEvent.KEYCODE_MEDIA_PAUSE)
        assertFalse(engine.state.value.playWhenReady)
    }

    @Test fun holdingCenterToRevealControlsDoesNotTriggerLongClickOrPause() {
        hideControls()
        hold(KeyEvent.KEYCODE_DPAD_CENTER, 3)
        assertTrue(engine.state.value.playWhenReady)
        assertTrue(binding.playPause.hasFocus())
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertFalse(engine.state.value.playWhenReady)
    }

    @Test fun liveChannelKeysSwitchEvenWhenControlsAreVisibleAndSeekIsIgnored() {
        vm.start(PlayRequest(PlayKind.LIVE, "source", "2"))
        idle()
        press(KeyEvent.KEYCODE_CHANNEL_DOWN)
        assertEquals("3", vm.currentRequest?.ref)
        press(KeyEvent.KEYCODE_CHANNEL_UP)
        assertEquals("2", vm.currentRequest?.ref)
        press(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
        press(KeyEvent.KEYCODE_MEDIA_REWIND)
        assertEquals(60_000L, engine.position)
        hideControls()
        press(KeyEvent.KEYCODE_DPAD_UP)
        assertEquals("1", vm.currentRequest?.ref)
    }

    @Test fun disabledNextEpisodeDoesNotBlockTheSettingsControls() {
        press(KeyEvent.KEYCODE_MEDIA_NEXT)
        assertEquals("3", vm.currentRequest?.ref)
        assertFalse(binding.next.isEnabled)
        binding.playPause.requestFocus()
        press(KeyEvent.KEYCODE_DPAD_RIGHT)
        assertTrue("Focus must reach quality past the disabled next button: ${binding.root.findFocus()}", binding.quality.hasFocus())
    }

    @Test fun unavailableDurationDoesNotTrapFocusBelowTheProgressBar() {
        engine.duration = 0L
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        assertFalse(binding.progress.isEnabled)
        binding.playPause.requestFocus()
        press(KeyEvent.KEYCODE_DPAD_UP)
        assertFalse("Up must escape the disabled progress bar", binding.playPause.hasFocus())
    }

    @Test fun remoteUseStillAllowsControlsToAutoHide() {
        binding.playPause.requestFocus()
        press(KeyEvent.KEYCODE_DPAD_UP)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(7))
        assertEquals(View.GONE, binding.controls.visibility)
    }

    @Test fun everyVisibleControlIsReachableByDirectionalKeys() {
        val controls = listOf(binding.back, binding.switchSource, binding.previous, binding.playPause,
            binding.next, binding.progress, binding.quality, binding.speed, binding.subtitles,
            binding.audio, binding.episodes, binding.lines)
        for (control in controls) navigateTo(control)
        vm.start(PlayRequest(PlayKind.LIVE, "source", "2"))
        idle(); layout()
        navigateTo(binding.channels)
    }

    @Test fun allOptionDialogsKeepControlsAndRestoreTheirTriggerAfterBack() {
        for (button in listOf(binding.quality, binding.speed, binding.subtitles, binding.audio, binding.episodes, binding.lines)) {
            navigateTo(button)
            press(KeyEvent.KEYCODE_DPAD_CENTER)
            val dialog = latestDialog()
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(8))
            assertTrue("Controls hidden behind ${button.id}", binding.controls.isShown)
            pressDialog(dialog, KeyEvent.KEYCODE_BACK)
            assertFalse(dialog.isShowing)
            assertTrue("Trigger lost after dialog ${button.id}: ${binding.root.findFocus()}", button.hasFocus())
        }
    }

    @Test fun remoteSelectsQualitySpeedAudioSubtitlesAndLines() {
        navigateTo(binding.quality); press(KeyEvent.KEYCODE_DPAD_CENTER)
        chooseNext(latestDialog())
        assertEquals(com.flytech.juying.player.api.PlayerTrackType.VIDEO to "video-1", engine.selection)
        navigateTo(binding.speed); press(KeyEvent.KEYCODE_DPAD_CENTER)
        chooseNext(latestDialog())
        assertEquals(1.25f, engine.speed)
        navigateTo(binding.audio); press(KeyEvent.KEYCODE_DPAD_CENTER)
        chooseNext(latestDialog())
        assertEquals(com.flytech.juying.player.api.PlayerTrackType.AUDIO to "audio-2", engine.selection)
        navigateTo(binding.subtitles); press(KeyEvent.KEYCODE_DPAD_CENTER)
        chooseNext(latestDialog())
        assertEquals(com.flytech.juying.player.api.PlayerTrackType.SUBTITLE to "subtitle-1", engine.selection)
        navigateTo(binding.lines); press(KeyEvent.KEYCODE_DPAD_CENTER)
        val dialog = latestDialog()
        pressDialog(dialog, KeyEvent.KEYCODE_DPAD_DOWN)
        pressDialog(dialog, KeyEvent.KEYCODE_DPAD_DOWN)
        pressDialog(dialog, KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("https://example.test/backup.mp4", engine.preparedUrl)
    }

    @Test fun remoteSelectsEpisodesAndChannelsFromDialogs() {
        navigateTo(binding.episodes); press(KeyEvent.KEYCODE_DPAD_CENTER)
        chooseNext(latestDialog())
        assertEquals("3", vm.currentRequest?.ref)
        vm.start(PlayRequest(PlayKind.LIVE, "source", "2")); idle(); layout()
        navigateTo(binding.channels); press(KeyEvent.KEYCODE_DPAD_CENTER)
        chooseNext(latestDialog())
        assertEquals("3", vm.currentRequest?.ref)
    }

    @Test fun failedSwitchKeepsFocusWithinRecoveryAndBackRestoresPlaybackControls() {
        failResolution = true
        press(KeyEvent.KEYCODE_MEDIA_NEXT)
        assertTrue(binding.recovery.isShown)
        assertTrue(binding.cancelSwitch.hasFocus())
        press(KeyEvent.KEYCODE_DPAD_UP)
        assertTrue("Recovery lost focus: ${binding.root.findFocus()}", binding.recovery.hasFocus())
        press(KeyEvent.KEYCODE_BACK)
        assertFalse(binding.recovery.isShown)
        assertTrue(binding.controls.isShown)
        assertTrue(binding.playPause.hasFocus())
    }

    @Test fun failedSwitchCanBeRetriedWithTheRemote() {
        failResolution = true
        press(KeyEvent.KEYCODE_MEDIA_NEXT)
        navigateTo(binding.retry)
        failResolution = false
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertFalse(binding.recovery.isShown)
        assertEquals("3", vm.currentRequest?.ref)
        assertTrue(binding.playPause.hasFocus())
    }

    @Test fun menuAndSourceButtonInvokePickerAndBackHidesThenExits() {
        hideControls()
        hold(KeyEvent.KEYCODE_MENU, 3)
        assertEquals(1, menuCalls)
        navigateTo(binding.switchSource); press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals(2, menuCalls)
        press(KeyEvent.KEYCODE_BACK)
        assertFalse(binding.controls.isShown)
        assertFalse(activity.isFinishing)
        press(KeyEvent.KEYCODE_BACK)
        assertTrue(activity.isFinishing)
    }

    @Test fun fullscreenButtonAndBackButtonAreReachableOnLandscapeDevices() {
        // TV resources intentionally omit orientation switching; ordinary landscape devices expose it.
        binding.fullscreen.visibility = View.VISIBLE
        layout()
        navigateTo(binding.fullscreen)
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, activity.requestedOrientation)
        navigateTo(binding.back)
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertTrue(activity.isFinishing)
    }

    @Test fun playerErrorOffersReturnToPreviousAndRestoresFocusAfterRecovery() {
        press(KeyEvent.KEYCODE_MEDIA_NEXT)
        engine.state.value = engine.state.value.copy(error = "Decoder failure")
        idle()
        // Exhaust the backup line so the production state exposes recovery.
        engine.state.value = engine.state.value.copy(error = "Backup failure")
        idle(); layout()
        assertTrue(binding.recovery.isShown)
        navigateTo(binding.returnPrevious)
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("2", vm.currentRequest?.ref)
        assertFalse(binding.recovery.isShown)
        assertTrue(binding.playPause.hasFocus())
    }

    @Test fun emptyTrackDialogsCanBeClosedAndRestoreTheirButtons() {
        engine.noTracks = true
        for (button in listOf(binding.audio, binding.quality)) {
            navigateTo(button); press(KeyEvent.KEYCODE_DPAD_CENTER)
            val dialog = latestDialog()
            pressDialog(dialog, KeyEvent.KEYCODE_DPAD_CENTER)
            assertFalse(dialog.isShowing)
            assertTrue(button.hasFocus())
        }
    }

    @Test fun webPlayerReceivesKeysWithoutNativeSeekingAndRetainsMenuAccess() {
        val browser = android.webkit.WebView(activity)
        ReflectionHelpers.setField(activity, "webView", browser)
        binding.webContainer.visibility = View.VISIBLE
        // Robolectric does not implement Chromium focus. A focused child checks only
        // the Activity's web-mode key forwarding, not navigation within web content.
        val webContent = View(activity).apply {
            isFocusable = true
            isFocusableInTouchMode = true
        }
        binding.webContainer.addView(webContent, android.widget.FrameLayout.LayoutParams(
            android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT))
        val received = mutableListOf<Int>()
        webContent.setOnKeyListener { _, key, _ -> received.add(key); true }
        layout()
        assertTrue(webContent.requestFocus())
        press(KeyEvent.KEYCODE_DPAD_RIGHT)
        press(KeyEvent.KEYCODE_DPAD_CENTER)
        press(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
        assertTrue("Web keys=$received focus=${binding.root.findFocus()}", received.containsAll(listOf(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)))
        assertEquals(60_000L, engine.position)
        press(KeyEvent.KEYCODE_MENU)
        assertEquals(1, menuCalls)
    }

    private fun latestDialog(): androidx.appcompat.app.AlertDialog =
        (org.robolectric.shadows.ShadowDialog.getLatestDialog() as androidx.appcompat.app.AlertDialog).also {
            assertTrue(it.isShowing)
            layoutWindow(it.window!!)
            val root = ReflectionHelpers.callInstanceMethod<Any>(it.window!!.decorView, "getViewRootImpl")
            (org.robolectric.shadow.api.Shadow.extract<org.robolectric.shadows.ShadowViewRootImpl>(root)).callWindowFocusChanged(true)
            idle()
        }

    private fun chooseNext(dialog: androidx.appcompat.app.AlertDialog) {
        pressDialog(dialog, KeyEvent.KEYCODE_DPAD_DOWN)
        pressDialog(dialog, KeyEvent.KEYCODE_DPAD_CENTER)
        assertFalse("Selection must close the dialog: focus=${dialog.window!!.decorView.findFocus()}, selected=${dialog.listView?.selectedItemPosition}", dialog.isShowing)
    }

    private fun pressDialog(dialog: android.app.Dialog, key: Int) {
        val now = android.os.SystemClock.uptimeMillis()
        for (action in listOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            val root = ReflectionHelpers.callInstanceMethod<Any>(dialog.window!!.decorView, "getViewRootImpl")
            ReflectionHelpers.callInstanceMethod<Unit>(root, "dispatchInputEvent",
                ReflectionHelpers.ClassParameter.from(android.view.InputEvent::class.java,
                    KeyEvent(now, now, action, key, 0)))
            idle()
        }
        layout()
    }

    private fun navigateTo(target: View) {
        assertTrue("Target unavailable ${target.id}", target.isShown && target.isEnabled)
        val directions = listOf(View.FOCUS_LEFT to KeyEvent.KEYCODE_DPAD_LEFT, View.FOCUS_RIGHT to KeyEvent.KEYCODE_DPAD_RIGHT,
            View.FOCUS_UP to KeyEvent.KEYCODE_DPAD_UP, View.FOCUS_DOWN to KeyEvent.KEYCODE_DPAD_DOWN)
        val queue = ArrayDeque<Pair<View, List<Int>>>()
        queue.add((binding.root.findFocus() ?: error("No focus")) to emptyList())
        val visited = mutableSetOf<View>()
        while (queue.isNotEmpty()) {
            val (view, keys) = queue.removeFirst()
            if (!visited.add(view)) continue
            if (view === target) {
                keys.forEach(::press)
                assertTrue("Target not focused ${target.id}: ${binding.root.findFocus()}", target.hasFocus())
                return
            }
            directions.filterNot { (direction, _) -> view === binding.progress &&
                (direction == View.FOCUS_LEFT || direction == View.FOCUS_RIGHT) }.forEach { (direction, key) ->
                view.focusSearch(direction)?.takeIf { it.isShown && it.isEnabled }?.let { queue.add(it to (keys + key)) }
            }
        }
        fail("Unreachable control ${target.id} from ${binding.root.findFocus()}")
    }

    private fun hideControls() {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(7))
        assertEquals(View.GONE, binding.controls.visibility)
    }

    private fun press(key: Int) = hold(key, 0)

    private fun hold(key: Int, repeats: Int) {
        val now = android.os.SystemClock.uptimeMillis()
        for (repeat in 0..repeats) send(KeyEvent(now, now, KeyEvent.ACTION_DOWN, key, repeat, 0,
            android.view.KeyCharacterMap.VIRTUAL_KEYBOARD, 0, 0, android.view.InputDevice.SOURCE_DPAD))
        send(KeyEvent(now, now, KeyEvent.ACTION_UP, key, 0, 0,
            android.view.KeyCharacterMap.VIRTUAL_KEYBOARD, 0, 0, android.view.InputDevice.SOURCE_DPAD))
    }

    private fun send(event: KeyEvent) {
        // Enter before Activity dispatch so Android also performs its normal focus navigation.
        val viewRoot = ReflectionHelpers.callInstanceMethod<Any>(activity.window.decorView, "getViewRootImpl")
        ReflectionHelpers.callInstanceMethod<Unit>(viewRoot, "dispatchInputEvent",
            ReflectionHelpers.ClassParameter.from(android.view.InputEvent::class.java, event))
        idle()
        layout()
    }

    private fun layout() = layoutWindow(activity.window)

    private fun layoutWindow(window: android.view.Window) {
        val decor = window.decorView
        decor.measure(View.MeasureSpec.makeMeasureSpec(1920, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY))
        decor.layout(0, 0, 1920, 1080)
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    @Implements(ActivityComponentManager::class)
    class ComponentManagerShadow {
        @Implementation fun initSavedStateHandleHolders() = Unit
        @Implementation fun clearSavedStateHandleHolders() = Unit
    }

    private class RecordingEngine : PlayerEngine {
        override val state = MutableStateFlow(PlayerState())
        var position = 60_000L
        var duration = 120_000L
        override fun setSurfaceView(view: SurfaceView?) = Unit
        var preparedUrl = ""
        var speed = 1f
        var selection: Pair<com.flytech.juying.player.api.PlayerTrackType, String?>? = null
        var noTracks = false
        override fun tracks(type: com.flytech.juying.player.api.PlayerTrackType) = if (noTracks) emptyList() else (1..2).map {
            com.flytech.juying.player.api.PlayerTrack("${type.name.lowercase()}-$it", "Track $it",
                type == com.flytech.juying.player.api.PlayerTrackType.AUDIO && it == 1)
        }
        override fun selectTrack(type: com.flytech.juying.player.api.PlayerTrackType, id: String?) { selection = type to id }
        override fun playbackSpeed() = speed
        override fun setPlaybackSpeed(speed: Float) { this.speed = speed }
        override fun prepare(item: PlayItem) { preparedUrl = item.url }
        override fun play() { state.value = PlayerState(isPlaying = true, playWhenReady = true) }
        override fun pause() { state.value = PlayerState() }
        override fun seekTo(positionMs: Long) { position = positionMs }
        override fun seekBy(deltaMs: Long) = error("Use the bounded ViewModel seek")
        override fun positionMs() = position
        override fun durationMs() = duration
        override fun release() = Unit
    }
}
