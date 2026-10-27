package com.flytech.juying.source.api

import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.EpgProgram
import com.flytech.juying.core.model.FileEntry
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.PlayLine
import com.flytech.juying.core.model.SidecarSubtitles
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.model.SubSource
import com.flytech.juying.core.model.VodCategory
import com.flytech.juying.core.model.VodDetail
import com.flytech.juying.core.model.VodItem
import kotlinx.coroutines.flow.Flow

/**
 * 数据源的统一抽象。一个 Provider 对应一种 [SourceType]，可按需正交组合实现 [LiveSource]、[VodSource]、[BrowseSource]。
 * 新增数据源 = 新建 `source:xxx` 模块 + 用 Hilt `@IntoSet` 绑定到 [SourceProvider]。
 */
interface SourceProvider {
    val type: SourceType

    /** null 表示该源不使用通用订阅地址表单。 */
    val urlSetup: com.flytech.juying.core.model.UrlSourceSetup? get() = null

    /** 单站配置可收窄能力，避免将点播入口同时显示为不存在的直播列表。 */
    fun capabilities(config: SourceConfig): Set<SourceCapability> = capabilities

    /** 计算当前 Provider 具备的所有正交业务能力。 */
    val capabilities: Set<SourceCapability>
        get() = buildSet {
            if (this@SourceProvider is LiveSource) add(SourceCapability.LIVE)
            if (this@SourceProvider is VodSource) add(SourceCapability.VOD)
            if (this@SourceProvider is BrowseSource) add(SourceCapability.BROWSE)
            if (this@SourceProvider is VodSource || this@SourceProvider is SearchableSource) {
                add(SourceCapability.SEARCH)
            }
        }
}

/**
 * 动态/免配置数据源发现器（如内置 CCTV、本地存储、USB 移动存储热插拔卷、局域网 UPnP SSDP 发现）。
 *
 * **What**: 发出当前可用的动态 [SourceConfig] 列表流。
 *
 * **Why**: 让需要动态热插拔或局域网发现的源（`LOCAL`、`USB_STORAGE`、`UPNP`）与用户手动持久化到 Room 的源
 * （`IPTV`、`TVBOX`、`SMB`、`WEBDAV`、`CLOUD_DRIVE`、`ALIST`、`NFS`）在 `SourceRepository` 中无缝合流，
 * 上层 UI 无需区分「静态配置源」与「动态发现源」。
 */
interface SourceDiscoveryProvider {
    fun observeDiscoveredSources(): Flow<List<SourceConfig>>
}

/** 支持关键字搜索的源（除 [VodSource] 外，Alist/网盘/UPnP 等目录源也可按需实现）。 */
interface SearchableSource : SourceProvider {
    suspend fun search(config: SourceConfig, keyword: String, page: Int): List<VodItem>

    /** 指定复合源内的站点；null 使用该源的默认站点，引用仍由源实现解释。 */
    suspend fun search(config: SourceConfig, keyword: String, page: Int, subSourceId: String?): List<VodItem> {
        require(subSourceId == null) { "该源不支持子站点搜索" }
        return search(config, keyword, page)
    }
}

interface LiveSource : SourceProvider {
    suspend fun channels(config: SourceConfig): List<ChannelGroup>

    suspend fun epg(config: SourceConfig, channelId: String): List<EpgProgram> = emptyList()

    /** 播放时解析真实地址（央视等需要动态签名的源重写它）。默认取第一条线路并附带其余备用线路与请求头。 */
    suspend fun resolve(config: SourceConfig, channel: Channel): PlayItem {
        val candidates = channel.lines.ifEmpty { channel.urls.map { PlayLine(url = it) } }
        val primary = candidates.firstOrNull()
            ?: error("频道「${channel.name}」没有可用线路")
        return PlayItem(
            id = channel.id,
            title = channel.name,
            url = primary.url,
            headers = primary.headers,
            isLive = true,
            backupLines = candidates.drop(1),
        )
    }
}

interface VodSource : SearchableSource {
    /** 复合源（如 TVBox 单仓多站点、网盘多挂载点）可返回子源列表；单站点源默认返回空列表。 */
    suspend fun subSources(config: SourceConfig): List<SubSource> = emptyList()
    suspend fun categories(config: SourceConfig): List<VodCategory>
    /** 子站点选择不修改持久配置；分类与内容引用需保留站点路由。 */
    suspend fun categories(config: SourceConfig, subSourceId: String?): List<VodCategory> {
        require(subSourceId == null) { "该源不支持子站点分类" }
        return categories(config)
    }
    suspend fun list(config: SourceConfig, categoryId: String, page: Int): List<VodItem>
    /** 保留源提供的结束标记，避免重叠页被误判为最后一页。 */
    suspend fun listPage(config: SourceConfig, categoryId: String, page: Int): com.flytech.juying.core.model.VodPage =
        com.flytech.juying.core.model.VodPage(list(config, categoryId, page))
    suspend fun detail(config: SourceConfig, itemId: String): VodDetail
    override suspend fun search(config: SourceConfig, keyword: String, page: Int): List<VodItem>
    suspend fun resolve(config: SourceConfig, episodeRef: String): PlayItem
}

interface BrowseSource : SourceProvider {
    suspend fun list(config: SourceConfig, path: String): List<FileEntry>
    fun playItem(config: SourceConfig, entry: FileEntry): PlayItem

    /**
     * 生成携带同目录外挂字幕的 [PlayItem]（适用于 SMB、WebDAV、NFS、网盘、Alist、本地存储、移动存储、UPnP）。
     */
    fun playItem(config: SourceConfig, entry: FileEntry, siblings: List<FileEntry>): PlayItem {
        val base = playItem(config, entry)
        if (siblings.isEmpty() || base.subtitles.isNotEmpty()) return base
        val matched = SidecarSubtitles.matchFor(entry, siblings) { sub -> playItem(config, sub).url }
        return if (matched.isEmpty()) base else base.copy(subtitles = matched)
    }
}
