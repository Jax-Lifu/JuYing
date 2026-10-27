package com.flytech.juying.source.smb

import java.io.IOException
import java.net.Inet4Address
import java.net.InetAddress
import java.net.Socket
import java.net.SocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class SmbNetworkStorageTest {
    private val storage get() = SmbNetworkStorage(RuntimeEnvironment.getApplication(), Dispatchers.IO)

    @Test fun candidatesStayInsideTheCurrentSubnetWithAtMostOneClassCBlock() {
        val broad = smbScanCandidates(ip("192.168.42.7"), 16)
        assertEquals(253, broad.size)
        assertTrue(broad.all { it.startsWith("192.168.42.") })
        assertFalse(broad.contains("192.168.42.7"))
        assertFalse(broad.contains("192.168.42.0"))
        assertFalse(broad.contains("192.168.42.255"))
        assertEquals(listOf("10.0.0.2", "10.0.0.3", "10.0.0.4", "10.0.0.5", "10.0.0.6"),
            smbScanCandidates(ip("10.0.0.1"), 29))
        assertEquals(listOf("10.0.0.3"), smbScanCandidates(ip("10.0.0.2"), 31))
        assertTrue(smbScanCandidates(ip("10.0.0.2"), 32).isEmpty())
    }

    @Test fun serverAddressesAcceptExplicitPortsButRejectConfigurationInTheAddress() {
        assertEquals("nas.local", storage.manualDevice("smb://nas.local").host)
        assertEquals(445, storage.manualDevice("192.168.1.2").port)
        assertEquals(1445, storage.manualDevice("192.168.1.2:1445").port)
        assertEquals("fd00::2", storage.manualDevice("smb://[fd00::2]:1445").host)
        listOf("", "http://nas", "smb://user:secret@nas", "smb://nas/share", "smb://nas?x=1",
            "smb://nas#x", "nas:0", "nas:65536", "nas:abc").forEach { address ->
            assertThrows("Accepted invalid address: $address", IllegalArgumentException::class.java) { storage.manualDevice(address) }
        }
    }

    @Test fun shareNamesAreEncodedOnceAndCredentialsRemainOutsideTheUrl() {
        val device = storage.manualDevice("nas:1445")
        val config = storage.configuration(device, "电影 100%#?", "user", "password", "WORKGROUP")
        val target = SmbTarget.fromConfig(config)
        assertEquals("电影 100%#?", target.share)
        assertEquals(1445, target.port)
        assertEquals("password", config.password)
        assertEquals("WORKGROUP", config.extra["domain"])
        assertFalse(config.url.contains("password"))
        assertFalse(config.url.contains("user@"))
        assertEquals(config.id, storage.configuration(device, "电影 100%#?", "user", "changed", "WORKGROUP").id)
        assertNotEquals(config.id, storage.configuration(device, "电影 100%#?", "user", "password", "OTHER").id)
        listOf("", ".", "..", "Movies/sub", "Movies\\sub", "Movies\n").forEach { share ->
            assertThrows(IllegalArgumentException::class.java) { storage.configuration(device, share, "", "", "") }
        }
    }

    @Test fun probesCloseTheirSocketOnSuccessAndFailure() = runBlocking {
        val success = ProbeSocket()
        assertTrue(smbPortOpen("127.0.0.1", socketFactory = { success }))
        assertEquals(350, success.timeoutMs)
        assertTrue(success.closed)
        val failure = ProbeSocket(fails = true)
        assertFalse(smbPortOpen("127.0.0.1", socketFactory = { failure }))
        assertTrue(failure.closed)
    }

    @Test fun cancellingAnActiveProbeInterruptsItAndClosesItsSocket() = runBlocking {
        val socket = ProbeSocket(blocks = true)
        val probe = async(Dispatchers.IO) { smbPortOpen("127.0.0.1", socketFactory = { socket }) }
        assertTrue(socket.entered.await(2, TimeUnit.SECONDS))
        probe.cancelAndJoin()
        assertTrue(socket.interrupted)
        assertTrue(socket.closed)
    }

    private class ProbeSocket(private val fails: Boolean = false, private val blocks: Boolean = false) : Socket() {
        val entered = CountDownLatch(1)
        var timeoutMs = 0
        var closed = false
        var interrupted = false
        override fun connect(endpoint: SocketAddress, timeout: Int) {
            timeoutMs = timeout
            entered.countDown()
            if (blocks) {
                try { CountDownLatch(1).await(5, TimeUnit.SECONDS) }
                catch (error: InterruptedException) { interrupted = true; throw error }
            }
            if (fails) throw IOException("Test connection refused")
        }
        override fun close() { closed = true }
    }

    private fun ip(address: String) = InetAddress.getByName(address) as Inet4Address
}
