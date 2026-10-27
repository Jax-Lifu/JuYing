package com.flytech.juying.source.local

import android.content.ContentProvider
import android.content.ContentValues
import android.content.pm.ProviderInfo
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import java.io.FileNotFoundException
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class LocalSourceTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private lateinit var provider: StorageProvider
    private val config = SourceConfig("local", "Movies", SourceType.LOCAL,
        "content://test.storage/tree/primary%3AMovies")

    @Before fun setup() {
        provider = StorageProvider().also {
            it.attachInfo(context, ProviderInfo().apply { authority = "test.storage" })
            ShadowContentResolver.registerProviderInternal("test.storage", it)
        }
    }

    @Test fun listsOpaqueDocumentsAndResolvesVideoAndSidecarsInsideTheGrantedTree() = runTest {
        val source = LocalSource(context, StandardTestDispatcher(testScheduler))
        val entries = source.list(config, "")
        assertEquals(listOf("Series", "movie.mkv", "movie.zh.srt"), entries.map { it.name })
        assertTrue(entries[1].isVideo)
        assertEquals(512L, entries[1].size)
        val nested = source.list(config, entries.first().path).single()
        assertEquals(entries.first().path, nested.path.substringBeforeLast('/'))
        assertEquals("primary:Movies/Series/episode.mkv",
            DocumentsContract.getDocumentId(Uri.parse(source.playItem(config, nested).url)))
        val played = source.playItem(config, entries[1].copy(uri = "content://untrusted/movie"), entries)
        assertEquals("test.storage", Uri.parse(played.url).authority)
        assertEquals("primary:Movies/movie.zh.srt", DocumentsContract.getDocumentId(Uri.parse(played.subtitles.single().url)))
        assertEquals(SourceType.USB_STORAGE, UsbStorageSource(source).type)
    }

    @Test fun unavailableAndRevokedDirectoriesStayVisibleAsFailures() = runTest {
        val source = LocalSource(context, StandardTestDispatcher(testScheduler))
        provider.denied = true
        try {
            source.list(config, "")
            fail("Revoked permission must fail")
        } catch (_: SecurityException) { }
    }

    @Test fun missingDirectoryIsNotReportedAsAnEmptyDirectory() = runTest {
        val source = LocalSource(context, StandardTestDispatcher(testScheduler))
        provider.missing = true
        try {
            source.list(config, "")
            fail("Missing directory must fail")
        } catch (_: FileNotFoundException) { }
    }

    @Test fun canceledLoadDoesNotQueryStorage() = runTest {
        val source = LocalSource(context, StandardTestDispatcher(testScheduler))
        val load = launch { source.list(config, "") }
        load.cancelAndJoin()
        assertEquals(0, provider.queries)
    }

    @Test fun canceledQueryCannotPublishDirectoryEntries() = runTest {
        val source = LocalSource(context, StandardTestDispatcher(testScheduler))
        lateinit var load: Job
        var returned = false
        provider.onQuery = { load.cancel() }
        load = launch { source.list(config, ""); returned = true }
        load.join()
        assertTrue(load.isCancelled)
        assertFalse(returned)
        assertEquals(1, provider.queries)
    }

    @Test fun pathsKeepSlashesPercentAndUnicodeInsideOneDocumentSegment() {
        val tree = LocalDocumentPath.tree(config.url)
        val id = "primary:Movies/中文 100%/episode.mkv"
        val path = LocalDocumentPath.child("", id)
        assertFalse(path.contains('/'))
        assertEquals(id, DocumentsContract.getDocumentId(LocalDocumentPath.document(tree, path)))
        assertThrows(IllegalArgumentException::class.java) { LocalDocumentPath.document(tree, "../movie.mkv") }
        assertThrows(IllegalArgumentException::class.java) { LocalDocumentPath.tree("file:///sdcard/Movies") }
    }

    @Test fun selectingTheSameTreeProducesOneStableSource() = runTest {
        val first = LocalStorage.configForTree(context, Uri.parse(config.url))
        val second = LocalStorage.configForTree(context, Uri.parse(config.url))
        assertEquals(first, second)
        assertEquals("Movies", first.name)
        assertEquals(SourceType.LOCAL, first.type)
    }

    class StorageProvider : ContentProvider() {
        var denied = false
        var missing = false
        var queries = 0
        var onQuery: (() -> Unit)? = null
        override fun onCreate() = true
        override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, order: String?): Cursor? {
            queries++
            onQuery?.invoke()
            if (denied) throw SecurityException("Permission revoked")
            if (missing) return null
            val cursor = MatrixCursor(projection)
            if (uri.lastPathSegment != "children") {
                cursor.addRow(arrayOf("Movies", Document.MIME_TYPE_DIR))
            } else if (DocumentsContract.getDocumentId(uri) == "primary:Movies/Series") {
                cursor.addRow(arrayOf<Any?>("primary:Movies/Series/episode.mkv", "episode.mkv", "video/x-matroska", 256L, 0L))
            } else {
                cursor.addRow(arrayOf<Any?>("primary:Movies/movie.mkv", "movie.mkv", "video/x-matroska", 512L, 0L))
                cursor.addRow(arrayOf("primary:Movies/Series", "Series", Document.MIME_TYPE_DIR, null, null))
                cursor.addRow(arrayOf<Any?>("primary:Movies/movie.zh.srt", "movie.zh.srt", "application/x-subrip", 128L, 0L))
            }
            return cursor
        }
        override fun getType(uri: Uri): String? = null
        override fun insert(uri: Uri, values: ContentValues?): Uri? = error("Read only")
        override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = error("Read only")
        override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?) = error("Read only")
    }
}
