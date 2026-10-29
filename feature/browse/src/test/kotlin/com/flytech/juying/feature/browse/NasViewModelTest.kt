package com.flytech.juying.feature.browse

import androidx.lifecycle.ViewModelStore
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.NetworkStorageDevice
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.testing.FakeSourceRepository
import com.flytech.juying.core.testing.MainDispatcherRule
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class NasViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val device = NetworkStorageDevice(SourceType.SMB, "Living room NAS", "192.168.1.12", 445)

    @Test fun selectingDiscoveredDeviceStopsScanAndOnlyReadableShareIsSaved() = runTest {
        var scanning = false
        var saved: SourceConfig? = null
        val repository = object : SourceRepository by FakeSourceRepository() {
            override fun discoverNetworkStorage() = flow {
                scanning = true
                try { emit(device); emit(device.copy(name = device.host)); awaitCancellation() }
                finally { scanning = false }
            }
            override fun networkDevice(address: String) = device
            override suspend fun networkShares(device: NetworkStorageDevice, username: String, password: String, domain: String): List<String> {
                if (password != "right") throw SecurityException()
                return listOf("Movies", "Private")
            }
            override fun networkConfiguration(device: NetworkStorageDevice, share: String, username: String, password: String, domain: String) =
                SourceConfig("nas-$share", share, device.type, "smb://${device.host}/$share", username = username, password = password)
            override suspend fun check(config: SourceConfig): Int {
                if (config.name == "Private") throw SecurityException()
                return 0 // Empty directories are valid connections.
            }
            override suspend fun upsert(config: SourceConfig) { saved = config }
        }
        val vm = NasViewModel(repository)
        val store = ViewModelStore().also { it.put("nas", vm) }
        try {
            vm.scan()
            assertTrue(scanning)
            assertEquals(1, vm.ui.value.devices.size)
            assertEquals(device.name, vm.ui.value.devices.single().name)
            vm.select(vm.ui.value.devices.single())
            assertFalse(scanning)
            assertEquals(NasStage.LOGIN, vm.ui.value.stage)
            vm.login(device.host, "user", "wrong", "")
            assertEquals(NasError.ACCESS_DENIED, vm.ui.value.error)
            assertNull(saved)
            vm.login(device.host, "user", "right", "")
            assertEquals(NasStage.SHARES, vm.ui.value.stage)
            assertEquals(listOf("Movies", "Private"), vm.ui.value.shares)
            vm.connectShare("Private")
            assertEquals(NasError.ACCESS_DENIED, vm.ui.value.error)
            assertNull(saved)
            vm.connectShare("Movies")
            assertEquals("nas-Movies", vm.ui.value.connectedSourceId)
            assertEquals("right", saved?.password)
        } finally { store.clear() }
    }

    @Test fun manualShareWorksWhenEnumerationIsForbiddenAndInvalidAddressDoesNotSave() = runTest {
        var saved: SourceConfig? = null
        val repository = object : SourceRepository by FakeSourceRepository() {
            override fun networkDevice(address: String): NetworkStorageDevice {
                require(address == device.host)
                return device
            }
            override suspend fun networkShares(device: NetworkStorageDevice, username: String, password: String, domain: String): List<String> = throw SecurityException()
            override fun networkConfiguration(device: NetworkStorageDevice, share: String, username: String, password: String, domain: String): SourceConfig {
                require(share.isNotBlank() && '/' !in share)
                return SourceConfig("manual", share, device.type, "smb://${device.host}/$share", username = username, password = password)
            }
            override suspend fun check(config: SourceConfig): Int { check(config.password == "right"); return 1 }
            override suspend fun upsert(config: SourceConfig) { saved = config }
        }
        val vm = NasViewModel(repository)
        val store = ViewModelStore().also { it.put("nas", vm) }
        try {
            vm.manual()
            vm.connectManualShare("invalid", "user", "right", "", "Movies")
            assertEquals(NasError.INVALID_ADDRESS, vm.ui.value.error)
            assertNull(saved)
            vm.login(device.host, "user", "right", "")
            assertEquals(NasError.ACCESS_DENIED, vm.ui.value.error)
            vm.connectManualShare(device.host, "user", "right", "", "Movies")
            assertEquals("manual", vm.ui.value.connectedSourceId)
            assertEquals("Movies", saved?.name)
        } finally { store.clear() }
    }

    @Test fun leavingLoginCancelsPendingConnectionAndClearsBusyState() = runTest {
        var cancelled = false
        val repository = object : SourceRepository by FakeSourceRepository() {
            override fun networkDevice(address: String) = device
            override suspend fun networkShares(device: NetworkStorageDevice, username: String, password: String, domain: String): List<String> =
                try { awaitCancellation() } finally { cancelled = true }
        }
        val vm = NasViewModel(repository)
        val store = ViewModelStore().also { it.put("nas", vm) }
        try {
            vm.manual()
            vm.login(device.host, "user", "right", "")
            assertTrue(vm.ui.value.busy)
            vm.backToDevices()
            assertTrue(cancelled)
            assertEquals(NasStage.DEVICES, vm.ui.value.stage)
            assertFalse(vm.ui.value.busy)
            assertTrue(vm.ui.value.shares.isEmpty())
        } finally { store.clear() }
    }

    @Test fun ipv4AndIpv6WithSameHostnameAreDeduplicatedPreferringIpv4() = runTest {
        val ipv6Device = NetworkStorageDevice(SourceType.SMB, "MyNAS", "fe80::1", 445)
        val ipv4Device = NetworkStorageDevice(SourceType.SMB, "MyNAS", "192.168.1.100", 445)
        val repository = object : SourceRepository by FakeSourceRepository() {
            override fun discoverNetworkStorage() = flow {
                emit(ipv6Device)
                emit(ipv4Device)
                awaitCancellation()
            }
        }
        val vm = NasViewModel(repository)
        val store = ViewModelStore().also { it.put("nas", vm) }
        try {
            vm.scan()
            assertEquals(1, vm.ui.value.devices.size)
            val single = vm.ui.value.devices.single()
            assertEquals("MyNAS", single.name)
            assertEquals("192.168.1.100", single.host)
        } finally { store.clear() }
    }
}
