package com.flytech.juying

import android.content.ContextWrapper
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.*
import com.flytech.juying.core.database.JuyingDatabase
import com.flytech.juying.core.database.SourceDao
import com.flytech.juying.core.database.SourceEntity
import com.flytech.juying.core.datastore.SettingsDataSource
import com.flytech.juying.core.model.*
import com.flytech.juying.source.api.LiveSource
import com.flytech.juying.source.api.NetworkStorageSource
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SourcePersistenceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val secrets = SourceSecrets()

    @Test fun hostnameResolutionDoesNotDelaySourcesOrOverwriteLaterEdits() = runBlocking {
        val db = Room.inMemoryDatabaseBuilder(context, JuyingDatabase::class.java).build()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val renamed = CompletableDeferred<Unit>()
        val calls = AtomicInteger()
        val dao = object : SourceDao by db.sourceDao() {
            override suspend fun renameIfUnchanged(snapshot: SourceEntity, name: String): Boolean =
                try { db.sourceDao().renameIfUnchanged(snapshot, name) }
                finally { renamed.complete(Unit) }
        }
        val provider = object : HostnameStorage() {
            override fun resolveHostname(address: String): String {
                calls.incrementAndGet()
                started.countDown()
                release.await(10, TimeUnit.SECONDS)
                return "NAS"
            }
        }
        try {
            val repository = DefaultSourceRepository(dao, SourceRegistry(setOf(provider)), emptySet(), context,
                secrets, emptySet(), SettingsDataSource(context))
            val source = SourceConfig("active", "A · 192.168.1.2", SourceType.SMB, "smb://192.168.1.2/share")
            val disabled = source.copy(id = "disabled", name = "Z · 192.168.1.3", url = "smb://192.168.1.3/share", enabled = false)
            repository.upsert(source)
            repository.upsert(disabled)
            val first = async { withTimeout(2_000) { repository.observeSources().first() } }
            assertTrue(withContext(Dispatchers.IO) { started.await(5, TimeUnit.SECONDS) })
            assertEquals(setOf(source, disabled), first.await().toSet())
            // A second subscriber must share the pending lookup, and edits must remain observable.
            assertEquals(setOf(source, disabled), withTimeout(2_000) { repository.observeSources().first() }.toSet())
            val edited = source.copy(name = "My NAS", password = "new-password")
            repository.upsert(edited)
            assertEquals(setOf(edited, disabled), withTimeout(2_000) { repository.observeSources().first() }.toSet())
            release.countDown()
            withTimeout(5_000) { renamed.await() }
            assertEquals(edited, repository.get(source.id))
            assertEquals(1, calls.get())
        } finally {
            release.countDown()
            if (started.count == 0L) withTimeoutOrNull(5_000) { renamed.await() }
            db.close()
        }
    }

    @Test fun hostnameIsUpdatedAfterTheInitialSourceSnapshot() = runBlocking {
        val db = Room.inMemoryDatabaseBuilder(context, JuyingDatabase::class.java).build()
        try {
            val provider = object : HostnameStorage() {
                override fun resolveHostname(address: String) = "NAS"
            }
            val repository = DefaultSourceRepository(db.sourceDao(), SourceRegistry(setOf(provider)), emptySet(), context,
                secrets, emptySet(), SettingsDataSource(context))
            val source = SourceConfig("nas", "share · 192.168.1.2", SourceType.SMB, "smb://192.168.1.2/share")
            repository.upsert(source)
            val resolved = withTimeout(5_000) { repository.observeSources().first { it.single().name == "share · NAS" } }
            assertEquals(source.copy(name = "share · NAS"), resolved.single())
        } finally { db.close() }
    }

    private abstract class HostnameStorage : NetworkStorageSource {
        override val type = SourceType.SMB
        override val capabilities = emptySet<SourceCapability>()
        override fun discoverDevices() = emptyFlow<NetworkStorageDevice>()
        override fun manualDevice(address: String): NetworkStorageDevice = error("Unused")
        override suspend fun shares(device: NetworkStorageDevice, username: String, password: String, domain: String): List<String> = error("Unused")
        override fun configuration(device: NetworkStorageDevice, share: String, username: String, password: String, domain: String): SourceConfig = error("Unused")
    }

    @Test fun resolvedHostnameOnlyRenamesTheUnchangedSnapshot() = runBlocking {
        val db = Room.inMemoryDatabaseBuilder(context, JuyingDatabase::class.java).build()
        try {
            val dao = db.sourceDao()
            val snapshot = SourceEntity("nas", "share · 192.168.1.2", "SMB", "smb://192.168.1.2/share",
                true, "user", "password")
            dao.upsert(snapshot)
            assertTrue(dao.renameIfUnchanged(snapshot, "share · NAS"))
            assertEquals(snapshot.copy(name = "share · NAS"), dao.get(snapshot.id))
            for (edited in listOf(snapshot.copy(password = "new-password"), snapshot.copy(enabled = false),
                snapshot.copy(name = "My NAS"), snapshot.copy(url = "smb://other/share"))) {
                dao.upsert(edited)
                assertFalse(dao.renameIfUnchanged(snapshot, "share · NAS"))
                assertEquals(edited, dao.get(snapshot.id))
            }
            dao.delete(snapshot.id)
            assertFalse(dao.renameIfUnchanged(snapshot, "share · NAS"))
            assertNull(dao.get(snapshot.id))
        } finally { db.close() }
    }

    @Test fun credentialsMigrateWithoutLosingFieldsOrOverwritingNewerEdits() = runBlocking {
        val db = Room.inMemoryDatabaseBuilder(context, JuyingDatabase::class.java).build()
        try {
            val dao = db.sourceDao()
            val row = SourceEntity("legacy", "NAS", "SMB", "smb://host/share", true, "user", "password",
                """{"domain":"office","token":"private-value"}""")
            dao.upsert(row)
            val repository = DefaultSourceRepository(dao, SourceRegistry(emptySet()), emptySet(), context,
                secrets, emptySet(), SettingsDataSource(context))
            val source = repository.get(row.id)!!
            assertEquals("password", source.password)
            assertEquals("private-value", source.extra["token"])
            val stored = dao.get(row.id)!!
            assertTrue(listOf(stored.url, stored.username!!, stored.password!!, stored.extraJson).all(secrets::isEncrypted))
            assertEquals(source, repository.get(row.id))
            val edited = source.copy(name = "Renamed", password = "new-password")
            repository.upsert(edited)
            dao.protect(row.id, stored.url, stored.username, stored.password, stored.extraJson,
                row.url, row.username, row.password, row.extraJson)
            assertEquals(edited, repository.get(row.id))
            assertTrue(runCatching { secrets.decrypt(stored.password!!, "another:password") }.isFailure)
            assertTrue(runCatching { secrets.decrypt(stored.password!!.dropLast(4) + "AAAA", "legacy:password") }.isFailure)
        } finally { db.close() }
    }

    @Test fun deletingAPresetSurvivesRepositoryRecreation() = runBlocking {
        val db = Room.inMemoryDatabaseBuilder(context, JuyingDatabase::class.java).build()
        try {
            val preset = SourceConfig("test-preset-${UUID.randomUUID()}", "Preset", SourceType.TVBOX, "https://example.test/config")
            fun repository() = DefaultSourceRepository(db.sourceDao(), SourceRegistry(emptySet()), emptySet(), context,
                secrets, setOf(preset), SettingsDataSource(context))
            assertEquals(listOf(preset), repository().observeSources().first())
            repository().upsert(preset.copy(name = "My name", enabled = false))
            assertEquals("My name", repository().observeSources().first().single().name)
            repository().delete(preset.id)
            assertTrue(repository().observeSources().first().isEmpty())
        } finally { db.close() }
    }

    @Test fun changedSourceNeverReusesOldChannelsAndOfflineCacheIsEncrypted() = runBlocking {
        val dir = File(context.cacheDir, "source-cache-test-${UUID.randomUUID()}").apply { mkdirs() }
        val cacheContext = object : ContextWrapper(context) { override fun getCacheDir() = dir }
        val db = Room.inMemoryDatabaseBuilder(context, JuyingDatabase::class.java).build()
        var offline = false
        val provider = object : LiveSource {
            override val type = SourceType.IPTV
            override suspend fun channels(config: SourceConfig): List<ChannelGroup> {
                check(!offline)
                return listOf(ChannelGroup("Test", listOf(Channel("one", config.name,
                    urls = listOf(config.url), lines = listOf(PlayLine(config.url, headers = mapOf("Authorization" to "private-token")))))))
            }
        }
        try {
            val registry = SourceRegistry(setOf(provider))
            val sources = DefaultSourceRepository(db.sourceDao(), registry, emptySet(), context, secrets, emptySet(), SettingsDataSource(context))
            fun live() = DefaultLiveRepository(cacheContext, registry, sources, Dispatchers.IO, secrets)
            val source = SourceConfig("cache-test", "Old", SourceType.IPTV, "https://example.test/old")
            sources.upsert(source)
            val repository = live()
            assertEquals("Old", repository.channelGroups(source.id).toList().last().single().channels.single().name)
            val files = File(dir, "live_channels").listFiles()!!
            assertEquals(1, files.size)
            assertTrue(secrets.isEncrypted(files.single().readText()))
            assertFalse(files.single().readText().contains("private-token"))
            offline = true
            assertEquals("Old", live().channelGroups(source.id).toList().last().single().channels.single().name)
            sources.upsert(source.copy(name = "New", url = "https://example.test/new", password = "changed"))
            assertTrue(runCatching { repository.channelGroups(source.id).toList() }.isFailure)
            offline = false
            assertEquals("New", repository.channelGroups(source.id).toList().single().single().channels.single().name)
        } finally { db.close(); dir.deleteRecursively() }
    }

    @Test fun connectionCheckAcceptsLiveOnlyTvboxWithoutStartingASpider() = runBlocking {
        val db = Room.inMemoryDatabaseBuilder(context, JuyingDatabase::class.java).build()
        val client = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            val content = when (request.url.encodedPath) {
                "/config" -> """{"lives":[{"url":"https://source.test/live.m3u"}]}"""
                "/live.m3u" -> "#EXTM3U\n#EXTINF:-1,Channel\nhttps://source.test/live.m3u8"
                else -> error("Unexpected request")
            }
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body(okhttp3.ResponseBody.create(null, content)).build()
        }.build()
        try {
            val provider = com.flytech.juying.source.tvbox.TvboxSource(javax.inject.Provider { client }, Dispatchers.Default,
                javax.inject.Provider { error("Live-only check must not start a Spider") })
            val sources = DefaultSourceRepository(db.sourceDao(), SourceRegistry(setOf(provider)), emptySet(), context,
                secrets, emptySet(), SettingsDataSource(context))
            val config = SourceConfig("live-only", "Live", SourceType.TVBOX, "https://source.test/config")
            assertEquals(1, sources.check(config))
            assertTrue(runCatching { sources.check(config.copy(extra = mapOf("siteKey" to "missing"))) }.isFailure)
        } finally {
            db.close()
            client.dispatcher.executorService.shutdownNow()
        }
    }
}
