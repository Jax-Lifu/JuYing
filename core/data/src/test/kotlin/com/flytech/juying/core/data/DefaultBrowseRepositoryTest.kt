package com.flytech.juying.core.data

import com.flytech.juying.core.model.*
import com.flytech.juying.source.api.BrowseSource
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class DefaultBrowseRepositoryTest {
    @Test fun evictedDirectoryReloadsSubtitlesAndChangedCredentialsCannotReuseOldEntries() = runTest {
        var config = SourceConfig("nas", "NAS", SourceType.SMB, "smb://host/share", password = "first")
        val calls = mutableListOf<Pair<String?, String>>()
        val source = object : BrowseSource {
            override val type = SourceType.SMB
            override suspend fun list(config: SourceConfig, path: String): List<FileEntry> {
                calls += config.password to path
                return listOf(FileEntry("film.mp4", "$path/film.mp4", false), FileEntry("film.srt", "$path/film.srt", false))
            }
            override fun playItem(config: SourceConfig, entry: FileEntry) = PlayItem(entry.path, entry.name, "${config.url}/${entry.path}")
        }
        val sources = object : SourceRepository {
            override fun observeSources(capability: SourceCapability?) = flowOf(listOf(config))
            override suspend fun get(id: String) = config
            override suspend fun upsert(config: SourceConfig) = error("not used")
            override suspend fun delete(id: String) = error("not used")
        }
        val repository = DefaultBrowseRepository(SourceRegistry(setOf(source)), sources)
        val video = repository.list("nas", "first").first()
        repeat(8) { repository.list("nas", "dir-$it") }
        assertEquals("smb://host/share/first/film.srt", repository.playItem("nas", video).subtitles.single().url)
        assertEquals(2, calls.count { it.second == "first" })
        config = config.copy(password = "second")
        repository.playItem("nas", video)
        assertEquals("second" to "first", calls.last())
        assertEquals(3, calls.count { it.second == "first" })
    }
}
