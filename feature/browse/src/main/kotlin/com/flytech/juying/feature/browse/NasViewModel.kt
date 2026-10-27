package com.flytech.juying.feature.browse

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.NetworkStorageDevice
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
import javax.inject.Inject

enum class NasStage { DEVICES, LOGIN, SHARES }
enum class NasError { SCAN_FAILED, INVALID_ADDRESS, ACCESS_DENIED, CONNECTION_FAILED, INVALID_SHARE }

data class NasUiState(
    val stage: NasStage = NasStage.DEVICES,
    val devices: List<NetworkStorageDevice> = emptyList(),
    val device: NetworkStorageDevice? = null,
    val shares: List<String> = emptyList(),
    val scanning: Boolean = false,
    val busy: Boolean = false,
    val error: NasError? = null,
    val connectedSourceId: String? = null,
)

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

    fun scan() {
        stopScan()
        val scan = ++scanGeneration
        state.update { it.copy(devices = emptyList(), scanning = true, error = null) }
        scanJob = viewModelScope.launch {
            try {
                sources.discoverNetworkStorage().collect { device ->
                    ensureActive()
                    state.update { current ->
                        val previous = current.devices.find { it.type == device.type && it.host == device.host && it.port == device.port }
                        val named = previous?.takeIf { device.name == device.host && it.name != it.host } ?: device
                        current.copy(devices = (current.devices - listOfNotNull(previous) + named).sortedBy { it.name.lowercase() })
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
        state.value = NasUiState()
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
            state.update { it.copy(stage = NasStage.SHARES, shares = shares.distinct().sorted()) }
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
}
