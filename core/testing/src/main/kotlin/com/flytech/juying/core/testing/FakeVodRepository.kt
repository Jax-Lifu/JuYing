package com.flytech.juying.core.testing

import com.flytech.juying.core.data.VodRepository
import com.flytech.juying.core.model.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

/** 页面测试只重写其场景需要的源行为。 */
open class FakeVodRepository : VodRepository {
    override suspend fun subSources(sourceId: String): List<SubSource> = emptyList()
    override suspend fun categories(sourceId: String): List<VodCategory> = emptyList()
    override suspend fun list(sourceId: String, categoryId: String, page: Int): List<VodItem> = emptyList()
    override suspend fun detail(sourceId: String, itemId: String): VodDetail = error("Unused detail")
    override suspend fun search(sourceId: String, keyword: String, page: Int): List<VodItem> = emptyList()
    override suspend fun searchAll(keyword: String, page: Int): List<VodItem> = emptyList()
    override fun searchUpdates(keyword: String, page: Int): Flow<SearchUpdate> = emptyFlow()
    override suspend fun resolve(sourceId: String, episodeRef: String): PlayItem = error("Unused resolve")
}
