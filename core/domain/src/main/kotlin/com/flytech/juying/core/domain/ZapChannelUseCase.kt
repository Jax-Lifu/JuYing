package com.flytech.juying.core.domain

import com.flytech.juying.core.data.LiveRepository
import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.ChannelGroup
import kotlinx.coroutines.flow.first
import javax.inject.Inject

/**
 * 直播按键快速切台用例。
 *
 * **What**: 根据当前频道 ID 与方向偏移量（[delta]，如 +1 为下一台，-1 为上一台），
 * 在当前频道分组列表内循环寻找目标频道。
 *
 * **Why**: 遥控器上下键切台与播放器控制栏切台共享同一组内循环寻址逻辑，
 * 边界越界时自动首尾相接环回，无可用频道或分组不存在时安全返回 null。
 */
class ZapChannelUseCase @Inject constructor(private val live: LiveRepository) {
    suspend operator fun invoke(sourceId: String, currentId: String, delta: Int): Channel? {
        val groups: List<ChannelGroup> = live.channelGroups(sourceId).first()
        val group = groups.firstOrNull { g -> g.channels.any { it.id == currentId } } ?: return null
        val idx = group.channels.indexOfFirst { it.id == currentId }
        val size = group.channels.size
        return group.channels[((idx + delta) % size + size) % size]
    }
}
