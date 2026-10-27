package com.flytech.juying.source.smb

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.flytech.juying.core.common.Dispatcher
import com.flytech.juying.core.common.JuyingDispatchers
import com.flytech.juying.core.model.NetworkStorageDevice
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.hierynomus.protocol.commons.socket.ProxySocketFactory
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.mssmb2.SMBApiException
import com.rapid7.client.dcerpc.mssrvs.ServerService
import com.rapid7.client.dcerpc.transport.SMBTransportFactories
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.IOException
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.net.URISyntaxException
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull

/** On-demand LAN discovery and short-lived login sessions; neither touches playback's connection cache. */
class SmbNetworkStorage @Inject constructor(
    @ApplicationContext private val context: Context,
    @Dispatcher(JuyingDispatchers.IO) private val ioDispatcher: CoroutineDispatcher,
) {
    fun discoverDevices(): Flow<NetworkStorageDevice> = channelFlow {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return@channelFlow
        val network = manager.activeNetwork ?: return@channelFlow
        val capabilities = manager.getNetworkCapabilities(network) ?: return@channelFlow
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
            (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))) return@channelFlow
        val addresses = manager.getLinkProperties(network)?.linkAddresses.orEmpty()
            .filter { it.address is Inet4Address && (it.address.isSiteLocalAddress || it.address.isLinkLocalAddress) }
        val candidates = addresses.flatMap { smbScanCandidates(it.address as Inet4Address, it.prefixLength) }.distinct()
        val scans = listOf(
            launch {
                // Eight short connects at a time cap sockets and coroutine work on low-memory TV boxes.
                candidates.chunked(SCAN_CONCURRENCY).forEach { batch ->
                    coroutineScope {
                        batch.forEach { host ->
                            launch {
                                if (smbPortOpen(host)) send(NetworkStorageDevice(SourceType.SMB, host, host, SMB_PORT))
                            }
                        }
                    }
                }
            },
            launch { discoverSmbServices(context).collect { send(it) } },
        )
        try {
            withTimeoutOrNull(DISCOVERY_TIMEOUT_MS) { scans.joinAll() }
        } finally {
            scans.forEach { it.cancel() }
        }
    }.flowOn(ioDispatcher)

    fun manualDevice(address: String): NetworkStorageDevice {
        val text = address.trim()
        val uri = try { URI(if ("://" in text) text else "smb://$text") }
        catch (_: URISyntaxException) { throw IllegalArgumentException("服务器地址格式无效") }
        require(uri.scheme.equals("smb", ignoreCase = true) && uri.host != null &&
            uri.rawUserInfo == null && uri.rawPath.isNullOrEmpty() && uri.rawQuery == null && uri.rawFragment == null) {
            "请输入服务器名称或 IP，可包含端口，不要包含共享目录或登录信息"
        }
        val port = uri.port.takeIf { it != -1 } ?: SMB_PORT
        require(port in 1..65535) { "端口必须在 1–65535 范围内" }
        val host = uri.host.removeSurrounding("[", "]")
        return NetworkStorageDevice(SourceType.SMB, host, host, port)
    }

    suspend fun shares(device: NetworkStorageDevice, username: String, password: String, domain: String): List<String> =
        withTimeout(LOGIN_TIMEOUT_MS) {
            runInterruptible(ioDispatcher) {
                val config = SmbConfig.builder()
                    .withSocketFactory(ProxySocketFactory(CONNECT_TIMEOUT_MS))
                    .withTimeout(RPC_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .withSoTimeout(RPC_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .build()
                try {
                    // A new client makes each login validate the submitted credentials, including failed retries.
                    SMBClient(config).use { client ->
                        client.connect(device.host, device.port).use { connection ->
                            connection.authenticate(AuthenticationContext(username.ifEmpty { "guest" }, password.toCharArray(), domain)).use { session ->
                                ServerService(SMBTransportFactories.SRVSVC.getTransport(session)).shares1
                                    .filter { (it.type and SHARE_TYPE_MASK) == DISK_SHARE_TYPE && !it.netName.endsWith('$') }
                                    .map { it.netName }
                                    .filter { it.isNotBlank() }
                                    .distinct()
                                    .sortedWith(String.CASE_INSENSITIVE_ORDER)
                            }
                        }
                    }
                } catch (error: SMBApiException) {
                    throw error.asBrowseException()
                }
            }
        }

    fun configuration(device: NetworkStorageDevice, share: String, username: String, password: String, domain: String): SourceConfig {
        require(share.isNotBlank() && share != "." && share != ".." && share.none { it == '/' || it == '\\' || it.isISOControl() }) {
            "共享名称无效"
        }
        val url = URI("smb", null, device.host, device.port.takeIf { it != SMB_PORT } ?: -1, "/$share", null, null).toASCIIString()
        val identity = "${device.host.lowercase()}:${device.port}/$share/${username.ifEmpty { "guest" }}/$domain"
        return SourceConfig(
            id = "smb:${UUID.nameUUIDFromBytes(identity.toByteArray(Charsets.UTF_8))}",
            name = "$share · ${device.name}",
            type = SourceType.SMB,
            url = url,
            username = username,
            password = password,
            extra = if (domain.isEmpty()) emptyMap() else mapOf("domain" to domain),
        )
    }

    private companion object {
        const val SCAN_CONCURRENCY = 8
        const val DISCOVERY_TIMEOUT_MS = 15_000L
        const val LOGIN_TIMEOUT_MS = 15_000L
        const val CONNECT_TIMEOUT_MS = 3_000
        const val RPC_TIMEOUT_MS = 5_000L
        const val SHARE_TYPE_MASK = 0xFF
        const val DISK_SHARE_TYPE = 0
    }
}

private const val SMB_PORT = 445
private const val PROBE_TIMEOUT_MS = 350

/** Restrict probes to at most the local /24; honor smaller real subnets and omit this device. */
internal fun smbScanCandidates(address: Inet4Address, prefixLength: Int): List<String> {
    require(prefixLength in 0..32)
    val prefix = maxOf(24, prefixLength)
    val own = address.address.fold(0L) { value, octet -> (value shl 8) or (octet.toLong() and 255) }
    val mask = (0xffff_ffffL shl (32 - prefix)) and 0xffff_ffffL
    val base = own and mask
    val last = base or (mask xor 0xffff_ffffL)
    val hosts = if (prefix < 31) (base + 1) until last else base..last
    return hosts.filter { it != own }.map { host -> (3 downTo 0).joinToString(".") { ((host shr (it * 8)) and 255).toString() } }
}

/** The timeout bounds Socket.connect, while use closes the socket after success, failure or interruption. */
internal suspend fun smbPortOpen(host: String, port: Int = SMB_PORT, socketFactory: () -> Socket = { Socket() }): Boolean =
    runInterruptible {
        socketFactory().use { socket ->
            try {
                socket.connect(InetSocketAddress(host, port), PROBE_TIMEOUT_MS)
                true
            } catch (_: IOException) {
                false
            }
        }
    }
