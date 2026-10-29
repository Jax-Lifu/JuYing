package com.flytech.juying.source.local

import android.content.Context
import android.os.Build
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.webkit.MimeTypeMap
import com.flytech.juying.core.common.Dispatcher
import com.flytech.juying.core.common.JuyingDispatchers
import com.flytech.juying.core.model.FileEntry
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.model.StorageAccessRequiredException
import com.flytech.juying.source.api.BrowseSource
import com.flytech.juying.source.api.SourceDiscoveryProvider
import com.flytech.juying.source.api.SourceProvider
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet
import java.io.FileNotFoundException
import javax.inject.Inject
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/**
 * 本机存储与外接存储浏览数据源实现。
 *
 * **What**: 支持直接文件系统路径（`file://`，通过 Android 11+ MANAGE_EXTERNAL_STORAGE 或 Android 9/10 READ_EXTERNAL_STORAGE）
 * 以及 Storage Access Framework（SAF 授权的 `content://` 目录树）遍历与媒体读取。
 *
 * **Why**: 用户无需频繁唤起系统文件选择器，在应用内即可完成目录导航与外挂字幕加载。
 */
class LocalSource @Inject constructor(
    @ApplicationContext private val context: Context,
    @Dispatcher(JuyingDispatchers.IO) private val ioDispatcher: CoroutineDispatcher,
) : BrowseSource {
    override val type = SourceType.LOCAL

    override suspend fun list(config: SourceConfig, path: String): List<FileEntry> = withContext(ioDispatcher) {
        ensureActive()
        if (config.url.startsWith("file:")) return@withContext listFiles(config, path)
        val tree = LocalDocumentPath.tree(config.url)
        val directory = LocalDocumentPath.document(tree, path)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getDocumentId(directory))
        val projection = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE, Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED)
        context.contentResolver.query(children, projection, null, null, null)?.use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    ensureActive()
                    val id = cursor.getString(0)
                    val mimeType = cursor.getString(2)
                    add(FileEntry(
                        name = cursor.getString(1),
                        path = LocalDocumentPath.child(path, id),
                        isDirectory = mimeType == Document.MIME_TYPE_DIR,
                        size = if (cursor.isNull(3)) 0 else cursor.getLong(3),
                        modifiedMs = if (cursor.isNull(4)) 0 else cursor.getLong(4),
                        mimeType = mimeType,
                        uri = DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                    ))
                }
            }.sortedWith(compareByDescending<FileEntry> { it.isDirectory }.thenBy { it.name.lowercase() })
        } ?: throw FileNotFoundException("Directory unavailable")
    }

    private suspend fun listFiles(config: SourceConfig, path: String): List<FileEntry> {
        if (!LocalStorage.hasFileAccess(context)) throw StorageAccessRequiredException()
        val directory = LocalFilePath.file(config.url, path)
        if (!directory.isDirectory) throw FileNotFoundException("Directory unavailable")
        val children = directory.listFiles() ?: throw SecurityException("Directory is not readable")
        return buildList {
            for (file in children) {
                kotlinx.coroutines.currentCoroutineContext().ensureActive()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && path == "Android" && (file.name == "data" || file.name == "obb")) continue
                val childPath = LocalDocumentPath.child(path, file.name)
                val resolved = try { LocalFilePath.file(config.url, childPath) } catch (_: SecurityException) { continue }
                add(FileEntry(file.name, childPath, resolved.isDirectory, resolved.length(), resolved.lastModified(),
                    MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()), resolved.toURI().toString()))
            }
        }.sortedWith(compareByDescending<FileEntry> { it.isDirectory }.thenBy { it.name.lowercase() })
    }

    override fun playItem(config: SourceConfig, entry: FileEntry) = PlayItem(
        id = "${config.id}:${entry.path}",
        title = entry.name,
        url = if (config.url.startsWith("file:")) LocalFilePath.file(config.url, entry.path).toURI().toString()
            else LocalDocumentPath.document(LocalDocumentPath.tree(config.url), entry.path).toString(),
    )
}

/** USB 移动存储热插拔浏览数据源实现。 */
class UsbStorageSource @Inject constructor(source: LocalSource) : BrowseSource by source {
    override val type = SourceType.USB_STORAGE
}

/** 本地存储与 USB 存储数据源的 Hilt 注入模块。 */
@Module
@InstallIn(SingletonComponent::class)
abstract class LocalModule {
    @Binds @IntoSet abstract fun local(impl: LocalSource): SourceProvider
    @Binds @IntoSet abstract fun usb(impl: UsbStorageSource): SourceProvider
    @Binds @IntoSet abstract fun discovery(impl: LocalStorageDiscovery): SourceDiscoveryProvider
}
