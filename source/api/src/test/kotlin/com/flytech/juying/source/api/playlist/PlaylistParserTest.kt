package com.flytech.juying.source.api.playlist

import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.FileEntry
import com.flytech.juying.core.model.PlayItem
import com.flytech.juying.core.model.SidecarSubtitles
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.source.api.BrowseSource
import com.flytech.juying.source.api.LiveSource
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaylistParserTest {

    @Test fun rejectsErrorPagesAndNonMediaLinks() {
        assertTrue(PlaylistParser.parse("<html>Oops,try later</html>").isEmpty())
        assertTrue(PlaylistParser.parse("Unsafe,javascript:alert(1)\nLocal,file:///private/secret").isEmpty())
        assertEquals(1, PlaylistParser.parse("Multicast,udp://@239.1.1.1:1234").single().channels.size)
    }

    @Test
    fun parsesM3uAndMergesDuplicateChannelsWithVlcHeaders() {
        val text = """
            #EXTM3U
            #EXTINF:-1 tvg-id="cctv1" tvg-logo="http://x/1.png" group-title="央视",CCTV-1 综合
            #EXTVLCOPT:http-user-agent=CustomUA/1.0
            #EXTVLCOPT:http-referrer=https://tv.cctv.com/
            http://a/1.m3u8
            #EXTINF:-1 group-title="央视",CCTV-1 综合
            http://b/1.m3u8
            #EXTINF:-1 group-title="卫视",湖南卫视
            http://a/hn.m3u8
        """.trimIndent()
        val groups = PlaylistParser.parse(text)
        assertEquals(listOf("央视", "卫视"), groups.map { it.name })
        val cctv1 = groups[0].channels.single()
        assertEquals(listOf("http://a/1.m3u8", "http://b/1.m3u8"), cctv1.urls)
        assertEquals("cctv1", cctv1.epgId)
        assertEquals("http://x/1.png", cctv1.logo)
        assertEquals("CustomUA/1.0", cctv1.lines[0].headers["User-Agent"])
        assertEquals("https://tv.cctv.com/", cctv1.lines[0].headers["Referer"])
    }

    @Test
    fun parsesTxtFormat() {
        val text = "央视,#genre#\nCCTV-1,http://a/1.m3u8\nCCTV-2,http://a/2.m3u8\n卫视,#genre#\n湖南卫视,http://a/hn.m3u8"
        val groups = PlaylistParser.parse(text)
        assertEquals(2, groups.size)
        assertEquals(2, groups[0].channels.size)
        assertEquals("http://a/hn.m3u8", groups[1].channels.single().urls.single())
    }

    @Test
    fun liveSourceResolvePopulatesPrimaryHeadersAndBackupLines() = runTest {
        val fakeLive = object : LiveSource {
            override val type = SourceType.IPTV
            override suspend fun channels(config: SourceConfig) = emptyList<com.flytech.juying.core.model.ChannelGroup>()
        }
        val group = PlaylistParser.parse(
            """
            #EXTM3U
            #EXTINF:-1 group-title="央视",CCTV-1
            #EXTVLCOPT:http-user-agent=UA1
            http://line1.m3u8
            #EXTINF:-1 group-title="央视",CCTV-1
            http://line2.m3u8
            """.trimIndent(),
        ).single()
        val ch: Channel = group.channels.single()
        val item = fakeLive.resolve(SourceConfig("iptv-1", "IPTV", SourceType.IPTV, "http://x"), ch)
        assertEquals("http://line1.m3u8", item.url)
        assertEquals("UA1", item.headers["User-Agent"])
        assertEquals(1, item.backupLines.size)
        assertEquals("http://line2.m3u8", item.backupLines.single().url)
        assertTrue(SourceCapability.LIVE in fakeLive.capabilities)
    }

    @Test
    fun browseSourceMatchesSidecarSubtitlesAcrossUnifiedStorage() {
        val fakeBrowse = object : BrowseSource {
            override val type = SourceType.WEBDAV
            override suspend fun list(config: SourceConfig, path: String) = emptyList<FileEntry>()
            override fun playItem(config: SourceConfig, entry: FileEntry) =
                PlayItem(id = entry.path, title = entry.name, url = "${config.url}/${entry.path}")
        }
        val video = FileEntry(name = "Interstellar.2014.mkv", path = "movies/Interstellar.2014.mkv", isDirectory = false)
        val siblings = listOf(
            video,
            FileEntry(name = "Interstellar.2014.zh.ass", path = "movies/Interstellar.2014.zh.ass", isDirectory = false),
            FileEntry(name = "Interstellar.2014.srt", path = "movies/Interstellar.2014.srt", isDirectory = false),
            FileEntry(name = "OtherMovie.srt", path = "movies/OtherMovie.srt", isDirectory = false),
        )
        val cfg = SourceConfig("dav-1", "WebDAV", SourceType.WEBDAV, "http://nas:5244/dav")
        val playItem = fakeBrowse.playItem(cfg, video, siblings)
        assertTrue(video.isVideo)
        assertEquals(2, playItem.subtitles.size)
        assertEquals("zh", playItem.subtitles[0].lang)
        assertEquals("text/x-ssa", playItem.subtitles[0].mimeType)
        assertEquals("application/x-subrip", playItem.subtitles[1].mimeType)
    }
}
