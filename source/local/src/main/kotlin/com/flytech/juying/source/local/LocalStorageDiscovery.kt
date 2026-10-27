package com.flytech.juying.source.local

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import androidx.core.content.ContextCompat
import com.flytech.juying.core.common.Dispatcher
import com.flytech.juying.core.common.JuyingDispatchers
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.source.api.SourceDiscoveryProvider
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import javax.inject.Inject
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map

/** Mounted volumes are discovered lazily on IO; no storage work runs during Application.onCreate. */
class LocalStorageDiscovery @Inject constructor(
    @ApplicationContext private val context: Context,
    @Dispatcher(JuyingDispatchers.IO) private val ioDispatcher: CoroutineDispatcher,
) : SourceDiscoveryProvider {
    override fun observeDiscoveredSources(): Flow<List<SourceConfig>> = callbackFlow {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) { trySend(Unit) }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_MEDIA_MOUNTED)
            addAction(Intent.ACTION_MEDIA_UNMOUNTED)
            addAction(Intent.ACTION_MEDIA_REMOVED)
            addAction(Intent.ACTION_MEDIA_BAD_REMOVAL)
            addDataScheme("file")
        }
        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        trySend(Unit)
        awaitClose { context.unregisterReceiver(receiver) }
    }.map { mountedSources() }.distinctUntilChanged().flowOn(ioDispatcher)

    internal fun mountedSources(): List<SourceConfig> {
        val manager = context.getSystemService(StorageManager::class.java)
        val legacyRoots = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) context.getExternalFilesDirs(null)
            .filterNotNull().map { File(it.absolutePath.substringBefore("/Android/")) } else emptyList()
        return manager.storageVolumes.mapNotNull { volume ->
            if (volume.state != Environment.MEDIA_MOUNTED && volume.state != Environment.MEDIA_MOUNTED_READ_ONLY) return@mapNotNull null
            val directory = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) volume.directory else if (volume.isPrimary)
                Environment.getExternalStorageDirectory()
            else legacyRoots.firstOrNull { manager.getStorageVolume(it)?.uuid == volume.uuid }
                ?: volume.uuid?.let { File("/storage/$it") }
            directory?.let {
                SourceConfig(
                    id = "storage:volume:${if (volume.isPrimary) "primary" else volume.uuid ?: it.absolutePath}",
                    name = if (volume.isPrimary) context.getString(R.string.storage_device) else volume.getDescription(context),
                    type = if (volume.isRemovable) SourceType.USB_STORAGE else SourceType.LOCAL,
                    url = it.toURI().toString(),
                    isReadOnly = true,
                )
            }
        }.distinctBy { it.url }
    }
}
