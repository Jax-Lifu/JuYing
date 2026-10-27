package com.flytech.juying.source.cctv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CctvChannelsTest {
    @Test
    fun `every channel has its own official logo including special channels`() {
        val logos = CctvChannels.ALL.map { CctvChannels.logo(it.first) }
        assertEquals(CctvChannels.ALL.size, logos.toSet().size)
        assertTrue(logos.all { it.startsWith("https://") && it.contains(".img.cctvpic.com/") })
        assertTrue(CctvChannels.logo("cctv5plus") != CctvChannels.logo("cctv5"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `unknown channel is not given an invented logo`() {
        CctvChannels.logo("other")
    }
}
