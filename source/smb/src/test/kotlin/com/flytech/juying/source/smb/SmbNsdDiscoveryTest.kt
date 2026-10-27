package com.flytech.juying.source.smb

import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import com.flytech.juying.core.model.NetworkStorageDevice
import com.flytech.juying.core.model.SourceType
import java.net.InetAddress
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowNsdManager

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class SmbNsdDiscoveryTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private val nsd: ShadowNsdManager
        get() = Shadow.extract(context.getSystemService(NsdManager::class.java))

    @Test fun discoveredServicesResolveOneAtATime() = runTest {
        val devices = mutableListOf<NetworkStorageDevice>()
        val collector = backgroundScope.launch { discoverSmbServices(context).collect { devices += it } }
        runCurrent()
        val discovery = requireNotNull(nsd.getDiscoveryListeners(SERVICE_TYPE)).single()
        val first = service("First NAS")
        val second = service("Second NAS")

        discovery.onServiceFound(first)
        discovery.onServiceFound(second)
        runCurrent()
        val firstResolver = requireNotNull(nsd.getResolveListeners(first)).single()
        assertTrue(nsd.getResolveListeners(second).isNullOrEmpty())
        assertTrue(devices.isEmpty())

        firstResolver.onServiceResolved(service("First NAS", "192.168.1.10"))
        runCurrent()
        assertEquals(listOf(NetworkStorageDevice(SourceType.SMB, "First NAS", "192.168.1.10", 445)), devices)
        requireNotNull(nsd.getResolveListeners(second)).single().onServiceResolved(service("Second NAS", "192.168.1.11"))
        runCurrent()
        assertEquals(listOf("First NAS", "Second NAS"), devices.map { it.name })
        collector.cancelAndJoin()
    }

    @Test fun cancellingCollectorStopsServiceDiscovery() = runTest {
        val collector = backgroundScope.launch { discoverSmbServices(context).collect {} }
        runCurrent()
        val discovery = requireNotNull(nsd.getDiscoveryListeners(SERVICE_TYPE)).single()
        assertEquals(SERVICE_TYPE, nsd.getDiscoveryListenerServiceType(discovery))

        collector.cancelAndJoin()

        assertNull(nsd.getDiscoveryListenerServiceType(discovery))
        assertTrue(nsd.getDiscoveryListeners(SERVICE_TYPE).isNullOrEmpty())
    }

    @Test fun callbacksAfterCancellationCannotEmitOrResolveQueuedServices() = runTest {
        val devices = mutableListOf<NetworkStorageDevice>()
        val collector = backgroundScope.launch { discoverSmbServices(context).collect { devices += it } }
        runCurrent()
        val discovery = requireNotNull(nsd.getDiscoveryListeners(SERVICE_TYPE)).single()
        val first = service("First NAS")
        val queued = service("Queued NAS")
        val late = service("Late NAS")
        discovery.onServiceFound(first)
        discovery.onServiceFound(queued)
        runCurrent()
        val resolver = requireNotNull(nsd.getResolveListeners(first)).single()
        assertTrue(nsd.getResolveListeners(queued).isNullOrEmpty())

        collector.cancelAndJoin()
        resolver.onServiceResolved(service("First NAS", "192.168.1.10"))
        discovery.onServiceFound(late)
        runCurrent()

        assertTrue(devices.isEmpty())
        assertTrue(nsd.getResolveListeners(queued).isNullOrEmpty())
        assertTrue(nsd.getResolveListeners(late).isNullOrEmpty())
        assertNull(nsd.getDiscoveryListenerServiceType(discovery))
    }

    @Suppress("DEPRECATION")
    private fun service(name: String, address: String? = null) = NsdServiceInfo().apply {
        serviceName = name
        serviceType = SERVICE_TYPE
        port = 445
        if (address != null) host = InetAddress.getByName(address)
    }

    private companion object {
        const val SERVICE_TYPE = "_smb._tcp."
    }
}
