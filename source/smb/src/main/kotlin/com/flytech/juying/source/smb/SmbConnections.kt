package com.flytech.juying.source.smb

import com.hierynomus.protocol.commons.socket.ProxySocketFactory
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.share.DiskShare
import timber.log.Timber
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 复用 SMB 连接与内存凭据：
 * 1. 拖动进度条或加载外挂字幕会触发多次 open，复用连接避免重复握手。
 * 2. 采用按 `(host, port, share, user)` 分片锁而非全局锁，防止单个离线 NAS 阻塞其余连接。
 * 3. 内存中维护凭据映射，使 `smb://` 播放 URI 无需携带明文密码。
 */
@Singleton
class SmbConnections internal constructor(createClient: () -> SMBClient) {

    @Inject constructor() : this({
        SMBClient(SmbConfig.builder()
            .withSocketFactory(ProxySocketFactory(CONNECT_TIMEOUT_MS))
            .withTimeout(10, TimeUnit.SECONDS)
            .withSoTimeout(20, TimeUnit.SECONDS)
            .build())
    })

    private data class Key(val host: String, val port: Int, val share: String, val user: String)
    private data class Credential(val password: String, val domain: String)
    private class Entry(val connection: Connection, val share: DiskShare)

    // 懒加载 SMBClient：避免进入直播/点播页构造 SourceRegistry 时在主线程提前初始化 SMBEventBus
    private val client: SMBClient by lazy(createClient)
    private val cache = ConcurrentHashMap<Key, Entry>()
    private val credentials = ConcurrentHashMap<Key, Credential>()
    private val locks = ConcurrentHashMap<Key, Any>()

    internal fun registerCredentials(target: SmbTarget) {
        val key = Key(target.host, target.port, target.share, target.user)
        val lock = locks.getOrPut(key) { Any() }
        synchronized(lock) {
            updateCredentialsLocked(key, Credential(target.password, target.domain))
        }
    }

    /** 配置检查传 true，使清空密码或域也重新认证；无密码播放 URI 则沿用已登记凭据。 */
    internal fun share(target: SmbTarget, useTargetCredentials: Boolean = false): DiskShare {
        val key = Key(target.host, target.port, target.share, target.user)
        val lock = locks.getOrPut(key) { Any() }
        synchronized(lock) {
            // 更新和取缓存必须同锁，避免检查期间被另一个请求换回旧凭据。
            if (useTargetCredentials || target.password.isNotEmpty() || target.domain.isNotEmpty()) {
                updateCredentialsLocked(key, Credential(target.password, target.domain))
            }
            cache[key]?.let {
                if (it.connection.isConnected && it.share.isConnected) {
                    return it.share
                } else {
                    dropLocked(key)
                }
            }
            val cred = credentials[key] ?: Credential(target.password, target.domain)
            val connection = client.connect(target.host, target.port)
            try {
                val session = connection.authenticate(
                    AuthenticationContext(target.user, cred.password.toCharArray(), cred.domain),
                )
                val share = session.connectShare(target.share) as DiskShare
                cache[key] = Entry(connection, share)
                return share
            } catch (t: Throwable) {
                Timber.w(t, "SMB connect failed for %s/%s", target.host, target.share)
                runCatching { connection.close() }
                throw t
            }
        }
    }

    internal fun invalidate(target: SmbTarget) {
        val key = Key(target.host, target.port, target.share, target.user)
        val lock = locks.getOrPut(key) { Any() }
        synchronized(lock) {
            dropLocked(key)
        }
    }

    private fun updateCredentialsLocked(key: Key, credential: Credential) {
        if (credentials[key] != credential) {
            dropLocked(key)
            credentials[key] = credential
        }
    }

    private fun dropLocked(key: Key) {
        cache.remove(key)?.let {
            runCatching { it.share.close() }
            runCatching { it.connection.close() }
        }
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 3_000
    }
}
