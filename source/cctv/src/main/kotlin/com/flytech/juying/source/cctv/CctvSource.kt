package com.flytech.juying.source.cctv

import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.Episode
import com.flytech.juying.core.model.PlayGroup
import com.flytech.juying.core.common.Dispatcher
import com.flytech.juying.core.common.JuyingDispatchers
import com.flytech.juying.core.network.fetchText
import com.flytech.juying.core.network.await
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.model.VodCategory
import com.flytech.juying.core.model.VodDetail
import com.flytech.juying.core.model.VodItem
import com.flytech.juying.source.api.LiveSource
import com.flytech.juying.source.api.SourceDiscoveryProvider
import com.flytech.juying.source.api.SourceProvider
import com.flytech.juying.source.api.VodSource
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonObject
import com.flytech.juying.source.cctv.CctvJson.number
import com.flytech.juying.source.cctv.CctvJson.text
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Provider
import javax.inject.Singleton

const val BUILTIN_CCTV_ID = "builtin-cctv"

/** 央视内置源：直播（tv.cctv.com/live）+ 点播电视剧（tv.cctv.com/yxg），通过 [SourceDiscoveryProvider] 自动注册。 */
@Singleton
class CctvSource @Inject constructor(
    private val client: Provider<OkHttpClient>,
    @Dispatcher(JuyingDispatchers.Default) private val defaultDispatcher: CoroutineDispatcher,
) : LiveSource, VodSource, SourceDiscoveryProvider {

    override val type = SourceType.CCTV
    private val albums = LinkedHashMap<String, CctvAlbum>()

    override fun observeDiscoveredSources(): Flow<List<SourceConfig>> = flowOf(
        listOf(
            SourceConfig(
                id = BUILTIN_CCTV_ID,
                name = "央视",
                type = SourceType.CCTV,
                url = "",
                isReadOnly = true,
            ),
        ),
    )

    // ---------- 直播 ----------
    override suspend fun channels(config: SourceConfig): List<ChannelGroup> =
        listOf(ChannelGroup("央视", CctvChannels.ALL.map { (id, name) -> Channel(id = id, name = name, logo = CctvChannels.logo(id)) }))

    override suspend fun resolve(config: SourceConfig, channel: Channel): PlayItem {
        require(CctvChannels.ALL.any { it.first == channel.id }) { "央视频道不存在" }
        val slug = when (channel.id) {
            "cctv9" -> "cctvjilu"
            "cctv14" -> "cctvchild"
            else -> channel.id
        }
        val timestamp = System.currentTimeMillis()
        val nonce = Math.round(Math.random() * LIVE_NONCE_RANGE).let {
            if (it < LIVE_NONCE_MIN) it + LIVE_NONCE_MIN else it
        }
        // 与官网 liveplayer.js 的 VDN v3 请求一致；签名只用于解析，不传给媒体 CDN。
        val digest = MessageDigest.getInstance("MD5")
            .digest("$slug$timestamp$nonce$LIVE_AUTH_SEED".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        val headers = REQUEST_HEADERS + ("Referer" to "${OFFICIAL_SITE}live/$slug/index.shtml")
        val url = LIVE_VDN_API.toHttpUrl().newBuilder().addQueryParameter("channel", slug)
            .addQueryParameter("vn", "1").addQueryParameter("pdrm", "1")
            .addQueryParameter("uid", "").addQueryParameter("hbss", timestamp.toString()).build()
        val response = withContext(defaultDispatcher) {
            CctvJson.format.parseToJsonElement(client.get().fetchText(url.toString(),
                headers + ("auth-key" to "$timestamp-$nonce-$digest"), MAX_JSON_BYTES)) as? JsonObject
                ?: error("央视直播接口返回格式异常")
        }
        check(response.text("ack") == "yes" && response.text("play") == "1") {
            "该央视频道当前暂不可播放"
        }
        val master = (response["manifest"] as? JsonObject)?.text("hls_cdrm")?.takeIf { it.isNotBlank() }
            ?: error("该央视频道未提供原生高清线路")
        highestHd(master, headers) // 先验证高清可用，再保留总清单供播放器切换各档画质。
        return PlayItem(channel.id, channel.name, CctvH5ePlaylist.wrap(master, live = true), headers,
            isLive = true, preferHighestVideoQuality = true)
    }

    override suspend fun categories(config: SourceConfig): List<VodCategory> =
        CctvCategory.entries.map { VodCategory(it.name, it.label) }

    override suspend fun list(config: SourceConfig, categoryId: String, page: Int): List<VodItem> =
        loadAlbums(CctvCategory.valueOf(categoryId), page).map { it.toItem(config.id) }

    private suspend fun loadAlbums(category: CctvCategory, page: Int, letter: String? = null): List<CctvAlbum> {
        require(page >= 1)
        val parameters = mutableMapOf("fc" to category.apiName, "p" to page.toString(),
            "n" to ALBUM_PAGE_SIZE.toString(), "topv" to "1", "t" to "json")
        letter?.let { parameters["letter"] = it }
        val result = CctvJson.albums(api("list/getVideoAlbumList", parameters))
        synchronized(albums) {
            result.forEach { albums[it.id] = it }
            while (albums.size > ALBUM_CACHE_SIZE) albums.remove(albums.keys.first())
        }
        return result
    }

    override suspend fun detail(config: SourceConfig, itemId: String): VodDetail {
        require(itemId.isNotBlank())
        val cached = synchronized(albums) { albums[itemId] }
        var episodes = loadEpisodes(itemId, false)
        if (episodes.isEmpty()) {
            val vsetId = cached?.vsetId ?: itemId.takeIf { it.startsWith("VSET") }
            if (vsetId != null) episodes = loadEpisodes(vsetId, true)
        }
        val main = CctvJson.mainEpisodes(episodes)
        check(main.isNotEmpty()) { "该央视专辑暂无可播放分集" }
        val item = cached?.toItem(config.id) ?: VodItem(itemId, config.id,
            Regex("[《〈](.*?)[》〉]").find(main.first().title)?.groupValues?.get(1) ?: main.first().title,
            main.first().cover)
        return VodDetail(item, cached?.description, cached?.year, cached?.area,
            listOf(CctvPlayback.NATIVE_HD, CctvPlayback.STANDARD).map { playback ->
                PlayGroup(playback.label,
                    main.map { episode ->
                        val ref = CctvEpisodeRef(episode.guid, episode.pageUrl, episode.title, playback)
                        Episode(episode.title, CctvJson.format.encodeToString(ref),
                            if (playback == CctvPlayback.NATIVE_HD) listOf(CctvJson.format.encodeToString(
                                ref.copy(playback = CctvPlayback.OFFICIAL))) else emptyList())
                    })
            })
    }

    private suspend fun loadEpisodes(id: String, legacy: Boolean): List<CctvEpisode> {
        val episodes = linkedMapOf<String, CctvEpisode>()
        for (page in 1..MAX_EPISODE_PAGES) {
            val data = api(if (legacy) "NewVideo/getVideoListByVsetId" else "NewVideo/getVideoListByAlbumIdNew",
                mapOf((if (legacy) "vsetId" else "id") to id, "pub" to "1",
                    "p" to page.toString(), "n" to EPISODE_PAGE_SIZE.toString()))
            val rows = CctvJson.episodes(data)
            val before = episodes.size
            rows.forEach { episodes.putIfAbsent(it.guid, it) }
            val total = data.number("total")
            if (total != null && episodes.size >= total) return episodes.values.toList()
            if (rows.isEmpty() || episodes.size == before) {
                check(total == null || episodes.size >= total) { "央视分集分页未完成，请稍后重试" }
                return episodes.values.toList()
            }
            if (total == null && rows.size < EPISODE_PAGE_SIZE) return episodes.values.toList()
        }
        error("央视专辑超过分页上限")
    }

    override suspend fun search(config: SourceConfig, keyword: String, page: Int): List<VodItem> = coroutineScope {
        val query = keyword.trim()
        if (query.isEmpty()) return@coroutineScope emptyList()
        val letter = query.takeIf { it.length == 1 && it[0].isLetter() && it[0].code < ASCII_LIMIT }?.uppercase()
        val semaphore = Semaphore(SEARCH_CONCURRENCY)
        // 延续旧版的目录检索语义；接口没有全文搜索参数，每页查询各分类的同一目录页。
        CctvCategory.entries.map { category -> async {
            semaphore.withPermit { loadAlbums(category, page, letter) }
                .filter { letter != null || it.title.contains(query, true) || it.actors.contains(query, true) }
                .map { it.toItem(config.id) }
        } }.awaitAll().flatten().distinctBy { it.id }
    }

    override suspend fun resolve(config: SourceConfig, episodeRef: String): PlayItem {
        val ref = CctvJson.format.decodeFromString<CctvEpisodeRef>(episodeRef)
        require(ref.guid.isNotBlank()) { "缺少央视视频 GUID" }
        val url = VDN_API.toHttpUrl().newBuilder().addQueryParameter("pid", ref.guid)
            .addQueryParameter("tz", "-8").addQueryParameter("from", "000news").build()
        val response = withContext(defaultDispatcher) {
            CctvJson.format.parseToJsonElement(client.get().fetchText(url.toString(), REQUEST_HEADERS, MAX_JSON_BYTES)) as? JsonObject
                ?: error("央视播放接口返回格式异常")
        }
        // 旧历史的 OFFICIAL 引用继续解析原生高清，不再打开点播网页。
        if (ref.playback != CctvPlayback.STANDARD) {
            val manifest = response["manifest"] as? JsonObject
            val master = manifest?.text("hls_h5e_url")?.takeIf { it.isNotBlank() }
                ?: error("该节目未提供原生高清线路，请尝试其他节目")
            val media = highestHd(master, REQUEST_HEADERS)
            return PlayItem(ref.guid, ref.title, CctvH5ePlaylist.wrap(media), REQUEST_HEADERS)
        }
        val hls = response.text("hls_url").toHttpUrl()
        return PlayItem(ref.guid, "${ref.title} · 官方标清", hls.toString(), REQUEST_HEADERS)
    }

    private suspend fun highestHd(master: String, headers: Map<String, String>): String = withContext(defaultDispatcher) {
        client.get().newCall(okhttp3.Request.Builder().url(master).apply {
            headers.forEach { (name, value) -> header(name, value) }
        }.build()).await().use { result ->
            check(result.isSuccessful) { "央视高清清单请求失败：HTTP ${result.code}" }
            val body = checkNotNull(result.body) { "央视高清清单为空" }
            require(body.contentLength() <= CctvH5ePlaylist.MAX_PLAYLIST_BYTES &&
                !body.source().request(CctvH5ePlaylist.MAX_PLAYLIST_BYTES + 1)) { "央视高清清单过大" }
            CctvH5ePlaylist.highestHd(body.string(), result.request.url.toString())
        }
    }

    private suspend fun api(path: String, parameters: Map<String, String>): JsonObject = withContext(defaultDispatcher) {
        val url = (API_BASE + path).toHttpUrl().newBuilder().addQueryParameter("serviceId", "tvcctv")
            .apply { parameters.forEach { (key, value) -> addQueryParameter(key, value) } }.build()
        CctvJson.data(client.get().fetchText(url.toString(), REQUEST_HEADERS, MAX_JSON_BYTES))
    }

    private fun CctvAlbum.toItem(sourceId: String) = VodItem(id, sourceId, title, cover,
        listOfNotNull(year, area).joinToString(" · "))

    private companion object {
        const val API_BASE = "https://api.cntv.cn/"
        const val VDN_API = "https://vdn.apps.cntv.cn/api/getHttpVideoInfo.do"
        const val LIVE_VDN_API = "https://vdnx.live.cntv.cn/api/v3/vdn/live"
        // 官网桌面 VDN v3 签名参数，来自 liveplayer.js 2026.10.21.01。
        const val LIVE_AUTH_SEED = "a4220a71b31746908fa3e7fdd7a6852a"
        const val LIVE_NONCE_RANGE = 1000
        const val LIVE_NONCE_MIN = 100
        const val OFFICIAL_SITE = "https://tv.cctv.com/"
        const val ALBUM_PAGE_SIZE = 24
        const val EPISODE_PAGE_SIZE = 100
        const val MAX_EPISODE_PAGES = 100
        const val ALBUM_CACHE_SIZE = 256
        const val SEARCH_CONCURRENCY = 2
        const val ASCII_LIMIT = 128
        const val MAX_JSON_BYTES = 2L * 1024 * 1024
        val REQUEST_HEADERS = mapOf("Referer" to OFFICIAL_SITE, "User-Agent" to
            "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36")
    }
}

/** 央视官方内置电视频道列表静态配置。 */
internal object CctvChannels {
    // 官网各频道首页的高清台标；首页和直播页直接消费模型，不识别 CCTV 类型。
    fun logo(id: String): String = requireNotNull(logos[id])

    private val logos = mapOf(
        "cctv1" to "https://p3.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/18/1647586299749_488.png",
        "cctv2" to "https://p3.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/22/1647930311577_599.png",
        "cctv3" to "https://p1.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/18/1647589588472_235.png",
        "cctv4" to "https://p2.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/18/1647589706482_695.png",
        "cctv5" to "https://p2.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/21/1647846719088_381.png",
        "cctv5plus" to "https://p4.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/21/1647846841376_750.png",
        "cctv6" to "https://p3.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/18/1647597091565_512.png",
        "cctv7" to "https://p3.img.cctvpic.com/photoAlbum/page/performance/img/2022/6/10/1654828698005_552.png",
        "cctv8" to "https://p3.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/18/1647597522993_467.png",
        "cctv9" to "https://p2.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/18/1647597680980_785.png",
        "cctv10" to "https://p2.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/21/1647844669705_491.png",
        "cctv11" to "https://p5.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/18/1647594081178_564.png",
        "cctv12" to "https://p2.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/22/1647931672491_366.png",
        "cctv13" to "https://p2.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/30/1648609564977_591.png",
        "cctv14" to "https://p3.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/18/1647592530516_684.png",
        "cctv15" to "https://p4.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/18/1647592242802_151.png",
        "cctv16" to "https://p4.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/21/1647848501711_626.png",
        "cctv17" to "https://p3.img.cctvpic.com/photoAlbum/page/performance/img/2022/3/22/1647933216133_756.png",
    )

    val ALL = listOf(
        "cctv1" to "CCTV-1 综合", "cctv2" to "CCTV-2 财经", "cctv3" to "CCTV-3 综艺",
        "cctv4" to "CCTV-4 国际", "cctv5" to "CCTV-5 体育", "cctv5plus" to "CCTV-5+ 体育赛事",
        "cctv6" to "CCTV-6 电影", "cctv7" to "CCTV-7 国防军事", "cctv8" to "CCTV-8 电视剧",
        "cctv9" to "CCTV-9 纪录", "cctv10" to "CCTV-10 科教", "cctv11" to "CCTV-11 戏曲",
        "cctv12" to "CCTV-12 社会与法", "cctv13" to "CCTV-13 新闻", "cctv14" to "CCTV-14 少儿",
        "cctv15" to "CCTV-15 音乐", "cctv16" to "CCTV-16 奥林匹克", "cctv17" to "CCTV-17 农业农村",
    )
}

/** 央视数据源的 Hilt 注入模块。 */
@Module
@InstallIn(SingletonComponent::class)
abstract class CctvModule {
    @Binds @IntoSet
    abstract fun source(impl: CctvSource): SourceProvider

    @Binds @IntoSet
    abstract fun discovery(impl: CctvSource): SourceDiscoveryProvider
}
