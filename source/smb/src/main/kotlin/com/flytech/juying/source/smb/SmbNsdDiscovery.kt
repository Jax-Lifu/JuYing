package com.flytech.juying.source.smb

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import com.flytech.juying.core.model.NetworkStorageDevice
import com.flytech.juying.core.model.SourceType
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.resume
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber

/** 按需发现局域网 SMB 服务；调用方限定网络和扫描时长，取消后停止发现并忽略迟到解析。 */
@Suppress("DEPRECATION") // Android 9 仍需使用旧版 NSD 解析接口。
internal fun discoverSmbServices(context: Context): Flow<NetworkStorageDevice> = callbackFlow {
    val manager = context.getSystemService(NsdManager::class.java)
    if (manager == null) {
        close()
        return@callbackFlow
    }
    val pending = Channel<NsdServiceInfo>(Channel.BUFFERED)
    val seen = ConcurrentHashMap.newKeySet<String>()
    // Android 旧版 NSD 同时解析多个服务会返回 BUSY，因此只保留一个解析协程。
    val resolver = launch {
        for (service in pending) {
            val resolved = suspendCancellableCoroutine<NsdServiceInfo?> { continuation ->
                if (!continuation.isActive) return@suspendCancellableCoroutine
                val listener = object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                        if (continuation.isActive) continuation.resume(null)
                    }
                    override fun onServiceResolved(info: NsdServiceInfo) {
                        if (continuation.isActive) continuation.resume(info)
                    }
                }
                try {
                    manager.resolveService(service, listener)
                } catch (_: IllegalArgumentException) {
                    if (continuation.isActive) continuation.resume(null)
                }
            } ?: continue
            val address = resolved.host ?: continue
            if (!address.isSiteLocalAddress && !address.isLinkLocalAddress) continue
            val host = address.hostAddress ?: continue
            if (resolved.port !in 1..65535) continue
            val serviceName = resolved.serviceName.orEmpty().ifBlank {
                address.hostName.orEmpty().ifBlank { host }
            }
            val displayName = if (!SmbHostResolver.isIpAddress(serviceName)) serviceName else SmbHostResolver.resolve(host)
            trySend(NetworkStorageDevice(SourceType.SMB, displayName, host, resolved.port))
        }
    }
    val discovery = object : NsdManager.DiscoveryListener {
        override fun onDiscoveryStarted(serviceType: String) = Unit
        override fun onDiscoveryStopped(serviceType: String) { close() }
        override fun onServiceLost(service: NsdServiceInfo) = Unit
        override fun onServiceFound(service: NsdServiceInfo) {
            if (!isActive) return
            val name = service.serviceName ?: return
            if (seen.add(name) && pending.trySend(service).isFailure) seen.remove(name)
        }
        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
            Timber.w("SMB service discovery failed: %d", errorCode)
            close()
        }
        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
            Timber.w("SMB service discovery stop failed: %d", errorCode)
        }
    }
    try {
        manager.discoverServices("_smb._tcp.", NsdManager.PROTOCOL_DNS_SD, discovery)
    } catch (error: RuntimeException) {
        Timber.w(error, "SMB service discovery unavailable")
        close()
    }
    awaitClose {
        resolver.cancel()
        pending.close()
        runCatching { manager.stopServiceDiscovery(discovery) }
    }
}
