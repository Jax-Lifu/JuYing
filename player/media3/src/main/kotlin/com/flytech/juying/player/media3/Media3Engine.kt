package com.flytech.juying.player.media3

import android.content.Context
import android.net.Uri
import android.view.SurfaceView
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.text.CueGroup
import com.flytech.juying.player.api.PlayerTrack
import com.flytech.juying.player.api.PlayerTrackType
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.DecoderMode
import com.flytech.juying.core.model.DeviceProfile
import com.flytech.juying.core.model.PerformanceTier
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.Subtitle
import com.flytech.juying.player.api.PlayerEngine
import com.flytech.juying.player.api.PlayerState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import timber.log.Timber

@UnstableApi
class Media3Engine(
    context: Context,
    profile: DeviceProfile,
    settings: AppSettings,
    private val dataSourceFactory: JuyingDataSourceFactory,
) : PlayerEngine {

    private val _state = MutableStateFlow(PlayerState())
    override val state: StateFlow<PlayerState> = _state.asStateFlow()

    private val player: ExoPlayer = ExoPlayer.Builder(context, renderersFactory(context, settings))
        .setLoadControl(loadControl(profile.tier))
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            /* handleAudioFocus = */ true,
        )
        .setHandleAudioBecomingNoisy(true)
        .build()
        .apply {
            // 4K/HDR：硬解优先；杜比音频由 DefaultAudioSink 按设备/HDMI 能力自动直通。
            videoChangeFrameRateStrategy = if (settings.autoFrameRate) {
                C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS
            } else {
                C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF
            }
            playWhenReady = true
        }

    private var subtitleView: androidx.media3.ui.SubtitleView? = null
    private var pendingHighestVideoQuality = false
    private val listener = object : Player.Listener {
        override fun onTracksChanged(tracks: Tracks) {
            if (!pendingHighestVideoQuality) return
            val highest = tracks.groups.filter { it.type == C.TRACK_TYPE_VIDEO }
                .flatMap { group -> (0 until group.length).map { group to it } }
                .maxWithOrNull(compareBy<Pair<Tracks.Group, Int>> { (group, index) ->
                    group.getTrackFormat(index).let { it.width.coerceAtLeast(0).toLong() * it.height.coerceAtLeast(0) }
                }.thenBy { (group, index) -> group.getTrackFormat(index).bitrate }) ?: return
            // 不过滤不支持的最高档，避免设备能力不足时悄悄降档；交给播放器明确报错。
            pendingHighestVideoQuality = false
            player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                .setOverrideForType(TrackSelectionOverride(highest.first.mediaTrackGroup, highest.second)).build()
        }
        override fun onCues(cueGroup: CueGroup) {
            subtitleView?.setCues(cueGroup.cues)
        }
        override fun onIsPlayingChanged(isPlaying: Boolean) = _state.update { it.copy(isPlaying = isPlaying) }

        override fun onPlaybackStateChanged(playbackState: Int) = _state.update {
            it.copy(
                isBuffering = playbackState == Player.STATE_BUFFERING,
                ended = playbackState == Player.STATE_ENDED,
            )
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) =
            _state.update { it.copy(videoWidth = videoSize.width, videoHeight = videoSize.height) }

        override fun onPlayerError(error: PlaybackException) {
            Timber.e(error, "ExoPlayer error: code=%s", error.errorCodeName)
            _state.update { it.copy(error = "播放失败：${error.errorCodeName}") }
        }
    }

    init {
        player.addListener(listener)
    }

    override fun setSurfaceView(view: SurfaceView?) {
        if (view != null) player.setVideoSurfaceView(view) else player.clearVideoSurface()
    }

    override fun setSubtitleContainer(container: android.view.ViewGroup?) {
        subtitleView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        subtitleView = container?.let { parent ->
            androidx.media3.ui.SubtitleView(parent.context).also {
                parent.addView(it, android.view.ViewGroup.LayoutParams(-1, -1))
                it.setUserDefaultStyle(); it.setUserDefaultTextSize(); it.setCues(player.currentCues.cues)
            }
        }
    }

    override fun prepare(item: PlayItem) {
        pendingHighestVideoQuality = false
        _state.update { PlayerState(isBuffering = true) }
        // A fixed quality belongs to this item; a new line may expose different video groups.
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_VIDEO).build()
        val subtitleConfigs = item.subtitles.mapIndexed { index, sub ->
            sub.toMedia3SubtitleConfig(isDefault = index == 0)
        }
        val mediaItem = MediaItem.Builder()
            .setMediaId(item.id)
            .setUri(item.url)
            .setSubtitleConfigurations(subtitleConfigs)
            .build()
        val mediaSource = DefaultMediaSourceFactory(dataSourceFactory.forHeaders(item.headers))
            .createMediaSource(mediaItem)
        player.setMediaSource(mediaSource, item.startPositionMs)
        pendingHighestVideoQuality = item.preferHighestVideoQuality
        player.prepare()
    }

    override fun tracks(type: PlayerTrackType): List<PlayerTrack> = buildList {
        val mediaType = type.media3Type()
        player.currentTracks.groups.forEachIndexed { groupIndex, group ->
            if (group.type == mediaType) repeat(group.length) { trackIndex ->
                if (group.isTrackSupported(trackIndex)) {
                    val format = group.getTrackFormat(trackIndex)
                    val label = if (type == PlayerTrackType.VIDEO) listOfNotNull(
                        format.height.takeIf { it > 0 }?.let { "${format.width} × $it" },
                        format.bitrate.takeIf { it > 0 }?.let { "${it / 1000} kbps" },
                    ).joinToString(" · ") else listOfNotNull(format.label, format.language,
                        format.channelCount.takeIf { it > 0 }?.let { "$it ch" }).distinct().joinToString(" · ")
                    val selected = if (type == PlayerTrackType.VIDEO) {
                        player.trackSelectionParameters.overrides[group.mediaTrackGroup]?.trackIndices?.contains(trackIndex) == true
                    } else group.isTrackSelected(trackIndex)
                    add(PlayerTrack("$groupIndex:$trackIndex", label.ifEmpty { "${size + 1}" }, selected))
                }
            }
        }
    }
    override fun selectTrack(type: PlayerTrackType, id: String?) {
        val mediaType = type.media3Type()
        val parameters = player.trackSelectionParameters.buildUpon()
        if (id == null) {
            if (type == PlayerTrackType.VIDEO) pendingHighestVideoQuality = false
            player.trackSelectionParameters = parameters.clearOverridesOfType(mediaType)
                .setTrackTypeDisabled(mediaType, type == PlayerTrackType.SUBTITLE).build()
            return
        }
        val indices = id.split(':').mapNotNull(String::toIntOrNull)
        if (indices.size != 2) return
        val group = player.currentTracks.groups.getOrNull(indices[0]) ?: return
        if (group.type != mediaType || indices[1] !in 0 until group.length || !group.isTrackSupported(indices[1])) return
        if (type == PlayerTrackType.VIDEO) pendingHighestVideoQuality = false
        player.trackSelectionParameters = parameters.setTrackTypeDisabled(mediaType, false)
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, indices[1])).build()
    }
    override fun playbackSpeed() = player.playbackParameters.speed
    override fun setPlaybackSpeed(speed: Float) = player.setPlaybackSpeed(speed.coerceIn(.5f, 2f))
    override fun play() = player.play()
    override fun pause() = player.pause()
    override fun seekTo(positionMs: Long) = player.seekTo(positionMs)
    override fun seekBy(deltaMs: Long) {
        val target = (player.currentPosition + deltaMs).coerceAtLeast(0)
        val dur = player.duration
        player.seekTo(if (dur != C.TIME_UNSET) target.coerceAtMost(dur) else target)
    }

    override fun positionMs(): Long = player.currentPosition
    override fun durationMs(): Long = player.duration.takeIf { it != C.TIME_UNSET } ?: 0L

    override fun release() {
        setSubtitleContainer(null)
        player.removeListener(listener)
        player.release()
    }

    private companion object {
        fun PlayerTrackType.media3Type() = when (this) {
            PlayerTrackType.VIDEO -> C.TRACK_TYPE_VIDEO
            PlayerTrackType.AUDIO -> C.TRACK_TYPE_AUDIO
            PlayerTrackType.SUBTITLE -> C.TRACK_TYPE_TEXT
        }
        fun renderersFactory(context: Context, settings: AppSettings) = DefaultRenderersFactory(context)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF)
            .setEnableDecoderFallback(true)
            .setMediaCodecSelector(selector(settings.decoderMode))

        fun selector(mode: DecoderMode) = MediaCodecSelector { mime, secure, tunneling ->
            val infos = MediaCodecUtil.getDecoderInfos(mime, secure, tunneling)
            if (mode == DecoderMode.SOFTWARE_FIRST) infos.sortedByDescending { it.softwareOnly } else infos
        }

        /** 低配机：小缓冲 + 限制字节数，换取更低内存占用；高配机放宽。 */
        fun loadControl(tier: PerformanceTier): DefaultLoadControl {
            val b = DefaultLoadControl.Builder()
            when (tier) {
                PerformanceTier.LOW -> b.setBufferDurationsMs(8_000, 20_000, 1_500, 3_000)
                    .setTargetBufferBytes(24 * 1024 * 1024)
                PerformanceTier.MID -> b.setBufferDurationsMs(15_000, 40_000, 2_000, 4_000)
                    .setTargetBufferBytes(48 * 1024 * 1024)
                PerformanceTier.HIGH -> b.setBufferDurationsMs(30_000, 60_000, 2_500, 5_000)
            }
            return b.setPrioritizeTimeOverSizeThresholds(false).build()
        }

        fun Subtitle.toMedia3SubtitleConfig(isDefault: Boolean): MediaItem.SubtitleConfiguration {
            val resolvedMime = mimeType ?: when (url.substringBefore('?').substringAfterLast('.', "").lowercase()) {
                "ass", "ssa" -> MimeTypes.TEXT_SSA
                "vtt" -> MimeTypes.TEXT_VTT
                else -> MimeTypes.APPLICATION_SUBRIP
            }
            return MediaItem.SubtitleConfiguration.Builder(Uri.parse(url))
                .setMimeType(resolvedMime)
                .setLanguage(lang)
                .setLabel(lang ?: "外挂字幕")
                .setSelectionFlags(if (isDefault) C.SELECTION_FLAG_DEFAULT else 0)
                .build()
        }
    }
}
