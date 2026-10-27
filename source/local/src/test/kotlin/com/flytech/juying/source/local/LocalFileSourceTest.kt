package com.flytech.juying.source.local

import android.Manifest
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.model.StorageAccessRequiredException
import java.io.File
import java.io.FileNotFoundException
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class LocalFileSourceTest {
    @get:Rule val temporary = TemporaryFolder()
    private val context get() = RuntimeEnvironment.getApplication()

    @Test fun rawFoldersResolveVideoAndSidecarsWithoutTrustingEntryUris() = runTest {
        shadowOf(context).grantPermissions(Manifest.permission.READ_EXTERNAL_STORAGE)
        val root = temporary.newFolder("storage")
        val folder = File(root, "中文 100%").apply { mkdir() }
        File(folder, "movie.mkv").writeText("video")
        File(folder, "movie.zh.srt").writeText("subtitle")
        val config = SourceConfig("raw", "Device", SourceType.LOCAL, root.toURI().toString())
        val source = LocalSource(context, StandardTestDispatcher(testScheduler))
        val entry = source.list(config, "").single()
        assertTrue(entry.isDirectory)
        val files = source.list(config, entry.path)
        assertEquals(listOf("movie.mkv", "movie.zh.srt"), files.map { it.name })
        val play = source.playItem(config, files.first().copy(uri = "file:///untrusted"), files)
        assertEquals(File(folder, "movie.mkv").canonicalFile.toURI().toString(), play.url)
        assertEquals(File(folder, "movie.zh.srt").canonicalFile.toURI().toString(), play.subtitles.single().url)
        assertThrows(IllegalArgumentException::class.java) { LocalFilePath.file(config.url, "../outside") }
        assertThrows(IllegalArgumentException::class.java) { LocalFilePath.file(config.url, "%2E%2E/outside") }
        assertThrows(IllegalArgumentException::class.java) { LocalFilePath.file(config.url, "%2Foutside") }
    }

    @Test fun deniedAndMissingStorageAreNotEmptyDirectories() = runTest {
        val root = temporary.newFolder("storage")
        val config = SourceConfig("raw", "Device", SourceType.LOCAL, root.toURI().toString())
        val source = LocalSource(context, StandardTestDispatcher(testScheduler))
        shadowOf(context).denyPermissions(Manifest.permission.READ_EXTERNAL_STORAGE)
        try { source.list(config, ""); fail("Permission must be requested") } catch (_: StorageAccessRequiredException) { }
        shadowOf(context).grantPermissions(Manifest.permission.READ_EXTERNAL_STORAGE)
        assertTrue(source.list(config, "").isEmpty())
        assertTrue(root.delete())
        try { source.list(config, ""); fail("Missing volume must fail") } catch (_: FileNotFoundException) { }
    }

    @Test fun canceledRawListingCannotPublishAnErrorOrResult() = runTest {
        val config = SourceConfig("raw", "Device", SourceType.LOCAL, temporary.root.toURI().toString())
        val source = LocalSource(context, StandardTestDispatcher(testScheduler))
        var returned = false
        val load = launch { source.list(config, ""); returned = true }
        load.cancelAndJoin()
        assertFalse(returned)
    }
}
