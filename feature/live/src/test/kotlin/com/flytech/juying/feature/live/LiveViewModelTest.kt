package com.flytech.juying.feature.live

import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.testing.FakeLiveRepository
import com.flytech.juying.core.testing.FakeSourceRepository
import com.flytech.juying.core.testing.MainDispatcherRule
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LiveViewModelTest {

    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    @Test
    fun `loads channels from first available live source and switches group`() = runTest {
        val sources = FakeSourceRepository(
            listOf(
                SourceConfig(id = "builtin-cctv", name = "央视", type = SourceType.CCTV, url = ""),
            ),
        )
        val groups = listOf(
            ChannelGroup("央视", listOf(Channel(id = "cctv1", name = "CCTV-1 综合"))),
            ChannelGroup("卫视", listOf(Channel(id = "hnws", name = "湖南卫视"))),
        )
        val live = FakeLiveRepository(groups)
        val vm = LiveViewModel(sources, live)

        val collectJob = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            vm.uiState.collect()
        }

        val initial = vm.uiState.value
        assertFalse(initial.loading)
        assertEquals("builtin-cctv", initial.sourceId)
        assertEquals(2, initial.groups.size)
        assertEquals(0, initial.selectedGroup)

        vm.selectGroup(1)
        assertEquals(1, vm.uiState.value.selectedGroup)

        collectJob.cancel()
    }
}
