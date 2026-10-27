package com.flytech.juying.source.smb

import com.flytech.juying.core.common.Dispatcher
import com.flytech.juying.core.common.JuyingDispatchers
import com.flytech.juying.core.model.FileEntry
import com.flytech.juying.core.model.NetworkStorageDevice
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.source.api.BrowseSource
import com.flytech.juying.source.api.NetworkStorageSource
import com.flytech.juying.source.api.SourceProvider
import com.hierynomus.msfscc.FileAttributes
import com.hierynomus.mssmb2.SMBApiException
import com.hierynomus.mserref.NtStatus
import java.io.FileNotFoundException
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.runInterruptible
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SmbSource @Inject constructor(
    private val connections: SmbConnections,
    private val networkStorage: SmbNetworkStorage,
    @Dispatcher(JuyingDispatchers.IO) private val ioDispatcher: CoroutineDispatcher,
) : BrowseSource, NetworkStorageSource {

    override val type = SourceType.SMB
    override val urlSetup = com.flytech.juying.core.model.UrlSourceSetup(type, "SMB", "smb://server/share",
        schemes = setOf("smb"), credentials = true, requiresPath = true)

    override fun discoverDevices() = networkStorage.discoverDevices()
    override fun manualDevice(address: String) = networkStorage.manualDevice(address)
    override suspend fun shares(device: NetworkStorageDevice, username: String, password: String, domain: String) =
        networkStorage.shares(device, username, password, domain)
    override fun configuration(device: NetworkStorageDevice, share: String, username: String, password: String, domain: String) =
        networkStorage.configuration(device, share, username, password, domain)

    override suspend fun list(config: SourceConfig, path: String): List<FileEntry> =
        runInterruptible(ioDispatcher) {
            val target = SmbTarget.fromConfig(config)
            try {
                connections.share(target, useTargetCredentials = true).list(target.fullPath(path))
                    .filter { it.fileName != "." && it.fileName != ".." }
                    .map { info ->
                        val relPath = listOf(path, info.fileName).filter { it.isNotBlank() }.joinToString("/")
                        val isDir = (info.fileAttributes and FileAttributes.FILE_ATTRIBUTE_DIRECTORY.value) != 0L
                        FileEntry(
                            name = info.fileName,
                            path = relPath,
                            isDirectory = isDir,
                            size = info.endOfFile,
                            modifiedMs = info.lastWriteTime.toEpochMillis(),
                            uri = if (isDir) null else target.toPlayUri(relPath),
                        )
                    }
                    .sortedWith(compareByDescending<FileEntry> { it.isDirectory }.thenBy { it.name.lowercase() })
            } catch (t: Throwable) {
                connections.invalidate(target)
                if (t is SMBApiException) throw t.asBrowseException()
                throw t
            }
        }

    override fun playItem(config: SourceConfig, entry: FileEntry): PlayItem {
        val target = SmbTarget.fromConfig(config)
        connections.registerCredentials(target)
        return PlayItem(
            id = "${config.id}:${entry.path}",
            title = entry.name,
            url = entry.uri ?: target.toPlayUri(entry.path),
        )
    }
}

// Only a missing directory permits parent recovery; authentication and transport errors retain the path.
internal fun SMBApiException.asBrowseException(): Exception = when (status) {
    NtStatus.STATUS_NO_SUCH_FILE, NtStatus.STATUS_OBJECT_NAME_NOT_FOUND, NtStatus.STATUS_OBJECT_PATH_NOT_FOUND ->
        FileNotFoundException("Directory unavailable").apply { initCause(this@asBrowseException) }
    NtStatus.STATUS_ACCESS_DENIED, NtStatus.STATUS_LOGON_FAILURE, NtStatus.STATUS_PASSWORD_EXPIRED,
    NtStatus.STATUS_ACCOUNT_DISABLED, NtStatus.STATUS_NETWORK_SESSION_EXPIRED -> SecurityException("Access unavailable", this)
    else -> this
}

@Module
@InstallIn(SingletonComponent::class)
abstract class SmbModule {
    @Binds @IntoSet
    abstract fun source(impl: SmbSource): SourceProvider
}
