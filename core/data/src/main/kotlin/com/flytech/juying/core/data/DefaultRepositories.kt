package com.flytech.juying.core.data

import android.content.Context
import com.flytech.juying.core.common.Dispatcher
import com.flytech.juying.core.common.JuyingDispatchers
import com.flytech.juying.core.database.FavoriteDao
import com.flytech.juying.core.database.FavoriteEntity
import com.flytech.juying.core.database.HistoryDao
import com.flytech.juying.core.database.HistoryDbEntity
import com.flytech.juying.core.database.SourceDao
import com.flytech.juying.core.database.SourceEntity
import com.flytech.juying.core.datastore.SettingsDataSource
import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.DecoderMode
import com.flytech.juying.core.model.FavoriteEntry
import com.flytech.juying.core.model.FileEntry
import com.flytech.juying.core.model.HistoryEntry
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.PlayKind
import com.flytech.juying.core.model.PlayLine
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.model.SubSource
import com.flytech.juying.core.model.VodCategory
import com.flytech.juying.core.model.VodDetail
import com.flytech.juying.core.model.VodItem
import com.flytech.juying.core.model.DeviceProfile
import com.flytech.juying.core.model.PerformanceTier
import com.flytech.juying.core.model.SearchTarget
import com.flytech.juying.core.model.SearchOutcome
import com.flytech.juying.core.model.SearchUpdate
import com.flytech.juying.source.api.VodSource
import com.flytech.juying.source.api.SourceDiscoveryProvider
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import timber.log.Timber
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 统一数据源仓储实现。
 *
 * **What**: 协调本地持久化数据源（Room [SourceDao]）与网络/外设动态发现数据源（[SourceDiscoveryProvider]），
 * 负责预置源的一次性安装、密码与敏感令牌加解密（[SourceSecrets]）以及基于能力契约（[SourceCapability]）的合流分发。
 *
 * **Why**: 抹平静态配置源与动态热插拔源（如 USB 插入、局域网 SSDP/mDNS 广播）的差异，
 * 为 UI 层提供统一的单向 Flow 数据流。
 */
@Singleton
class DefaultSourceRepository @Inject constructor(
    private val dao: SourceDao,
    private val registry: SourceRegistry,
    private val discoveryProviders: @JvmSuppressWildcards Set<SourceDiscoveryProvider>,
    @ApplicationContext private val context: Context,
    private val secrets: SourceSecrets,
    private val presets: @JvmSuppressWildcards Set<SourceConfig>,
    private val settings: SettingsDataSource,
) : SourceRepository {
    private val presetLock = Mutex()
    override fun capabilities(config: SourceConfig) = registry.capabilitiesOf(config)
    override fun urlSetups() = registry.urlSetups()

    override fun discoverNetworkStorage() = channelFlow {
        registry.networkStorage().forEach { provider -> launch { provider.discoverDevices().collect { send(it) } } }
    }

    override fun networkDevice(address: String) = registry.networkStorage().firstOrNull()?.manualDevice(address)
        ?: error("Network storage unavailable")

    override suspend fun networkShares(device: com.flytech.juying.core.model.NetworkStorageDevice, username: String, password: String, domain: String) =
        registry.networkStorage(device.type).shares(device, username, password, domain)

    override fun networkConfiguration(device: com.flytech.juying.core.model.NetworkStorageDevice, share: String, username: String, password: String, domain: String) =
        registry.networkStorage(device.type).configuration(device, share, username, password, domain)

    private fun observeAllMerged(): Flow<List<SourceConfig>> {
        val dbFlow = dao.observeAll().onStart {
            // 仅首次后台使用时写入；记录已安装 ID，用户删除后不再恢复。
            presetLock.withLock {
                val installed = settings.installedSourcePresets.first()
                for (preset in presets.filter { it.id !in installed }) {
                    dao.insertPreset(protect(preset.toEntity()))
                    settings.markSourcePresetInstalled(preset.id)
                }
            }
        }.map { rows ->
            val list = rows.mapNotNull { read(it) }
            val smbStorage = registry.networkStorage().firstOrNull { it.type == SourceType.SMB }
            if (smbStorage != null) {
                list.map { cfg ->
                    if (cfg.type == SourceType.SMB) {
                        val host = runCatching { java.net.URI(cfg.url).host }.getOrNull()
                        if (host != null && host in cfg.name) {
                            val resolved = smbStorage.resolveHostname(host)
                            if (!resolved.isNullOrBlank() && resolved != host) {
                                val updated = cfg.copy(name = cfg.name.replace(host, resolved))
                                dao.upsert(protect(updated.toEntity()))
                                updated
                            } else cfg
                        } else cfg
                    } else cfg
                }
            } else list
        }.flowOn(kotlinx.coroutines.Dispatchers.IO)
        if (discoveryProviders.isEmpty()) {
            return dbFlow
        }
        val discoveredFlows = discoveryProviders.map { it.observeDiscoveredSources() }
        return combine(discoveredFlows + dbFlow) { arrays ->
            val merged = LinkedHashMap<String, SourceConfig>()
            for (list in arrays) {
                list.forEach { cfg -> merged[cfg.id] = cfg }
            }
            merged.values.toList()
        }
    }

    override fun observeSources(capability: SourceCapability?): Flow<List<SourceConfig>> =
        observeAllMerged().map { list ->
            if (capability == null) {
                list
            } else {
                list.filter { it.enabled && capability in capabilities(it) }
            }
        }

    override suspend fun get(id: String): SourceConfig? {
        withContext(kotlinx.coroutines.Dispatchers.IO) { dao.get(id)?.let { read(it) } }?.let { return it }
        return observeAllMerged().firstOrNull()?.firstOrNull { it.id == id }
    }

    override suspend fun check(config: SourceConfig): Int = kotlinx.coroutines.withTimeout(20_000) {
        when {
            registry.supportsVod(config.type) -> registry.vod(config.type).let { provider ->
                provider.subSources(config).takeIf { it.isNotEmpty() }?.size ?: provider.categories(config).size
            }
            registry.supportsLive(config.type) -> registry.live(config.type).channels(config).sumOf { it.channels.size }
            registry.supportsBrowse(config.type) -> registry.browse(config.type).list(config, "").size
            else -> error("Source unavailable")
        }
    }
    override suspend fun upsert(config: SourceConfig) = withContext(kotlinx.coroutines.Dispatchers.IO) {
        if (config.url.startsWith("content://")) {
            context.contentResolver.takePersistableUriPermission(android.net.Uri.parse(config.url), android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        dao.upsert(protect(config.toEntity()))
    }
    override suspend fun delete(id: String) = dao.delete(id)

    private fun protect(row: SourceEntity): SourceEntity = row.copy(
        url = secrets.encrypt(row.url, "${row.id}:url"),
        username = row.username?.let { secrets.encrypt(it, "${row.id}:username") },
        password = row.password?.let { secrets.encrypt(it, "${row.id}:password") },
        extraJson = secrets.encrypt(row.extraJson, "${row.id}:extra"),
    )

    private suspend fun read(row: SourceEntity): SourceConfig? {
        val plain = row.copy(url = secrets.decrypt(row.url, "${row.id}:url"),
            username = row.username?.let { secrets.decrypt(it, "${row.id}:username") },
            password = row.password?.let { secrets.decrypt(it, "${row.id}:password") },
            extraJson = secrets.decrypt(row.extraJson, "${row.id}:extra"))
        if (!secrets.isEncrypted(row.url) || !secrets.isEncrypted(row.extraJson) ||
            row.username?.let { !secrets.isEncrypted(it) } == true || row.password?.let { !secrets.isEncrypted(it) } == true) {
            val encrypted = protect(plain)
            dao.protect(row.id, encrypted.url, encrypted.username, encrypted.password, encrypted.extraJson,
                row.url, row.username, row.password, row.extraJson)
        }
        return plain.toModelOrNull()
    }
}

private fun SourceEntity.toModelOrNull(): SourceConfig? {
    val parsedType = runCatching { SourceType.valueOf(type) }.getOrNull() ?: return null
    val extraMap = runCatching {
        val obj = JSONObject(extraJson)
        buildMap {
            val keys = obj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                put(k, obj.optString(k, ""))
            }
        }
    }.getOrDefault(emptyMap())
    return SourceConfig(
        id = id,
        name = name,
        type = parsedType,
        url = url,
        enabled = enabled,
        username = username,
        password = password,
        extra = extraMap,
    )
}

private fun SourceConfig.toEntity(): SourceEntity {
    val extraJson = JSONObject(extra).toString()
    return SourceEntity(
        id = id,
        name = name,
        type = type.name,
        url = url,
        enabled = enabled,
        username = username,
        password = password,
        extraJson = extraJson,
    )
}

/**
 * 直播仓储实现。
 *
 * **What**: 负责频道分组、EPG 电子节目单查询以及直播真实播放流（含鉴权头与备用线路）解析。
 *
 * **Why**: 采用 Offline-First 双层缓存策略（内存 + 磁盘快照），保证电视机顶盒或低配设备冷启动秒开、
 * 弱网/断网环境下仍可立即展示频道列表，后台异步刷新成功后再静默更新。
 */
@Singleton
class DefaultLiveRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val registry: SourceRegistry,
    private val sources: SourceRepository,
    @Dispatcher(JuyingDispatchers.IO) private val io: CoroutineDispatcher,
    private val secrets: SourceSecrets,
) : LiveRepository {

    // NIA Offline-First 双层缓存：内存缓存 + 磁盘快照，保证冷启动秒开频道列表且断网可用。
    private val cache = java.util.Collections.synchronizedMap(LinkedHashMap<SourceConfig, List<ChannelGroup>>(8, 0.75f, true))
    private val diskCacheDir: File by lazy { File(context.cacheDir, "live_channels").apply { mkdirs() } }

    override fun channelGroups(sourceId: String): Flow<List<ChannelGroup>> = flow {
        val config = sources.get(sourceId) ?: error("数据源不存在")
        val mem = cache[config]
        if (mem != null) {
            emit(mem)
        } else {
            readDiskCache(config)?.takeIf { it.isNotEmpty() }?.let { diskGroups ->
                remember(config, diskGroups)
                emit(diskGroups)
            }
        }
        try {
            val fresh = registry.live(config.type).channels(config)
            if (fresh != cache[config]) {
                remember(config, fresh)
                emit(fresh)
                writeDiskCache(config, fresh)
            }
        } catch (t: Throwable) {
            if (t is CancellationException) throw t
            // 若已有缓存数据展示，后台刷新失败仅记录日志，不覆盖已渲染的频道列表
            if (cache[config].isNullOrEmpty()) throw t
            Timber.w("Live refresh failed: %s; keeping cached channels", t.javaClass.simpleName)
        }
    }.flowOn(io)

    private fun remember(config: SourceConfig, groups: List<ChannelGroup>) = synchronized(cache) {
        cache.keys.filter { it.id == config.id }.forEach { cache.remove(it) }
        cache[config] = groups
        while (cache.size > 8) cache.remove(cache.keys.first())
    }

    private fun cacheFile(config: SourceConfig): File {
        // 地址、凭据或请求头变更后，不得把旧线路作为新来源的缓存展示。
        val digest = java.security.MessageDigest.getInstance("SHA-256").digest(config.toEntity().toString().toByteArray())
            .joinToString("") { "%02x".format(it) }
        return File(diskCacheDir, "$digest.enc")
    }

    private fun readDiskCache(config: SourceConfig): List<ChannelGroup>? = runCatching {
        val f = cacheFile(config)
        if (!f.exists()) return null
        require(f.length() <= 8 * 1024 * 1024) { "频道缓存过大" }
        val root = JSONArray(secrets.decrypt(f.readText(), "live:${f.name}"))
        buildList(root.length()) {
            for (i in 0 until root.length()) {
                val gObj = root.getJSONObject(i)
                val cArr = gObj.getJSONArray("channels")
                val channels = buildList(cArr.length()) {
                    for (j in 0 until cArr.length()) {
                        val cObj = cArr.getJSONObject(j)
                        val lArr = cObj.optJSONArray("lines") ?: JSONArray()
                        val lines = buildList(lArr.length()) {
                            for (k in 0 until lArr.length()) {
                                val lObj = lArr.getJSONObject(k)
                                val hObj = lObj.optJSONObject("headers")
                                val headers = if (hObj != null) {
                                    buildMap {
                                        val keys = hObj.keys()
                                        while (keys.hasNext()) {
                                            val key = keys.next()
                                            put(key, hObj.optString(key, ""))
                                        }
                                    }
                                } else emptyMap()
                                add(PlayLine(url = lObj.getString("url"), label = lObj.optString("label", "线路"), headers = headers))
                            }
                        }
                        add(
                            Channel(
                                id = cObj.getString("id"),
                                name = cObj.getString("name"),
                                logo = cObj.optString("logo").takeIf { it.isNotEmpty() },
                                urls = lines.map { it.url },
                                epgId = cObj.optString("epgId").takeIf { it.isNotEmpty() },
                                lines = lines,
                            ),
                        )
                    }
                }
                add(ChannelGroup(name = gObj.getString("name"), channels = channels))
            }
        }
    }.getOrNull()

    private fun writeDiskCache(config: SourceConfig, groups: List<ChannelGroup>) = runCatching {
        val root = JSONArray()
        for (g in groups) {
            val cArr = JSONArray()
            for (c in g.channels) {
                val lArr = JSONArray()
                for (l in c.lines) {
                    lArr.put(
                        JSONObject()
                            .put("url", l.url)
                            .put("label", l.label)
                            .put("headers", JSONObject(l.headers)),
                    )
                }
                cArr.put(
                    JSONObject()
                        .put("id", c.id)
                        .put("name", c.name)
                        .put("logo", c.logo ?: "")
                        .put("epgId", c.epgId ?: "")
                        .put("lines", lArr),
                )
            }
            root.put(JSONObject().put("name", g.name).put("channels", cArr))
        }
        val file = cacheFile(config)
        val atomic = android.util.AtomicFile(file)
        val output = atomic.startWrite()
        try {
            output.write(secrets.encrypt(root.toString(), "live:${file.name}").toByteArray())
            atomic.finishWrite(output)
        } catch (error: Exception) { atomic.failWrite(output); throw error }
        diskCacheDir.listFiles()?.filter { it.extension == "json" }?.forEach { it.delete() }
        diskCacheDir.listFiles()?.filter { it.extension == "enc" }?.sortedByDescending { it.lastModified() }?.drop(8)?.forEach { it.delete() }
    }

    override suspend fun findChannel(sourceId: String, channelId: String): Channel? {
        // 优先命中内存缓存，未命中则取首次非空发出（磁盘快照或网络返回），避免等待后台二次刷新完成
        val config = sources.get(sourceId) ?: return null
        val groups = cache[config] ?: channelGroups(sourceId).firstOrNull { it.isNotEmpty() }.orEmpty()
        return groups.asSequence().flatMap { it.channels }.firstOrNull { it.id == channelId }
    }

    override suspend fun epg(sourceId: String, channelId: String) = withContext(io) {
        val config = sources.get(sourceId) ?: error("Source unavailable")
        registry.live(config.type).epg(config, channelId)
    }

    override suspend fun resolve(sourceId: String, channel: Channel): PlayItem {
        val config = sources.get(sourceId) ?: error("数据源不存在: $sourceId")
        return registry.live(config.type).resolve(config, channel)
    }
}

/**
 * 点播仓储实现。
 *
 * **What**: 负责点播子源路由、分类检索、分页列表、详情元数据解析以及全源联邦搜索。
 *
 * **Why**: 针对低内存设备（LOW 档）与中高端设备按 [DeviceProfile] 动态控制并发抓取上限（Semaphore），
 * 搜索任务在协程取消时立即向各个数据源下发中断信号，并支持逐源流式增量回调（NDJSON/增量流）。
 */
@Singleton
class DefaultVodRepository @Inject constructor(
    private val registry: SourceRegistry,
    private val sources: SourceRepository,
    private val deviceProfile: DeviceProfile,
    private val suggestService: SearchSuggestService? = null,
) : VodRepository {
    private suspend fun <T> withSource(id: String, block: suspend (SourceConfig, com.flytech.juying.source.api.VodSource) -> T): T {
        val c = sources.get(id) ?: error("数据源不存在: $id")
        return block(c, registry.vod(c.type))
    }

    override suspend fun subSources(sourceId: String): List<SubSource> = withSource(sourceId) { c, s -> s.subSources(c) }
    override suspend fun categories(sourceId: String): List<VodCategory> = withSource(sourceId) { c, s -> s.categories(c) }
    override suspend fun categories(sourceId: String, subSourceId: String?): List<VodCategory> =
        withSource(sourceId) { c, s -> s.categories(c, subSourceId) }
    override suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem> =
        withSource(sourceId) { c, s -> s.list(c, categoryId, page) }
    override suspend fun listPage(sourceId: String, categoryId: String, page: Int): com.flytech.juying.core.model.VodPage =
        withSource(sourceId) { c, s -> s.listPage(c, categoryId, page) }
    override suspend fun detail(sourceId: String, itemId: String): VodDetail =
        withSource(sourceId) { c, s -> s.detail(c, itemId) }
    override suspend fun suggestions(query: String): List<String> = suggestService?.suggest(query).orEmpty()
    override suspend fun search(sourceId: String, keyword: String, page: Int): List<VodItem> {
        val c = sources.get(sourceId) ?: error("数据源不存在: $sourceId")
        return registry.searchable(c.type).search(c, keyword, page)
    }
    override suspend fun searchAll(keyword: String, page: Int): List<VodItem> =
        searchUpdates(keyword, page).filterIsInstance<SearchUpdate.Finished>().toList()
            .flatMap { it.items }.distinctBy { it.sourceId to it.id }

    override fun searchUpdates(keyword: String, page: Int): Flow<SearchUpdate> = channelFlow {
        require(page >= 1)
        if (keyword.isBlank()) return@channelFlow
        val trimmed = keyword.trim()
        val isPinyin = trimmed.all { it in 'a'..'z' || it in 'A'..'Z' || it.isDigit() }
        val searchKeywords = if (isPinyin && trimmed.length >= 2) {
            val suggestions = runCatching { suggestService?.suggest(trimmed)?.take(2).orEmpty() }.getOrDefault(emptyList())
            (listOf(trimmed) + suggestions).distinct()
        } else {
            listOf(trimmed)
        }
        val permits = when (deviceProfile.tier) {
            PerformanceTier.LOW -> LOW_SEARCH_CONCURRENCY
            PerformanceTier.MID -> MID_SEARCH_CONCURRENCY
            PerformanceTier.HIGH -> HIGH_SEARCH_CONCURRENCY
        }
        val semaphore = Semaphore(permits)
        sources.observeSources(SourceCapability.SEARCH).firstOrNull().orEmpty().forEach { config -> launch {
            val parent = SearchTarget(config.id, config.name)
            val provider = registry.searchable(config.type)
            val targets = try {
                semaphore.withPermit { withTimeoutOrNull(DISCOVERY_TIMEOUT_MS) {
                    val children = (provider as? VodSource)?.subSources(config).orEmpty()
                    if (children.isEmpty()) listOf(parent)
                    else children.filter { it.searchable }.map { parent.copy(subSource = it) }
                } }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                send(SearchUpdate.Discovered(listOf(parent)))
                send(SearchUpdate.Finished(parent, SearchOutcome.FAILED))
                return@launch
            }
            if (targets == null) {
                send(SearchUpdate.Discovered(listOf(parent)))
                send(SearchUpdate.Finished(parent, SearchOutcome.TIMED_OUT))
                return@launch
            }
            send(SearchUpdate.Discovered(targets))
            targets.forEach { target -> launch {
                val result = semaphore.withPermit {
                    try {
                        val collected = mutableListOf<VodItem>()
                        var hasSuccess = false
                        for (kw in searchKeywords) {
                            val items = runCatching {
                                withTimeoutOrNull(SEARCH_TIMEOUT_MS) {
                                    if (provider is VodSource) provider.search(config, kw, page, target.subSource?.id)
                                    else provider.search(config, kw, page)
                                }
                            }.getOrNull()
                            if (items != null) {
                                hasSuccess = true
                                collected.addAll(items)
                            }
                        }
                        val outcome = if (hasSuccess) SearchOutcome.SUCCESS else SearchOutcome.FAILED
                        SearchUpdate.Finished(target, outcome, collected.distinctBy { it.id })
                    } catch (error: Exception) {
                        if (error is CancellationException) throw error
                        Timber.w("Source search failed: %s", error.javaClass.simpleName)
                        SearchUpdate.Finished(target, SearchOutcome.FAILED)
                    }
                }
                send(result)
            } }
        } }
    }
    override suspend fun resolve(sourceId: String, episodeRef: String): PlayItem =
        withSource(sourceId) { c, s -> s.resolve(c, episodeRef) }

    private companion object {
        // 低配机避免一次创建几十条联网/脚本任务；排队时间不占源自身的执行超时。
        const val LOW_SEARCH_CONCURRENCY = 2
        const val MID_SEARCH_CONCURRENCY = 4
        const val HIGH_SEARCH_CONCURRENCY = 6
        const val DISCOVERY_TIMEOUT_MS = 8_000L
        const val SEARCH_TIMEOUT_MS = 30_000L
    }
}

/**
 * 存储与目录浏览仓储实现。
 *
 * **What**: 负责 SMB、本地存储、USB 移动硬盘等多源目录树遍历、最近目录 LRU 缓存与同目录外挂字幕发现。
 *
 * **Why**: 将目录缓存限制在最近 8 个条目以内，避免用户深度遍历多层文件夹时内存泄漏或挤占视频缓冲空间。
 */
@Singleton
class DefaultBrowseRepository @Inject constructor(
    private val registry: SourceRegistry,
    private val sources: SourceRepository,
) : BrowseRepository {
    // 按配置隔离并只保留最近 8 个目录，避免长时间浏览占满低配盒子的内存。
    private val directoryCache = LinkedHashMap<Pair<SourceConfig, String>, List<FileEntry>>(8, .75f, true)

    override suspend fun list(sourceId: String, path: String): List<FileEntry> {
        val c = sources.get(sourceId) ?: error("数据源不存在: $sourceId")
        return registry.browse(c.type).list(c, path).also { entries ->
            synchronized(directoryCache) {
                directoryCache[c to path.trim('/')] = entries
                while (directoryCache.size > 8) directoryCache.remove(directoryCache.keys.first())
            }
        }
    }

    override suspend fun playItem(sourceId: String, entry: FileEntry): PlayItem {
        val c = sources.get(sourceId) ?: error("数据源不存在: $sourceId")
        val parentPath = entry.path.trim('/').substringBeforeLast('/', "")
        val siblings = synchronized(directoryCache) { directoryCache[c to parentPath] } ?: try {
            list(sourceId, parentPath)
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Timber.w("Subtitle directory unavailable: %s", error.javaClass.simpleName)
            emptyList()
        }
        return withContext(kotlinx.coroutines.Dispatchers.IO) { registry.browse(c.type).playItem(c, entry, siblings) }
    }
}

/**
 * 播放历史仓储实现。
 *
 * **What**: 使用 Room [HistoryDao] 持久化各源最近播放记录、时间戳、进度（毫秒）及恢复选集所需的元数据。
 */
@Singleton
class DefaultHistoryRepository @Inject constructor(private val dao: HistoryDao) : HistoryRepository {
    override fun observeRecent(limit: Int): Flow<List<HistoryEntry>> =
        dao.observeRecent(limit).map { rows ->
            rows.map { it.toModel() }
        }

    override suspend fun get(id: String): HistoryEntry? = dao.get(id)?.toModel()

    override suspend fun record(entry: HistoryEntry) = dao.upsert(
        HistoryDbEntity(entry.id, entry.kind.name, entry.sourceId, entry.ref, entry.title, entry.positionMs, entry.durationMs, entry.updatedAt, entry.cover,
            JSONObject(entry.extra).toString()),
    )

    override suspend fun delete(id: String) = dao.delete(id)
    override suspend fun clear() = dao.clear()

    private fun HistoryDbEntity.toModel() =
        HistoryEntry(id, PlayKind.valueOf(kind), sourceId, ref, title, positionMs, durationMs, updatedAt, cover,
            JSONObject(extraJson).let { obj -> obj.keys().asSequence().associateWith { obj.getString(it) } })
}

/**
 * 收藏夹仓储实现。
 *
 * **What**: 管理用户收藏的直播频道、点播影片与目录项目，支持响应式关注状态流。
 */
@Singleton
class DefaultFavoriteRepository @Inject constructor(private val dao: FavoriteDao) : FavoriteRepository {
    override fun observeAll(): Flow<List<FavoriteEntry>> =
        dao.observeAll().map { rows ->
            rows.map {
                FavoriteEntry(it.id, PlayKind.valueOf(it.kind), it.sourceId, it.ref, it.title, it.cover, it.createdAt)
            }
        }

    override fun observeIsFavorite(id: String): Flow<Boolean> = dao.observeIsFavorite(id)

    override suspend fun upsert(entry: FavoriteEntry) = dao.upsert(
        FavoriteEntity(
            id = entry.id,
            kind = entry.kind.name,
            sourceId = entry.sourceId,
            ref = entry.ref,
            title = entry.title,
            cover = entry.cover,
            createdAt = if (entry.createdAt > 0L) entry.createdAt else System.currentTimeMillis(),
        ),
    )

    override suspend fun delete(id: String) = dao.delete(id)
}

/**
 * 全局应用设置仓储实现。
 *
 * **What**: 对接 DataStore [SettingsDataSource]，提供解码模式（软解/硬解）、自动帧率切换（AFR）等偏好设置。
 */
@Singleton
class DefaultSettingsRepository @Inject constructor(private val ds: SettingsDataSource) : SettingsRepository {
    override val settings: Flow<AppSettings> = ds.settings
    override suspend fun setDecoderMode(mode: DecoderMode) = ds.setDecoderMode(mode)
    override suspend fun setAutoFrameRate(enabled: Boolean) = ds.setAutoFrameRate(enabled)
}
