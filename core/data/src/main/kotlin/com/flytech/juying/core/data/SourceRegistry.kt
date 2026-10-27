package com.flytech.juying.core.data

import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.source.api.BrowseSource
import com.flytech.juying.source.api.LiveSource
import com.flytech.juying.source.api.SearchableSource
import com.flytech.juying.source.api.SourceProvider
import com.flytech.juying.source.api.VodSource
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 汇总所有通过 Hilt 多重绑定注册的数据源，按 [SourceType] + [SourceCapability] 查找。
 *
 * **What**: 提供面向能力（Live / Vod / Browse / Search）的统一源路由。
 *
 * **Why**: 让上层 Repository 与 ViewModel 只针对 `SourceCapability` 编程，不写死任何 `SourceType` 集合；
 * 后续新增 WebDAV、Alist、网盘、本地存储、USB 移动存储或 UPnP 模块时，只需注册 Hilt `@IntoSet`，全局自动生效。
 */
@Singleton
class SourceRegistry @Inject constructor(
    private val providers: @JvmSuppressWildcards Set<SourceProvider>,
) {
    fun urlSetups() = providers.mapNotNull { it.urlSetup }.distinctBy { it.type }

    fun networkStorage() = providers.filterIsInstance<com.flytech.juying.source.api.NetworkStorageSource>()
    fun networkStorage(type: SourceType): com.flytech.juying.source.api.NetworkStorageSource = find(type)

    fun capabilitiesOf(config: com.flytech.juying.core.model.SourceConfig): Set<SourceCapability> =
        providers.filter { it.type == config.type }.flatMapTo(linkedSetOf()) { it.capabilities(config) }

    fun live(type: SourceType): LiveSource = find(type)
    fun vod(type: SourceType): VodSource = find(type)
    fun browse(type: SourceType): BrowseSource = find(type)
    fun searchable(type: SourceType): SearchableSource = find(type)

    fun capabilitiesOf(type: SourceType): Set<SourceCapability> =
        providers.filter { it.type == type }.flatMapTo( linkedSetOf() ) { it.capabilities }

    fun supports(type: SourceType, capability: SourceCapability): Boolean =
        providers.any { it.type == type && capability in it.capabilities }

    fun supportsLive(type: SourceType) = supports(type, SourceCapability.LIVE)
    fun supportsVod(type: SourceType) = supports(type, SourceCapability.VOD)
    fun supportsBrowse(type: SourceType) = supports(type, SourceCapability.BROWSE)
    fun supportsSearch(type: SourceType) = supports(type, SourceCapability.SEARCH)

    private inline fun <reified T> find(type: SourceType): T =
        providers.firstOrNull { it.type == type && it is T } as? T
            ?: error("数据源类型 $type 不支持 ${T::class.java.simpleName}")
}
