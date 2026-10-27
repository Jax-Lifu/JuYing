package com.flytech.juying.source.api

import com.flytech.juying.core.model.NetworkStorageDevice
import com.flytech.juying.core.model.SourceConfig
import kotlinx.coroutines.flow.Flow

/** User-initiated discovery and setup; cancellation must release temporary network resources. */
interface NetworkStorageSource : SourceProvider {
    fun discoverDevices(): Flow<NetworkStorageDevice>
    /** Accepts a server address, never credentials or a share path. */
    fun manualDevice(address: String): NetworkStorageDevice
    suspend fun shares(device: NetworkStorageDevice, username: String, password: String, domain: String): List<String>
    /** Builds an unsaved draft; callers must check read access before persisting it. */
    fun configuration(device: NetworkStorageDevice, share: String, username: String, password: String, domain: String): SourceConfig
}
