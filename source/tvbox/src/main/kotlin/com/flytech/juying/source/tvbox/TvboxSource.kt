package com.flytech.juying.source.tvbox

import com.flytech.juying.core.common.Dispatcher
import com.flytech.juying.core.common.JuyingDispatchers
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.PlaybackRoute
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.model.SubSource
import com.flytech.juying.core.model.VodCategory
import com.flytech.juying.core.model.VodDetail
import com.flytech.juying.core.model.VodItem
import com.flytech.juying.core.network.fetchText
import com.flytech.juying.core.network.await
import com.flytech.juying.source.api.LiveSource
import com.flytech.juying.source.api.SourceProvider
import com.flytech.juying.source.api.VodSource
import com.flytech.juying.source.api.playlist.PlaylistParser
import com.flytech.juying.source.tvbox.TvboxJson.text
import com.flytech.juying.source.tvbox.config.TvboxConfig
import com.flytech.juying.source.tvbox.config.TvboxConfigParser
import com.flytech.juying.source.tvbox.config.TvboxSite
import com.flytech.juying.source.tvbox.spider.SpiderCall
import com.flytech.juying.source.tvbox.spider.SpiderClient
import com.flytech.juying.source.tvbox.spider.SpiderMethod
import com.flytech.juying.source.tvbox.spider.SpiderSpec
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.add
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import javax.inject.Inject
import javax.inject.Provider
import javax.inject.Singleton

/** 用户配置的 CMS JSON 与 Spider 共用内容协议，UI 无需知道站点的执行语言。 */
@Singleton
class TvboxSource @Inject constructor(
    private val client: Provider<OkHttpClient>,
    @Dispatcher(JuyingDispatchers.Default) private val defaultDispatcher: CoroutineDispatcher,
    private val spiders: Provider<SpiderClient>,
) : LiveSource, VodSource {
    override val type = SourceType.TVBOX
    override fun capabilities(config: SourceConfig) = if (config.extra[CONFIG_SITE_KEY].isNullOrBlank()) capabilities
        else capabilities - com.flytech.juying.core.model.SourceCapability.LIVE
    override val urlSetup = com.flytech.juying.core.model.UrlSourceSetup(type, "TVBox",
        "输入单仓、多仓或 CMS JSON 地址。订阅中的 Jar、JS、Python 会在设备上执行，请只添加可信订阅。")
    private val configs = LinkedHashMap<SourceConfig, CachedConfig>()

    private suspend fun loadConfig(config: SourceConfig): LoadedConfig {
        synchronized(configs) {
            configs[config]?.takeIf { System.nanoTime() - it.loadedAtNanos < CONFIG_TTL_NANOS }?.let { return it.value }
        }
        val (url, document) = configDocument(TvboxJson.httpUrl(config.url))
        val repos = TvboxConfigParser.parseRepoList(document.toString())
        val repoUrl = if (repos != null) {
            val preferred = config.extra[CONFIG_REPO_URL]
            repos.firstOrNull { TvboxJson.httpUrl(it.url, url) == preferred }?.url ?: repos.first().url
        } else null
        val (baseUrl, root) = if (repoUrl == null) url to document else configDocument(TvboxJson.httpUrl(repoUrl, url))
        val parsed = withContext(defaultDispatcher) {
            if ("sites" !in root && ("class" in root || "list" in root)) {
                TvboxConfig(sites = listOf(TvboxSite(DIRECT_CMS_SITE, config.name, TvboxSiteType.CMS_JSON.code, baseUrl)))
            } else TvboxConfigParser.parse(root.toString())
        }
        require(parsed.sites.all { it.key.isNotBlank() && it.api.isNotBlank() }) { "TVBox 站点缺少 key 或 api" }
        require(parsed.sites.distinctBy { it.key }.size == parsed.sites.size) { "TVBox 站点 key 重复" }
        val loaded = LoadedConfig(baseUrl, parsed)
        synchronized(configs) {
            configs.keys.filter { it.id == config.id }.forEach { configs.remove(it) }
            configs[config] = CachedConfig(loaded, System.nanoTime())
            while (configs.size > CONFIG_CACHE_SIZE) configs.remove(configs.keys.first())
        }
        return loaded
    }

    override suspend fun subSources(config: SourceConfig): List<SubSource> =
        loadConfig(config).value.sites.filter { config.extra[CONFIG_SITE_KEY].isNullOrBlank() || it.key == config.extra[CONFIG_SITE_KEY] }
            .map { SubSource(it.key, it.name.ifBlank { it.key }, it.searchable != SEARCH_DISABLED) }

    override suspend fun channels(config: SourceConfig): List<ChannelGroup> {
        val loaded = loadConfig(config)
        val live = loaded.value.lives.firstOrNull { it.url.isNotBlank() } ?: return emptyList()
        val headers = live.ua?.let { mapOf("User-Agent" to it) }.orEmpty()
        val text = fetch(TvboxJson.httpUrl(live.url, loaded.baseUrl), headers)
        return withContext(defaultDispatcher) { PlaylistParser.parse(text) }
    }

    override suspend fun categories(config: SourceConfig): List<VodCategory> = categories(config, null)

    override suspend fun categories(config: SourceConfig, subSourceId: String?): List<VodCategory> {
        val loaded = loadConfig(config)
        val site = loaded.site(config, subSourceId)
        val response = request(loaded, site, SpiderMethod.HOME, buildJsonArray { add(false) })
        return withContext(defaultDispatcher) { TvboxJson.categories(response, site.key) }
    }

    override suspend fun list(config: SourceConfig, categoryId: String, page: Int): List<VodItem> =
        listPage(config, categoryId, page).items

    override suspend fun listPage(config: SourceConfig, categoryId: String, page: Int): com.flytech.juying.core.model.VodPage {
        require(page >= FIRST_PAGE) { "页码必须大于零" }
        val ref = TvboxItemRef.decode(categoryId)
        val loaded = loadConfig(config)
        val site = loaded.site(config, ref.siteKey)
        val body = request(loaded, site, SpiderMethod.CATEGORY, buildJsonArray {
            add(ref.id); add(page.toString()); add(false); add(JsonObject(emptyMap()))
        })
        return withContext(defaultDispatcher) {
            val response = TvboxJson.response(body)
            com.flytech.juying.core.model.VodPage(TvboxJson.videos(response).map { it.item(config.id, site.key) },
                TvboxJson.hasMore(response, page))
        }
    }

    override suspend fun detail(config: SourceConfig, itemId: String): VodDetail {
        val ref = TvboxItemRef.decode(itemId)
        val loaded = loadConfig(config)
        val site = loaded.site(config, ref.siteKey)
        return video(loaded, site, ref.id).detail(config.id, site.key)
    }

    override suspend fun search(config: SourceConfig, keyword: String, page: Int): List<VodItem> =
        search(config, keyword, page, null)

    override suspend fun search(config: SourceConfig, keyword: String, page: Int, subSourceId: String?): List<VodItem> {
        require(page >= FIRST_PAGE) { "页码必须大于零" }
        if (keyword.isBlank()) return emptyList()
        val loaded = loadConfig(config)
        val site = loaded.site(config, subSourceId)
        if (site.searchable == SEARCH_DISABLED) return emptyList()
        val body = request(loaded, site, SpiderMethod.SEARCH, buildJsonArray {
            add(keyword.trim()); add(false); add(page.toString())
        })
        return items(body, config, site)
    }

    override suspend fun resolve(config: SourceConfig, episodeRef: String): PlayItem {
        val ref = TvboxEpisodeRef.decode(episodeRef)
        val loaded = loadConfig(config)
        val site = loaded.site(config, ref.item.siteKey)
        val video = video(loaded, site, ref.item.id)
        val group = video.groups.singleOrNull { it.name == ref.groupName } ?: error("播放线路已变化，请重新选集")
        val episode = group.episodes.getOrNull(ref.episodeIndex)?.takeIf { it.name == ref.episodeName }
            ?: group.episodes.singleOrNull { it.name == ref.episodeName }
            ?: error("分集已变化，请重新选集")
        var url = episode.playId
        var headers = TvboxJson.headers(site.header)
        var route = PlaybackRoute.NATIVE
        if (TvboxSiteType.fromCode(site.type) in setOf(TvboxSiteType.SPIDER, TvboxSiteType.HTTP_SPIDER)) {
            val playback = TvboxJson.response(request(loaded, site, SpiderMethod.PLAYER, buildJsonArray {
                add(group.name); add(episode.playId); add(buildJsonArray { loaded.value.flags.forEach { add(it) } })
            }))
            url = playback.text("url") ?: error("站点未返回播放地址")
            headers = headers + TvboxJson.headers(playback["header"] ?: playback["headers"])
            if (playback.text("parse") == PARSE_WEB || playback.text("jx") == PARSE_WEB) route = PlaybackRoute.WEB
        }
        if (route == PlaybackRoute.WEB) {
            TvboxJsonPlayback.resolve(client.get(), loaded.value.parses, loaded.baseUrl,
                group.name, TvboxJson.httpUrl(url, loaded.baseUrl), headers)?.let { resolved ->
                url = resolved.url
                headers = resolved.headers
                route = PlaybackRoute.NATIVE
            }
        }
        return PlayItem(
            id = episodeRef, title = "${video.title} · ${episode.name}",
            url = TvboxJson.httpUrl(url, loaded.baseUrl), headers = headers, route = route,
        )
    }

    private suspend fun video(loaded: LoadedConfig, site: TvboxSite, id: String): TvboxVideo {
        val response = request(loaded, site, SpiderMethod.DETAIL, buildJsonArray { add(buildJsonArray { add(id) }) })
        return withContext(defaultDispatcher) {
            TvboxJson.videos(response).firstOrNull { it.id == id } ?: error("该内容已失效或没有详情")
        }
    }

    private suspend fun items(body: String, config: SourceConfig, site: TvboxSite): List<VodItem> =
        withContext(defaultDispatcher) { TvboxJson.videos(body).map { it.item(config.id, site.key) } }

    private suspend fun request(loaded: LoadedConfig, site: TvboxSite, method: SpiderMethod, args: JsonArray): String {
        val siteType = TvboxSiteType.fromCode(site.type)
        if (siteType == TvboxSiteType.SPIDER) {
            val language = site.spiderLanguage()
            val jar = (site.jar ?: loaded.value.spider)?.let { value ->
                val parts = value.split(JAR_HASH_SEPARATOR, limit = 2)
                TvboxJson.httpUrl(parts.first(), loaded.baseUrl) +
                    (parts.getOrNull(1)?.let { JAR_HASH_SEPARATOR + it } ?: "")
            }
            val spec = SpiderSpec(
                key = site.key, language = language,
                api = if (language == SpiderLanguage.JAR) site.api else TvboxJson.httpUrl(site.api, loaded.baseUrl),
                jar = jar, ext = site.ext ?: JsonNull,
            )
            return spiders.get().call(SpiderCall(spec, method, args))
        }
        val action = if (siteType == TvboxSiteType.CMS_XML) "videolist" else "detail"
        val url = TvboxJson.httpUrl(site.api, loaded.baseUrl).toHttpUrl().newBuilder()
        val parameters = when (method) {
            SpiderMethod.HOME -> emptyMap()
            SpiderMethod.CATEGORY -> mapOf("ac" to action, "t" to args[0].jsonPrimitive.content, "pg" to args[1].jsonPrimitive.content)
            SpiderMethod.DETAIL -> mapOf("ac" to action, "ids" to args[0].jsonArray[0].jsonPrimitive.content)
            SpiderMethod.SEARCH -> mapOf("ac" to action, "wd" to args[0].jsonPrimitive.content, "pg" to args[2].jsonPrimitive.content)
            SpiderMethod.PLAYER -> mapOf("play" to args[1].jsonPrimitive.content, "flag" to args[0].jsonPrimitive.content)
        }
        parameters.forEach { (key, value) -> url.setQueryParameter(key, value) }
        if (siteType == TvboxSiteType.HTTP_SPIDER && site.ext != null) url.setQueryParameter("extend", site.ext.toString())
        val response = fetch(url.build().toString(), TvboxJson.headers(site.header))
        return if (siteType == TvboxSiteType.CMS_XML) withContext(defaultDispatcher) { TvboxXml.response(response) } else response
    }

    private suspend fun fetch(url: String, headers: Map<String, String> = emptyMap()): String =
        withContext(defaultDispatcher) {
            client.get().fetchText(url, headers, maxBytes = RESPONSE_MAX_BYTES)
        }

    private suspend fun configDocument(url: String): Pair<String, JsonObject> = withContext(kotlinx.coroutines.Dispatchers.IO) {
        client.get().newCall(okhttp3.Request.Builder().url(url).build()).await().use { response ->
            check(response.isSuccessful) { "订阅 HTTP ${response.code}" }
            val body = checkNotNull(response.body) { "订阅为空" }
            require(body.contentLength() <= RESPONSE_MAX_BYTES) { "订阅过大" }
            val source = body.source()
            require(!source.request(RESPONSE_MAX_BYTES + 1)) { "订阅过大" }
            val finalUrl = response.request.url.toString()
            finalUrl to TvboxConfigParser.document(source.readUtf8(), finalUrl)
        }
    }

    private data class LoadedConfig(val baseUrl: String, val value: TvboxConfig) {
        fun site(config: SourceConfig, id: String?): TvboxSite {
            val selected = id ?: config.extra[CONFIG_SITE_KEY]
            return if (selected == null) value.sites.firstOrNull() ?: error("配置中没有点播站点")
            else value.sites.firstOrNull { it.key == selected } ?: error("站点已移除，请重新选择")
        }
    }
    private data class CachedConfig(val value: LoadedConfig, val loadedAtNanos: Long)

    private companion object {
        const val CONFIG_REPO_URL = "repoUrl"
        const val CONFIG_SITE_KEY = "siteKey"
        const val DIRECT_CMS_SITE = "cms"
        const val CONFIG_TTL_NANOS = 5L * 60 * 1_000_000_000
        const val CONFIG_CACHE_SIZE = 4
        const val RESPONSE_MAX_BYTES = 2L * 1024 * 1024
        const val FIRST_PAGE = 1
        const val SEARCH_DISABLED = 0
        const val PARSE_WEB = "1"
        const val JAR_HASH_SEPARATOR = ";md5;"
    }
}

@Module
@InstallIn(SingletonComponent::class)
abstract class TvboxModule {
    @Binds @IntoSet
    abstract fun source(impl: TvboxSource): SourceProvider
}
