package com.flytech.juying.feature.browse

import androidx.lifecycle.ViewModelStore
import com.flytech.juying.core.data.BrowseRepository
import com.flytech.juying.core.data.SourceBrowseMemory
import com.flytech.juying.core.model.*
import com.flytech.juying.core.testing.FakeSourceRepository
import com.flytech.juying.core.testing.MainDispatcherRule
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class BrowseViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val context get() = RuntimeEnvironment.getApplication()

    @Test fun missingDirectoryRecoversButDeniedDirectoryKeepsItsLocation() = runTest {
        context.getSharedPreferences("source_browse", 0).edit().clear().commit()
        val memory = SourceBrowseMemory(context)
        val source = SourceConfig("recovery", "NAS", SourceType.SMB, "smb://nas/share")
        memory.select(source.id, SourceCapability.BROWSE)
        memory.put(source.id, "path", "gone-child")
        memory.put(source.id, "parents", "[\"\",\"gone-parent\"]")
        val calls = mutableListOf<String>()
        val repo = object : BrowseRepository {
            override suspend fun list(sourceId: String, path: String): List<FileEntry> {
                calls += path
                if (path.startsWith("gone")) throw java.io.FileNotFoundException()
                if (path == "private") throw SecurityException()
                return listOf(FileEntry("Private", "private", true))
            }
            override suspend fun playItem(sourceId: String, entry: FileEntry): PlayItem = error("unused")
        }
        val vm = BrowseViewModel(FakeSourceRepository(listOf(source)), repo, memory, main.testDispatcher)
        val store = ViewModelStore(); store.put("browse", vm)
        try {
            assertEquals(listOf("gone-child", "gone-parent", ""), calls)
            assertTrue(vm.ui.value.recovered)
            assertEquals("", memory.get(source.id, "path"))
            vm.enter(vm.ui.value.files.single())
            assertTrue(vm.ui.value.accessDenied)
            assertEquals("private", vm.ui.value.path)
            assertEquals("Private", memory.get(source.id, "location"))
            assertTrue(vm.ui.value.canGoUp)
        } finally { store.clear() }
    }

    @Test fun sourceIdsOwnPathsAndCredentialChangesReloadTheSameDirectory() = runTest {
        context.getSharedPreferences("source_browse", 0).edit().clear().commit()
        val memory = SourceBrowseMemory(context)
        val one = SourceConfig("one", "Same name", SourceType.SMB, "smb://one/share")
        val two = one.copy(id = "two", url = "smb://two/share")
        memory.put("one", "path", "opaque-one"); memory.put("two", "path", "opaque-two")
        memory.select("one", SourceCapability.BROWSE)
        val sources = FakeSourceRepository(listOf(one, two))
        val calls = mutableListOf<Pair<String, String>>()
        val repo = object : BrowseRepository {
            override suspend fun list(sourceId: String, path: String): List<FileEntry> { calls += sourceId to path; return emptyList() }
            override suspend fun playItem(sourceId: String, entry: FileEntry): PlayItem = error("unused")
        }
        val vm = BrowseViewModel(sources, repo, memory, main.testDispatcher)
        val store = ViewModelStore(); store.put("browse", vm)
        try {
            memory.select("two", SourceCapability.BROWSE)
            sources.upsert(two.copy(password = "updated"))
            assertEquals(listOf("one" to "opaque-one", "two" to "opaque-two", "two" to "opaque-two"), calls)
            assertEquals("updated", vm.ui.value.source?.password)
            assertEquals("opaque-one", memory.get("one", "path"))
        } finally { store.clear() }
    }

    @Test fun directoryParentUsesVisitedIdsAndCancelledResultCannotReplaceNewFolder() = runTest {
        context.getSharedPreferences("source_browse", 0).edit().clear().commit()
        val memory = SourceBrowseMemory(context)
        val source = SourceConfig("one", "NAS", SourceType.SMB, "smb://one/share")
        memory.select(source.id, SourceCapability.BROWSE)
        lateinit var slow: Continuation<List<FileEntry>>
        val repo = object : BrowseRepository {
            override suspend fun list(sourceId: String, path: String): List<FileEntry> =
                if (path == "opaque-slow") suspendCoroutine { slow = it } else listOf(FileEntry(path, path, false))
            override suspend fun playItem(sourceId: String, entry: FileEntry): PlayItem = error("unused")
        }
        val vm = BrowseViewModel(FakeSourceRepository(listOf(source)), repo, memory, main.testDispatcher)
        val store = ViewModelStore(); store.put("browse", vm)
        try {
            vm.enter(FileEntry("Slow", "opaque-slow", true))
            vm.up()
            slow.resume(listOf(FileEntry("Stale", "stale", false)))
            assertEquals("", vm.ui.value.path)
            assertEquals(listOf(""), vm.ui.value.files.map { it.path })
            assertFalse(vm.ui.value.canGoUp)
        } finally { store.clear() }
    }

    @Test fun rootSelectionBreadcrumbsPermissionsAndRemovalStayInTheNativeBrowser() = runTest {
        context.getSharedPreferences("source_browse", 0).edit().clear().commit()
        val memory = SourceBrowseMemory(context)
        val source = SourceConfig("usb", "USB", SourceType.USB_STORAGE, "file:///storage/USB", isReadOnly = true)
        val sources = FakeSourceRepository(listOf(source))
        var allowed = false
        val repo = object : BrowseRepository {
            override suspend fun list(sourceId: String, path: String): List<FileEntry> {
                if (!allowed) throw StorageAccessRequiredException()
                return listOf(FileEntry("Movies", "Movies", true))
            }
            override suspend fun playItem(sourceId: String, entry: FileEntry): PlayItem = error("unused")
        }
        val vm = BrowseViewModel(sources, repo, memory, main.testDispatcher)
        val store = ViewModelStore(); store.put("browse", vm)
        try {
            assertTrue(vm.ui.value.showRoots)
            assertEquals(listOf(source), vm.ui.value.sources)
            vm.selectSource(source.id)
            assertTrue(vm.ui.value.canRequestStorageAccess)
            allowed = true; vm.retry()
            assertFalse(vm.ui.value.canRequestStorageAccess)
            vm.enter(vm.ui.value.files.single())
            assertEquals(listOf("USB", "Movies"), vm.ui.value.breadcrumbs.map { it.label })
            vm.openCrumb("")
            assertEquals("", vm.ui.value.path)
            assertFalse(vm.ui.value.canGoUp)
            vm.up()
            assertTrue(vm.ui.value.showRoots)
            vm.selectSource(source.id)
            sources.delete(source.id)
            assertTrue(vm.ui.value.showRoots)
            assertNull(vm.ui.value.source)
        } finally { store.clear() }
    }

    @Test fun rememberedVolumeIsRestoredWhenDiscoveryArrivesAfterTheScreen() = runTest {
        context.getSharedPreferences("source_browse", 0).edit().clear().commit()
        val memory = SourceBrowseMemory(context)
        val source = SourceConfig("device", "Device", SourceType.LOCAL, "file:///storage/emulated/0", isReadOnly = true)
        memory.select(source.id, SourceCapability.BROWSE)
        memory.put(source.id, "path", "Movies")
        val sources = FakeSourceRepository()
        val repo = object : BrowseRepository {
            override suspend fun list(sourceId: String, path: String): List<FileEntry> = emptyList()
            override suspend fun playItem(sourceId: String, entry: FileEntry): PlayItem = error("unused")
        }
        val vm = BrowseViewModel(sources, repo, memory, main.testDispatcher)
        val store = ViewModelStore(); store.put("browse", vm)
        try {
            assertTrue(vm.ui.value.showRoots)
            sources.upsert(source)
            assertFalse(vm.ui.value.showRoots)
            assertEquals("Movies", vm.ui.value.path)
            vm.showRoots()
            sources.upsert(source.copy(name = "Renamed device"))
            assertTrue(vm.ui.value.showRoots)
        } finally { store.clear() }
    }
}
