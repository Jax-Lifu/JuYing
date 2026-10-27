package com.flytech.juying.core.testing

import com.flytech.juying.core.data.LiveRepository
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.rules.TestWatcher
import org.junit.runner.Description

/** 不用 Mock 框架：为 Repository 写 Fake，ViewModel 测试直接注入（符合 NIA 测试规范）。 */
class FakeLiveRepository(private val groups: List<ChannelGroup> = emptyList()) : LiveRepository {
    override fun channelGroups(sourceId: String): Flow<List<ChannelGroup>> = flowOf(groups)
    override suspend fun findChannel(sourceId: String, channelId: String): Channel? =
        groups.flatMap { it.channels }.firstOrNull { it.id == channelId }
    override suspend fun resolve(sourceId: String, channel: Channel) =
        PlayItem(
            id = channel.id,
            title = channel.name,
            url = channel.urls.firstOrNull().orEmpty(),
            isLive = true,
            backupLines = channel.lines.drop(1),
        )
}

class FakeSourceRepository(initial: List<SourceConfig> = emptyList()) : SourceRepository {
    private val state = MutableStateFlow(initial)

    override fun observeSources(capability: SourceCapability?): Flow<List<SourceConfig>> =
        state.map { list -> if (capability == null) list else list.filter { it.enabled } }

    override suspend fun get(id: String): SourceConfig? = state.value.firstOrNull { it.id == id }

    override suspend fun upsert(config: SourceConfig) {
        state.value = state.value.filterNot { it.id == config.id } + config
    }

    override suspend fun delete(id: String) {
        state.value = state.value.filterNot { it.id == id }
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(
    val testDispatcher: TestDispatcher = UnconfinedTestDispatcher(),
) : TestWatcher() {
    override fun starting(description: Description) = Dispatchers.setMain(testDispatcher)
    override fun finished(description: Description) = Dispatchers.resetMain()
}
