package com.flytech.juying.core.data

import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.DecoderMode
import com.flytech.juying.core.model.FavoriteEntry
import com.flytech.juying.core.model.FileEntry
import com.flytech.juying.core.model.HistoryEntry
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SubSource
import com.flytech.juying.core.model.SearchUpdate
import com.flytech.juying.core.model.VodCategory
import com.flytech.juying.core.model.VodDetail
import com.flytech.juying.core.model.VodItem
import kotlinx.coroutines.flow.Flow

/** 数据源仓储契约：管理所有持久化与动态发现源，支持测试连接与能力查询。 */
interface SourceRepository {
    /** Scan on demand; stopping collection cancels discovery. Devices are not persisted. */
    fun discoverNetworkStorage(): Flow<com.flytech.juying.core.model.NetworkStorageDevice> = kotlinx.coroutines.flow.emptyFlow()
    fun networkDevice(address: String): com.flytech.juying.core.model.NetworkStorageDevice = error("Network storage unavailable")
    suspend fun networkShares(device: com.flytech.juying.core.model.NetworkStorageDevice, username: String, password: String, domain: String): List<String> = error("Network storage unavailable")
    fun networkConfiguration(device: com.flytech.juying.core.model.NetworkStorageDevice, share: String, username: String, password: String, domain: String): SourceConfig = error("Network storage unavailable")

    /** Actual registered capabilities, including disabled sources in the management screen. */
    fun capabilities(config: SourceConfig): Set<SourceCapability> = emptySet()
    fun urlSetups(): List<com.flytech.juying.core.model.UrlSourceSetup> = emptyList()

    /**
     * 观察所有数据源（内置源 + 动态发现源如本地/USB/UPnP + Room 中用户配置的持久源）。
     * 若传入 [capability]，则仅返回已启用且当前已注册模块支持该能力的数据源。
     */
    fun observeSources(capability: SourceCapability? = null): Flow<List<SourceConfig>>
    suspend fun get(id: String): SourceConfig?
    suspend fun upsert(config: SourceConfig)
    suspend fun delete(id: String)
    /** Checks the draft without saving it; returns available channels, sites or directory entries. */
    suspend fun check(config: SourceConfig): Int = error("Connection check unavailable")
}

/** 直播仓储契约：频道分组、EPG 节目单与多线路签名播放项解析。 */
interface LiveRepository {
    /** offline-first：先发出缓存，再发出刷新结果。 */
    fun channelGroups(sourceId: String): Flow<List<ChannelGroup>>
    suspend fun findChannel(sourceId: String, channelId: String): Channel?
    /** An empty schedule is a supported absence, not a fabricated programme. */
    suspend fun epg(sourceId: String, channelId: String): List<com.flytech.juying.core.model.EpgProgram> = emptyList()
    suspend fun resolve(sourceId: String, channel: Channel): PlayItem
}

/** 点播仓储契约：子源管理、分类、分页列表与全源并发搜索。 */
interface VodRepository {
    /** 获取复合数据源的子源列表（如 TVBox 单仓内的多个 Spider 站点、网盘多挂载点）。 */
    suspend fun subSources(sourceId: String): List<SubSource>
    suspend fun categories(sourceId: String): List<VodCategory>
    suspend fun categories(sourceId: String, subSourceId: String?): List<VodCategory> = categories(sourceId)
    suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem>
    /** 分页结束信息由源决定；未知时交由列表按实际增长兜底。 */
    suspend fun listPage(sourceId: String, categoryId: String, page: Int): com.flytech.juying.core.model.VodPage =
        com.flytech.juying.core.model.VodPage(list(sourceId, categoryId, page))
    suspend fun detail(sourceId: String, itemId: String): VodDetail
    suspend fun search(sourceId: String, keyword: String, page: Int): List<VodItem>
    /** 并发跨所有启用且支持 `SEARCH` 能力的数据源检索，单个源超时或报错不影响其余源结果。 */
    suspend fun searchAll(keyword: String, page: Int = 1): List<VodItem>
    /** 同一仓库的可搜索子站也逐个返回；失败和超时保持可见，不伪装成零结果。 */
    fun searchUpdates(keyword: String, page: Int = 1): Flow<SearchUpdate>
    suspend fun resolve(sourceId: String, episodeRef: String): PlayItem
}

/** 存储浏览仓储契约：多层目录遍历与同目录外挂字幕发现。 */
interface BrowseRepository {
    suspend fun list(sourceId: String, path: String): List<FileEntry>
    suspend fun playItem(sourceId: String, entry: FileEntry): PlayItem
}

/** 历史记录仓储契约：播放时间戳、进度与续播元数据持久化。 */
interface HistoryRepository {
    fun observeRecent(limit: Int = 50): Flow<List<HistoryEntry>>
    suspend fun get(id: String): HistoryEntry?
    suspend fun record(entry: HistoryEntry)
    suspend fun delete(id: String)
    suspend fun clear()
}

/** 收藏夹仓储契约：用户收藏条目增删与监听。 */
interface FavoriteRepository {
    fun observeAll(): Flow<List<FavoriteEntry>>
    fun observeIsFavorite(id: String): Flow<Boolean>
    suspend fun upsert(entry: FavoriteEntry)
    suspend fun delete(id: String)
}

/** 应用设置仓储契约：解码器偏好、自动帧率切换等。 */
interface SettingsRepository {
    val settings: Flow<AppSettings>
    suspend fun setDecoderMode(mode: DecoderMode)
    suspend fun setAutoFrameRate(enabled: Boolean)
}
