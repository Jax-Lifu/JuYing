package com.flytech.juying.feature.browse

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.NetworkStorageDevice
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceType
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import java.net.URI
import javax.inject.Inject

enum class NasStage { DEVICES, LOGIN, SHARES }
enum class NasError { SCAN_FAILED, INVALID_ADDRESS, ACCESS_DENIED, CONNECTION_FAILED, INVALID_SHARE }

/**
 * 局域网网络存储向导 UI 状态实体。
 */
data class NasUiState(
    val stage: NasStage = NasStage.DEVICES,
    val devices: List<NetworkStorageDevice> = emptyList(),
    val connectedDevices: Map<String, String> = emptyMap(),
    val device: NetworkStorageDevice? = null,
    val shares: List<String> = emptyList(),
    val scanning: Boolean = false,
    val busy: Boolean = false,
    val error: NasError? = null,
    val connectedSourceId: String? = null,
)

/** 局域网网络存储向导 ViewModel。 */
@HiltViewModel
class NasViewModel @Inject constructor(private val sources: SourceRepository) : ViewModel() {
    private val state = MutableStateFlow(NasUiState())
    val ui = state.asStateFlow()
    private var scanJob: Job? = null
    private var connectionJob: Job? = null
    private var generation = 0
    private var scanGeneration = 0
    // Credentials stay in this screen's memory until a readable share is saved through SourceSecrets.
    private var username = ""
    private var password = ""
    private var domain = ""

    init {
        viewModelScope.launch {
            sources.observeSources(SourceCapability.BROWSE).collect { configs ->
                val smbConfigs = configs.filter { it.type == SourceType.SMB }
                val map = mutableMapOf<String, String>()
                var knownDevices = state.value.devices
                smbConfigs.forEach { config ->
                    val uri = runCatching { URI(config.url) }.getOrNull() ?: return@forEach
                    val host = uri.host ?: return@forEach
                    val port = uri.port.takeIf { it != -1 } ?: 445
                    val hostname = if ("·" in config.name) {
                        config.name.substringAfterLast("·").trim()
                    } else config.name
                    val dev = NetworkStorageDevice(SourceType.SMB, hostname, host, port)
                    map[address(dev.host, dev.port).lowercase()] = config.id
                    if (isNamed(hostname)) {
                        map[address(hostname, port).lowercase()] = config.id
                    }
                    knownDevices = mergeDevice(knownDevices, dev)
                }
                state.update { it.copy(connectedDevices = map, devices = knownDevices) }
            }
        }
    }

    fun scan() {
        stopScan()
        val scan = ++scanGeneration
        state.update { current ->
            val connectedKeys = current.connectedDevices.keys
            val retained = current.devices.filter { dev ->
                address(dev.host, dev.port).lowercase() in connectedKeys ||
                    address(dev.name, dev.port).lowercase() in connectedKeys
            }
            current.copy(devices = retained, scanning = true, error = null)
        }
        scanJob = viewModelScope.launch {
            try {
                sources.discoverNetworkStorage().collect { device ->
                    ensureActive()
                    state.update { current ->
                        current.copy(devices = mergeDevice(current.devices, device))
                    }
                }
            } catch (e: CancellationException) { throw e
            } catch (_: Exception) { if (scan == scanGeneration) state.update { it.copy(error = NasError.SCAN_FAILED) }
            } finally { if (scan == scanGeneration) state.update { it.copy(scanning = false) } }
        }
    }

    fun stopScan() { scanGeneration++; scanJob?.cancel(); scanJob = null; state.update { it.copy(scanning = false) } }

    fun select(device: NetworkStorageDevice) {
        cancelConnection()
        stopScan()
        state.update { it.copy(stage = NasStage.LOGIN, device = device, shares = emptyList(), scanning = false, busy = false, error = null) }
    }

    fun manual() {
        cancelConnection()
        stopScan()
        state.update { it.copy(stage = NasStage.LOGIN, device = null, shares = emptyList(), scanning = false, busy = false, error = null) }
    }

    fun backToDevices() {
        cancelConnection()
        state.update { NasUiState(devices = it.devices, connectedDevices = it.connectedDevices) }
        scan()
    }

    fun editLogin() {
        cancelConnection()
        state.update { it.copy(stage = NasStage.LOGIN, shares = emptyList(), busy = false, error = null) }
    }

    fun login(address: String, username: String, password: String, domain: String) {
        val device = credentials(address, username, password, domain) ?: return
        request {
            val shares = withTimeout(20_000) { sources.networkShares(device, this@NasViewModel.username, this@NasViewModel.password, this@NasViewModel.domain) }
            ensureActive()
            val resolvedName = if (!isNamed(device.name)) {
                val parsed = runCatching { sources.networkDevice(device.host) }.getOrNull()
                if (parsed != null && isNamed(parsed.name)) parsed.name else device.name
            } else device.name
            val updatedDevice = if (resolvedName != device.name) device.copy(name = resolvedName) else device
            state.update { it.copy(stage = NasStage.SHARES, device = updatedDevice, shares = shares.distinct().sorted()) }
        }
    }

    fun connectManualShare(address: String, username: String, password: String, domain: String, share: String) {
        if (credentials(address, username, password, domain) != null) connectShare(share.trim())
    }

    fun connectShare(share: String) {
        val device = state.value.device ?: return
        val config = try { sources.networkConfiguration(device, share, username, password, domain) }
        catch (_: IllegalArgumentException) { state.update { it.copy(error = NasError.INVALID_SHARE) }; return }
        request {
            sources.check(config)
            ensureActive()
            sources.upsert(config)
            ensureActive()
            state.update { it.copy(connectedSourceId = config.id) }
            clearCredentials()
        }
    }

    fun consumeConnection() { state.update { it.copy(connectedSourceId = null) } }

    private fun credentials(address: String, username: String, password: String, domain: String): NetworkStorageDevice? {
        cancelConnection()
        val device = try { sources.networkDevice(address.trim()).let { parsed ->
            state.value.device?.takeIf { it.host == parsed.host && it.port == parsed.port && it.type == parsed.type } ?: parsed
        } } catch (_: IllegalArgumentException) {
            state.update { it.copy(error = NasError.INVALID_ADDRESS, busy = false) }; return null
        }
        this.username = username.trim()
        this.password = password
        this.domain = domain.trim()
        state.update { it.copy(device = device, shares = emptyList(), error = null) }
        return device
    }

    private fun request(block: suspend kotlinx.coroutines.CoroutineScope.() -> Unit) {
        connectionJob?.cancel()
        val request = ++generation
        state.update { it.copy(busy = true, error = null) }
        connectionJob = viewModelScope.launch {
            try { block()
            } catch (_: TimeoutCancellationException) {
                if (request == generation) state.update { it.copy(error = NasError.CONNECTION_FAILED) }
            } catch (e: CancellationException) { throw e
            } catch (e: Exception) {
                if (request == generation) state.update { it.copy(error = if (e is SecurityException) NasError.ACCESS_DENIED else NasError.CONNECTION_FAILED) }
            } finally { if (request == generation) state.update { it.copy(busy = false) } }
        }
    }

    private fun cancelConnection() { generation++; connectionJob?.cancel(); connectionJob = null; clearCredentials() }
    private fun clearCredentials() { username = ""; password = ""; domain = "" }
    override fun onCleared() { clearCredentials(); super.onCleared() }

    private fun isIpv4(host: String): Boolean {
        val s = host.trim().removeSurrounding("[", "]")
        val parts = s.split('.')
        return parts.size == 4 && parts.all { it.toIntOrNull()?.let { n -> n in 0..255 } == true }
    }

    private fun isNamed(name: String): Boolean {
        if (name.isBlank()) return false
        val s = name.trim().removeSurrounding("[", "]")
        val parts = s.split('.')
        if (parts.size == 4 && parts.all { it.toIntOrNull()?.let { n -> n in 0..255 } == true }) return false
        if (':' in s && s.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' || it == ':' }) return false
        return true
    }

    fun connectedSourceIdFor(device: NetworkStorageDevice): String? {
        val map = state.value.connectedDevices
        return map[address(device.host, device.port).lowercase()]
            ?: map[address(device.name, device.port).lowercase()]
    }

    private fun mergeDevice(current: List<NetworkStorageDevice>, device: NetworkStorageDevice): List<NetworkStorageDevice> {
        val previous = current.find { existing ->
            existing.type == device.type && existing.port == device.port && (
                existing.host == device.host ||
                (isNamed(existing.name) && isNamed(device.name) && existing.name.equals(device.name, ignoreCase = true))
            )
        }
        val winner = when {
            previous == null -> device
            isNamed(device.name) && !isNamed(previous.name) -> device
            isNamed(previous.name) && !isNamed(device.name) -> previous
            isIpv4(device.host) && !isIpv4(previous.host) -> device
            isIpv4(previous.host) && !isIpv4(device.host) -> previous
            else -> device
        }
        return (current - listOfNotNull(previous) + winner).sortedBy { it.name.lowercase() }
    }

    private fun address(host: String, port: Int) =
        "${if (':' in host && !host.startsWith('[')) "[$host]" else host}:$port"
}
