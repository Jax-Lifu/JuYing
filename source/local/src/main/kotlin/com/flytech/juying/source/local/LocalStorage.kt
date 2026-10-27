package com.flytech.juying.source.local

import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import java.io.FileNotFoundException
import java.io.File
import java.net.URI
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Reads an already-granted tree off the UI thread; repeated selection keeps the same source ID. */
object LocalStorage {
    /** Media-only grants omit sidecar subtitles, so raw browsing requires full shared-file access. */
    fun hasFileAccess(context: Context): Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
        Environment.isExternalStorageManager()
    else context.checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    /** The caller persists the read grant. Missing directories and revoked grants are propagated. */
    suspend fun configForTree(context: Context, uri: Uri): SourceConfig = withContext(Dispatchers.IO) {
        val tree = LocalDocumentPath.tree(uri.toString())
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val root = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
        val name = context.contentResolver.query(root,
            arrayOf(Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE), null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) throw FileNotFoundException("Directory unavailable")
            require(cursor.getString(1) == Document.MIME_TYPE_DIR) { "Select a directory" }
            cursor.getString(0)
        } ?: throw FileNotFoundException("Directory unavailable")
        val volumeId = rootId.substringBefore(':')
        val removable = tree.authority == "com.android.externalstorage.documents" &&
            context.getSystemService(StorageManager::class.java).storageVolumes.any {
                it.isRemovable && it.uuid.equals(volumeId, ignoreCase = true)
            }
        SourceConfig(
            id = "storage:${UUID.nameUUIDFromBytes(tree.toString().toByteArray(Charsets.UTF_8))}",
            name = name.ifBlank { rootId },
            type = if (removable) SourceType.USB_STORAGE else SourceType.LOCAL,
            url = tree.toString(),
        )
    }
}

/** Encoded path segments and canonical checks keep traversal and symlinks inside the selected root. */
internal object LocalFilePath {
    fun file(url: String, path: String): File {
        val root = File(URI(url)).canonicalFile
        val file = if (path.isEmpty()) root else path.split('/').fold(root) { parent, segment ->
            val name = Uri.decode(segment)
            require(name.isNotEmpty() && name != "." && name != ".." && '/' !in name && '\\' !in name && Uri.encode(name) == segment) {
                "Invalid directory path"
            }
            File(parent, name)
        }.canonicalFile
        if (file != root && !file.path.startsWith(root.path + File.separator)) throw SecurityException("Path leaves storage root")
        return file
    }
}

/** Encode each opaque document ID separately so parent lookup and subtitle caching stay lossless. */
internal object LocalDocumentPath {
    fun tree(url: String): Uri {
        val uri = Uri.parse(url)
        require(uri.scheme == "content" && !uri.authority.isNullOrBlank() && DocumentsContract.isTreeUri(uri)) {
            "Select a storage directory"
        }
        return DocumentsContract.buildTreeDocumentUri(uri.authority, DocumentsContract.getTreeDocumentId(uri))
    }

    fun child(parent: String, documentId: String): String =
        listOf(parent, Uri.encode(documentId)).filter(String::isNotEmpty).joinToString("/")

    fun document(tree: Uri, path: String): Uri {
        val id = if (path.isEmpty()) DocumentsContract.getTreeDocumentId(tree) else {
            require(path.split('/').all { it.isNotEmpty() && it != "." && it != ".." && Uri.encode(Uri.decode(it)) == it }) { "Invalid directory path" }
            Uri.decode(path.substringAfterLast('/'))
        }
        // The tree URI preserves Android's grant boundary even when document IDs are opaque.
        return DocumentsContract.buildDocumentUriUsingTree(tree, id)
    }
}
