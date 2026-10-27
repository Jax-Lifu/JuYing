package com.flytech.juying.source.iptv

import javax.inject.Provider
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.*
import org.junit.Test

class IptvSourceTest {
    @Test fun xmltvTimesRespectOffsetAndRejectInvalidDates() {
        assertEquals(Xmltv.timestamp("20261026120000 +0800"), Xmltv.timestamp("20261026040000 +0000"))
        assertEquals(Xmltv.timestamp("20261026120000 +0800"), Xmltv.timestamp("202610261200 +0800"))
        assertNull(Xmltv.timestamp("not-a-time"))
        assertNull(Xmltv.timestamp("20261326120000 +0800"))
        assertNull(Xmltv.timestamp("20260230120000 +0800"))
    }
    @Test fun exposesSubscriptionSetupWithoutCreatingNetworkClient() {
        val source = IptvSource(Provider { error("Network client must remain lazy") }, Dispatchers.Default,
            Provider { error("No file access during discovery") })
        assertNotNull("IPTV must be addable through source management", source.urlSetup)
        assertEquals(setOf("http", "https", "content"), source.urlSetup.schemes)
    }
}
