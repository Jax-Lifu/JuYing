package com.flytech.juying.source.cctv

import org.junit.Assert.*
import org.junit.Test

class CctvH5ePlaylistTest {
    @Test fun liveMasterRetainsHdAndManualLowerQualitiesWithoutCodecMetadata() {
        val resolutions = listOf("1280x720", "1024x576", "854x480", "640x360")
        val master = "#EXTM3U\n" + resolutions.mapIndexed { index, resolution ->
            "#EXT-X-STREAM-INF:BANDWIDTH=${1800000 - index * 400000},RESOLUTION=$resolution\n$index.m3u8?key=test"
        }.joinToString("\n")
        val rewritten = CctvH5ePlaylist.rewriteLiveMaster(master, "https://media.test/live/master.m3u8")
        resolutions.forEachIndexed { index, resolution ->
            assertTrue(rewritten.contains("RESOLUTION=$resolution"))
            assertTrue(rewritten.contains("cctvcdrm+https://media.test/live/$index.m3u8?key=test"))
        }
        assertEquals(4, rewritten.lineSequence().count { it.startsWith("#EXT-X-STREAM-INF:") })
        assertEquals("https://media.test/live/0.m3u8?key=test",
            CctvH5ePlaylist.highestHd(master, "https://media.test/live/master.m3u8"))
    }

    @Test fun liveMasterRejectsMissingHdAndUnsupportedHighestButOmitsUnsupportedLowerCodec() {
        val master = """#EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720,CODECS="avc1.64001e,mp4a.40.2"
            hd.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=600000,RESOLUTION=640x360,CODECS="hvc1.1.6.L93.B0,mp4a.40.2"
            sd.m3u8
        """.trimIndent()
        val base = "https://media.test/master.m3u8"
        val rewritten = CctvH5ePlaylist.rewriteLiveMaster(master, base)
        assertTrue(rewritten.contains("hd.m3u8"))
        assertFalse(rewritten.contains("sd.m3u8"))
        assertTrue(runCatching { CctvH5ePlaylist.rewriteLiveMaster(master.replace("1280x720", "1024x576"), base) }.isFailure)
        assertTrue(runCatching { CctvH5ePlaylist.rewriteLiveMaster(master.replace("avc1.64001e", "hvc1.1.6.L93.B0"), base) }.isFailure)
    }

    @Test fun liveMasterRejectsExternalRenditionsAndKeysInsteadOfBypassingTheAdapter() {
        val master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720\nhd.m3u8\n"
        val unsupported = listOf("#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",URI=\"audio.m3u8\"",
            "#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"key\"")
        unsupported.forEach { tag ->
            assertTrue(runCatching { CctvH5ePlaylist.rewriteLiveMaster("$master  $tag\n", "https://media.test/master.m3u8") }.isFailure)
        }
    }

    @Test fun livePreservesRollingSequenceAndUsesLiveScheme() {
        val playlist = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:123\n#EXTINF:10,\n123.ts\n"
        val rewritten = CctvH5ePlaylist.rewriteMedia(playlist, "https://media.test/live/index.m3u8", live = true)
        assertTrue(rewritten.contains("#EXT-X-MEDIA-SEQUENCE:123"))
        assertFalse(rewritten.contains("#EXT-X-ENDLIST"))
        assertTrue(rewritten.contains("cctvcdrm+https://media.test/live/123.ts"))
        assertEquals("https://media.test/live/123.ts", CctvH5ePlaylist.unwrap("cctvcdrm+https://media.test/live/123.ts"))
        assertTrue(runCatching { CctvH5ePlaylist.rewriteMedia(playlist, "https://media.test/live/index.m3u8") }.isFailure)
    }

    @Test fun preservesCompleteTimelineAndWrapsRelativeAndAbsoluteSegments() {
        val rewritten = CctvH5ePlaylist.rewriteMedia("""#EXTM3U
            #EXT-X-TARGETDURATION:10
            #EXT-X-MEDIA-SEQUENCE:0
            #EXTINF:10.0,
            first.ts?key=one
            #EXTINF:3.2,
            https://other.test/last.ts
            #EXT-X-ENDLIST
        """.trimIndent(), "https://media.test/show/index.m3u8")
        assertTrue(rewritten.contains("cctvh5e+https://media.test/show/first.ts?key=one"))
        assertTrue(rewritten.contains("cctvh5e+https://other.test/last.ts"))
        assertTrue(rewritten.contains("#EXTINF:3.2,"))
        assertTrue(rewritten.endsWith("#EXT-X-ENDLIST\n"))
        assertEquals("https://media.test/first.ts", CctvH5ePlaylist.unwrap("cctvh5e+https://media.test/first.ts"))
    }

    @Test fun rejectsPartialLiveEncryptedAndByteRangePlaylists() {
        val full = "#EXTM3U\n#EXTINF:10,\nfirst.ts\n#EXT-X-ENDLIST"
        val invalid = listOf(full.replace("#EXT-X-ENDLIST", ""),
            full.replace("#EXTINF", "#EXT-X-KEY:METHOD=AES-128,URI=\"key\"\n#EXTINF"),
            full.replace("#EXTINF", "#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF"),
            full.replace("#EXTINF", "#EXT-X-BYTERANGE:100@0\n#EXTINF"))
        invalid.forEach { text -> assertTrue(runCatching { CctvH5ePlaylist.rewriteMedia(text, "https://media.test/index.m3u8") }.isFailure) }
    }

    @Test fun refusesUnsupportedHighestCodecInsteadOfFallingBackToLowerQuality() {
        val master = """#EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1920x1080,CODECS="hvc1.1.6.L93.B0,mp4a.40.2"
            high.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720,CODECS="avc1.64001e,mp4a.40.2"
            low.m3u8
        """.trimIndent()
        assertTrue(runCatching { CctvH5ePlaylist.highestHd(master, "https://media.test/index.m3u8") }.isFailure)
        assertTrue(runCatching { CctvH5ePlaylist.highestHd(master.replace("1920x1080", "480x270")
            .replace("1280x720", "640x360"), "https://media.test/index.m3u8") }.isFailure)
    }
}
