package com.flytech.juying.source.iptv

import android.content.Context
import android.net.Uri
import com.flytech.juying.core.common.Dispatcher
import com.flytech.juying.core.common.JuyingDispatchers
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.network.fetchText
import com.flytech.juying.core.network.await
import com.flytech.juying.core.model.EpgProgram
import com.flytech.juying.source.api.LiveSource
import com.flytech.juying.source.api.SourceProvider
import com.flytech.juying.source.api.playlist.PlaylistParser
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.multibindings.IntoSet
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import javax.inject.Inject
import javax.inject.Provider
import javax.inject.Singleton
import okio.buffer
import okio.source
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/**
 * IPTV 直播数据源实现。
 *
 * **What**: 负责网络订阅（HTTP/HTTPS）及本地文件（`content://`）M3U / TXT 播放列表解析、
 * 频道分组聚合、XMLTV 电子节目单（EPG，支持 gzip 流式解压）按需抓取及多线路备选模型组装。
 *
 * **Why**: 支持同频道多线路故障转移（Failover），上游单线路故障时自动切线；
 * 采用 16MB 流式 Pull 解析与局部时间窗裁剪，防止超大 EPG 文件撑爆低内存盒子。
 */
@Singleton
class IptvSource @Inject constructor(
    private val client: Provider<OkHttpClient>,
    @Dispatcher(JuyingDispatchers.Default) private val defaultDispatcher: CoroutineDispatcher,
    @ApplicationContext private val context: Provider<Context>,
) : LiveSource {
    override val type = SourceType.IPTV
    override val urlSetup = com.flytech.juying.core.model.UrlSourceSetup(type, "IPTV",
        "输入 M3U / TXT 订阅地址，或选择本地列表文件。文件导入后请保留原文件。节目单可自动读取列表声明，也可单独填写 XMLTV 地址。",
        schemes = setOf("http", "https", "content"), fileMimeTypes = listOf("*/*"), epg = true)
    private data class Playlist(val config: SourceConfig, val groups: List<ChannelGroup>, val guide: String?)
    private val playlists = LinkedHashMap<String, Playlist>()
    private val schedules = LinkedHashMap<Pair<SourceConfig, String>, Pair<Long, List<EpgProgram>>>()

    override suspend fun channels(config: SourceConfig): List<ChannelGroup> = withContext(kotlinx.coroutines.Dispatchers.IO) {
        val headers = buildMap {
            config.extra["userAgent"]?.takeIf { it.isNotBlank() }?.let { put("User-Agent", it) }
            config.extra["referer"]?.takeIf { it.isNotBlank() }?.let { put("Referer", it) }
        }
        val text = if (config.url.startsWith("content://")) {
            context.get().contentResolver.openInputStream(Uri.parse(config.url))?.use { input ->
                input.source().buffer().use { source ->
                    require(!source.request(4 * 1024 * 1024 + 1L)) { "Playlist is too large" }
                    source.readUtf8()
                }
            } ?: error("Playlist unavailable")
        } else client.get().fetchText(config.url, headers, maxBytes = 4 * 1024 * 1024L)
        withContext(defaultDispatcher) {
            val groups = PlaylistParser.parse(text).map { group -> group.copy(channels = group.channels.map { channel ->
                channel.copy(lines = channel.lines.map { it.copy(headers = headers + it.headers) })
            }) }
            val declared = Regex("""(?:x-tvg-url|url-tvg)="([^"]+)""", RegexOption.IGNORE_CASE)
                .find(text.lineSequence().firstOrNull().orEmpty())?.groupValues?.get(1)?.substringBefore(',')
            val guide = declared?.toHttpUrlOrNull()?.toString() ?: declared?.let { config.url.toHttpUrlOrNull()?.resolve(it)?.toString() }
            synchronized(playlists) {
                playlists[config.id] = Playlist(config, groups, guide)
                while (playlists.size > 8) playlists.remove(playlists.keys.first())
            }
            groups
        }
    }
    override suspend fun epg(config: SourceConfig, channelId: String): List<EpgProgram> = withContext(kotlinx.coroutines.Dispatchers.IO) {
        val key = config to channelId
        synchronized(schedules) { schedules[key]?.takeIf { System.nanoTime() - it.first < 10 * 60_000_000_000L } }?.let { return@withContext it.second }
        var playlist = synchronized(playlists) { playlists[config.id]?.takeIf { it.config == config } }
        if (playlist == null) { channels(config); playlist = synchronized(playlists) { playlists[config.id] } }
        val guide = config.extra["epgUrl"]?.takeIf { it.isNotBlank() } ?: playlist?.guide ?: return@withContext emptyList()
        require(guide.toHttpUrlOrNull() != null) { "Invalid guide address" }
        val channel = playlist?.groups?.asSequence()?.flatMap { it.channels }?.firstOrNull { it.id == channelId } ?: return@withContext emptyList()
        val request = Request.Builder().url(guide).apply {
            config.extra["userAgent"]?.takeIf(String::isNotBlank)?.let { header("User-Agent", it) }
            config.extra["referer"]?.takeIf(String::isNotBlank)?.let { header("Referer", it) }
        }.build()
        val programmes = client.get().newCall(request).await().use { response ->
            check(response.isSuccessful) { "Guide unavailable" }
            val body = response.body ?: return@withContext emptyList()
            val source = body.source()
            val gzip = source.request(2) && source.buffer[0] == 0x1f.toByte() && source.buffer[1] == 0x8b.toByte()
            val input = if (gzip) java.util.zip.GZIPInputStream(source.inputStream()) else source.inputStream()
            input.use { Xmltv.parse(it, channel.epgId?.takeIf(String::isNotBlank) ?: channel.name, System.currentTimeMillis()) }
        }
        synchronized(schedules) {
            schedules[key] = System.nanoTime() to programmes
            while (schedules.size > 32) schedules.remove(schedules.keys.first())
        }
        programmes
    }
}

/** IPTV 数据源的 Hilt 注入模块。 */
@Module
@InstallIn(SingletonComponent::class)
abstract class IptvModule {
    @Binds @IntoSet
    abstract fun source(impl: IptvSource): SourceProvider
}
