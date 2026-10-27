package com.flytech.juying

import android.content.ContextWrapper
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.data.*
import com.flytech.juying.core.database.JuyingDatabase
import com.flytech.juying.core.database.SourceEntity
import com.flytech.juying.core.datastore.SettingsDataSource
import com.flytech.juying.core.model.*
import com.flytech.juying.source.api.LiveSource
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SourcePersistenceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val secrets = SourceSecrets()

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
}
