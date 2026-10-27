package com.flytech.juying.core.domain

import com.flytech.juying.core.data.LiveRepository
import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import kotlinx.coroutines.flow.first
import javax.inject.Inject

/** 上/下一个频道（在当前分组内循环）。 */
class ZapChannelUseCase @Inject constructor(private val live: LiveRepository) {
    suspend operator fun invoke(sourceId: String, currentId: String, delta: Int): Channel? {
        val groups: List<ChannelGroup> = live.channelGroups(sourceId).first()
        val group = groups.firstOrNull { g -> g.channels.any { it.id == currentId } } ?: return null
        val idx = group.channels.indexOfFirst { it.id == currentId }
        val size = group.channels.size
        return group.channels[((idx + delta) % size + size) % size]
    }
}
