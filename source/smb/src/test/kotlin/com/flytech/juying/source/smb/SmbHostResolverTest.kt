package com.flytech.juying.source.smb

import org.junit.Assert.*
import org.junit.Test

class SmbHostResolverTest {

    @Test
    fun isIpAddressCorrectlyIdentifiesIpv4AndIpv6() {
        assertTrue(SmbHostResolver.isIpAddress("192.168.1.1"))
        assertTrue(SmbHostResolver.isIpAddress("10.0.0.1"))
        assertTrue(SmbHostResolver.isIpAddress("127.0.0.1"))
        assertTrue(SmbHostResolver.isIpAddress("fe80::1"))
        assertTrue(SmbHostResolver.isIpAddress("[fe80::1]"))
        assertTrue(SmbHostResolver.isIpAddress("::1"))

        assertFalse(SmbHostResolver.isIpAddress("nas.local"))
        assertFalse(SmbHostResolver.isIpAddress("QYTECH"))
        assertFalse(SmbHostResolver.isIpAddress("my-server"))
        assertFalse(SmbHostResolver.isIpAddress("192.168.1.300"))
        assertFalse(SmbHostResolver.isIpAddress(""))
    }

    @Test
    fun parseNetBiosNamesExtractsUniqueComputerName() {
        val buffer = ByteArray(120)
        // Set number of names at byte 56
        buffer[56] = 2.toByte()

        // Entry 0: GROUP "WORKGROUP"
        val groupName = "WORKGROUP      ".toByteArray(Charsets.US_ASCII)
        System.arraycopy(groupName, 0, buffer, 57, 15)
        buffer[57 + 15] = 0x00 // type
        buffer[57 + 16] = 0x80.toByte() // group flag set (bit 15)

        // Entry 1: UNIQUE "QYTECH"
        val uniqueName = "QYTECH         ".toByteArray(Charsets.US_ASCII)
        System.arraycopy(uniqueName, 0, buffer, 57 + 18, 15)
        buffer[57 + 18 + 15] = 0x00 // type Workstation
        buffer[57 + 18 + 16] = 0x00 // unique flag (bit 15 clear)

        val resolved = SmbHostResolver.parseNetBiosNames(buffer, 57 + 36)
        assertEquals("QYTECH", resolved)
    }

    @Test
    fun parseNetBiosNamesReturnsNullOnTruncatedOrMalformedData() {
        assertNull(SmbHostResolver.parseNetBiosNames(ByteArray(50), 50))
        assertNull(SmbHostResolver.parseNetBiosNames(ByteArray(57), 57))
    }

    @Test
    fun resolveReturnsNonIpDirectlyWithoutNetwork() {
        assertEquals("nas.local", SmbHostResolver.resolve("nas.local"))
        assertEquals("QYTECH", SmbHostResolver.resolve("QYTECH"))
    }
}
