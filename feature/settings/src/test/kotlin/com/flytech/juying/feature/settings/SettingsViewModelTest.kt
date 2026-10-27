package com.flytech.juying.feature.settings

import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.*
import com.flytech.juying.core.testing.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class SettingsViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val setup = UrlSourceSetup(SourceType.TVBOX, "TVBox", "Trusted sources")

    @Test fun directoryActionsUseCurrentConfigAndPreserveMetadata() = runTest {
        val original = SourceConfig("folder", "Folder", SourceType.LOCAL, "content://provider/tree/one", extra = mapOf("tree" to "one"))
        val data = FakeSourceRepository(listOf(original))
        val vm = SettingsViewModel(data)
        runCurrent()
        val updated = original.copy(name = "Renamed", enabled = false)
        data.upsert(updated)
        vm.toggleSource(original); runCurrent()
        assertEquals(updated.copy(enabled = true), data.get(original.id))
        vm.removeSource(original.id); runCurrent()
        assertNull(data.get(original.id))
        assertFalse(vm.ui.value.saving)
    }

    @Test fun directoryActionsIgnoreMissingAndReadOnlySources() = runTest {
        val builtin = SourceConfig("builtin", "Storage", SourceType.LOCAL, "content://provider/tree/one", isReadOnly = true)
        val data = FakeSourceRepository(listOf(builtin))
        val vm = SettingsViewModel(data)
        runCurrent()
        vm.toggleSource(builtin); vm.removeSource(builtin.id)
        vm.toggleSource(builtin.copy(id = "missing", isReadOnly = false)); vm.removeSource("missing")
        runCurrent()
        assertEquals(listOf(builtin), vm.ui.value.sources)
        assertFalse(vm.ui.value.saving)
    }

    @Test fun directoryActionsBlockOverlappingMutations() = runTest {
        val original = SourceConfig("folder", "Folder", SourceType.LOCAL, "content://provider/tree/one")
        val data = FakeSourceRepository(listOf(original))
        val pending = kotlinx.coroutines.CompletableDeferred<Unit>()
        var writes = 0
        val vm = SettingsViewModel(object : SourceRepository by data {
            override suspend fun upsert(config: SourceConfig) { writes++; pending.await(); data.upsert(config) }
        })
        runCurrent()
        vm.toggleSource(original); runCurrent()
        assertTrue(vm.ui.value.saving)
        vm.toggleSource(original); vm.removeSource(original.id); runCurrent()
        assertEquals(1, writes)
        pending.complete(Unit); runCurrent()
        assertEquals(original.copy(enabled = false), data.get(original.id))
        assertFalse(vm.ui.value.saving)
    }

    @Test fun directoryActionsRejectSourceThatBecameReadOnly() = runTest {
        val original = SourceConfig("folder", "Folder", SourceType.LOCAL, "content://provider/tree/one")
        val data = FakeSourceRepository(listOf(original))
        val vm = SettingsViewModel(object : SourceRepository by data {
            override suspend fun get(id: String) = data.get(id)?.copy(isReadOnly = true)
        })
        runCurrent()
        vm.toggleSource(original); runCurrent()
        assertEquals(SourceFormMessage.FAILED, vm.ui.value.message)
        assertFalse(vm.ui.value.saving)
        vm.removeSource(original.id); runCurrent()
        assertEquals(SourceFormMessage.FAILED, vm.ui.value.message)
        assertEquals(original, data.get(original.id))
        assertFalse(vm.ui.value.saving)
    }

    @Test fun acceptsChineseSubscriptionDomain() = runTest {
        val data = FakeSourceRepository(emptyList())
        val vm = SettingsViewModel(object : SourceRepository by data { override fun urlSetups() = listOf(setup) })
        vm.add(setup); vm.change("中文地址", "http://www.饭太硬.net/tv", true)
        vm.save(); runCurrent()
        assertEquals("http://www.饭太硬.net/tv", vm.ui.value.sources.single().url)
    }

    @Test fun connectionCheckDoesNotSaveAndCancellationKeepsNoLateResult() = runTest {
        val data = FakeSourceRepository(emptyList())
        val result = kotlinx.coroutines.CompletableDeferred<Int>()
        val sources = object : SourceRepository by data {
            override fun urlSetups() = listOf(setup)
            override suspend fun check(config: SourceConfig): Int = result.await()
        }
        val vm = SettingsViewModel(sources)
        vm.add(setup); vm.change("Draft", "https://example.test", true)
        vm.check(); runCurrent()
        assertTrue(vm.ui.value.checking)
        vm.save(); runCurrent()
        assertTrue(vm.ui.value.sources.isEmpty())
        vm.cancel(); result.complete(3); runCurrent()
        assertNull(vm.ui.value.editor)
        assertFalse(vm.ui.value.checking)
        assertEquals(SourceFormMessage.NONE, vm.ui.value.message)
    }

    @Test fun importsContentPlaylistAndPersistsGuideAndHeaders() = runTest {
        val iptv = UrlSourceSetup(SourceType.IPTV, "IPTV", "Playlist", setOf("http", "https", "content"), fileMimeTypes = listOf("*/*"), epg = true)
        val data = FakeSourceRepository(emptyList())
        val vm = SettingsViewModel(object : SourceRepository by data {
            override fun urlSetups() = listOf(iptv)
            override suspend fun check(config: SourceConfig) = 2
        })
        vm.add(iptv); vm.selectFile("content://provider.test/documents/1", "Channels.m3u")
        vm.change("Channels", vm.ui.value.editor!!.url, true, epgUrl = "ftp://bad/guide", userAgent = "Custom/1")
        vm.save(); runCurrent()
        assertEquals(SourceFormMessage.INVALID_EPG, vm.ui.value.message)
        vm.change("Channels", vm.ui.value.editor!!.url, true, epgUrl = "https://example.test/guide.xml", referer = "https://example.test/")
        vm.check(); runCurrent()
        assertEquals(SourceFormMessage.CHECKED, vm.ui.value.message)
        assertEquals(2, vm.ui.value.checkedCount)
        assertTrue(vm.ui.value.sources.isEmpty())
        vm.save(); runCurrent()
        val saved = vm.ui.value.sources.single()
        assertEquals("Custom/1", saved.extra["userAgent"])
        assertEquals("https://example.test/guide.xml", saved.extra["epgUrl"])
        assertTrue(saved.url.startsWith("content://"))
    }

    @Test fun smbRequiresShareAndUpdatesCredentialsWithoutLosingOptions() = runTest {
        val smb = UrlSourceSetup(SourceType.SMB, "SMB", "Share", schemes = setOf("smb"), credentials = true, requiresPath = true)
        val original = SourceConfig("nas", "NAS", SourceType.SMB, "smb://server/share", username = "old", password = "old", extra = mapOf("domain" to "WORKGROUP"))
        val data = FakeSourceRepository(listOf(original))
        val vm = SettingsViewModel(object : SourceRepository by data { override fun urlSetups() = listOf(smb) })
        runCurrent()
        vm.edit("nas")
        assertFalse(vm.ui.value.editor!!.dirty)
        vm.change("NAS", "smb://server", true, "new", "new-secret")
        assertTrue(vm.ui.value.editor!!.dirty)
        vm.save(); runCurrent()
        assertEquals(SourceFormMessage.INVALID_URL, vm.ui.value.message)
        assertEquals(original, data.get("nas"))
        vm.change("NAS", "smb://server/share", true, "new", "new-secret")
        vm.save(); runCurrent()
        assertEquals("new-secret", data.get("nas")!!.password)
        assertEquals(original.extra, data.get("nas")!!.extra)
    }

    @Test fun rejectsInvalidUrlAndPreservesExistingCredentialsAndOptions() = runTest {
        val original = SourceConfig("one", "Old", SourceType.TVBOX, "https://example.test", username = "user",
            password = "secret", extra = mapOf("repoUrl" to "nested"))
        val data = FakeSourceRepository(listOf(original))
        val sources = object : SourceRepository by data { override fun urlSetups() = listOf(setup) }
        val vm = SettingsViewModel(sources)
        runCurrent()
        vm.edit(original.id)
        vm.change("New", "file:///tmp/config", false)
        vm.save()
        runCurrent()
        assertEquals(SourceFormMessage.INVALID_URL, vm.ui.value.message)
        assertEquals(original, data.get(original.id))
        vm.change("New", "https://example.test/new", false)
        vm.save()
        runCurrent()
        val saved = checkNotNull(data.get(original.id))
        assertEquals("secret", saved.password)
        assertEquals(original.extra, saved.extra)
        assertFalse(saved.enabled)
        assertNull(vm.ui.value.editor)
    }
}
