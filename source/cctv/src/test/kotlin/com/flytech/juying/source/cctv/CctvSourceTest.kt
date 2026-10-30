package com.flytech.juying.source.cctv

import com.flytech.juying.core.model.Channel
import com.flytech.juying.core.model.PlaybackRoute
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import javax.inject.Provider

class CctvSourceTest {
    private val requests = CopyOnWriteArrayList<Request>()
    private val config = SourceConfig(BUILTIN_CCTV_ID, "央视", SourceType.CCTV, "")

    private fun source(body: (Request) -> String): CctvSource {
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            requests += request
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(body(request).toResponseBody("application/json".toMediaType())).build()
        }.build()
        return CctvSource(Provider { client }, Dispatchers.Default)
    }

    @Test fun searchKeepsNextDirectoryPageWhenCurrentPageHasNoMatches() = runTest {
        val source = source { request ->
            val firstPage = request.url.queryParameter("p") == "1"
            val rows = if (firstPage) (1..24).joinToString(",") { """{"id":"$it","title":"Other $it"}""" }
                else """{"id":"match","title":"Target"}"""
            """{"data":{"list":[$rows]}}"""
        }
        val first = source.searchPage(config, "Target", 1, null)
        assertTrue(first.items.isEmpty())
        assertEquals(true, first.hasMore)
        val second = source.searchPage(config, "Target", 2, null)
        assertEquals(listOf("match"), second.items.map { it.id })
        assertEquals(false, second.hasMore)
    }

    @Test fun liveKeepsOfficialMasterAndPrefersHighestQualityWithoutOpeningWebPage() = runTest {
        val source = source { request ->
            when (request.url.host) {
                "vdnx.live.cntv.cn" -> """{"ack":"yes","play":"1",
                    "manifest":{"hls_cdrm":"https://media.test/live/master.m3u8"}}"""
                "media.test" -> """#EXTM3U
                    #EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360
                    sd.m3u8
                    #EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720
                    best.m3u8
                    #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720
                    low.m3u8
                """.trimIndent()
                else -> error("Live playback must use the official VDN and media endpoints")
            }
        }

        val play = source.resolve(config, Channel("cctv1", "CCTV-1 综合"))

        assertEquals(PlaybackRoute.NATIVE, play.route)
        assertTrue(play.isLive)
        assertEquals("cctv1", play.id)
        assertEquals("CCTV-1 综合", play.title)
        assertEquals(CctvH5ePlaylist.wrap("https://media.test/live/master.m3u8", live = true), play.url)
        assertTrue(play.preferHighestVideoQuality)
        assertEquals(2, requests.size)
        val request = requests.first()
        assertEquals("/api/v3/vdn/live", request.url.encodedPath)
        assertEquals("cctv1", request.url.queryParameter("channel"))
        assertEquals("1", request.url.queryParameter("vn"))
        assertEquals("1", request.url.queryParameter("pdrm"))
        assertEquals("", request.url.queryParameter("uid"))
        val auth = requireNotNull(request.header("auth-key")).split('-')
        assertEquals(request.url.queryParameter("hbss"), auth[0])
        assertTrue(auth[1].toInt() in 100..1000)
        assertTrue(Regex("[0-9a-f]{32}").matches(auth[2]))
        assertEquals("https://tv.cctv.com/live/cctv1/index.shtml", request.header("Referer"))
        assertNull(requests.last().header("auth-key"))
        assertNull(play.headers["auth-key"])
        assertTrue(requests.none { it.url.host == "tv.cctv.com" })
    }

    @Test fun liveRejectsOfficialDenialBeforeRequestingMedia() = runTest {
        for ((ack, play) in listOf("no" to "1", "yes" to "0", "yes" to "")) {
            requests.clear()
            val source = source { """{"ack":"$ack","play":"$play",
                "manifest":{"hls_cdrm":"https://media.test/live/master.m3u8"}}""" }

            val message = runCatching { source.resolve(config, Channel("cctv1", "CCTV-1")) }
                .exceptionOrNull()?.message.orEmpty()

            assertTrue(message.contains("暂不可播放"))
            assertEquals(1, requests.size)
            assertEquals("vdnx.live.cntv.cn", requests.single().url.host)
        }
    }

    @Test fun liveWithoutCdrmFailsWithoutSelectingAnotherRoute() = runTest {
        val source = source { """{"ack":"yes","play":"1",
            "manifest":{"hls_nd":"https://media.test/standard.m3u8"}}""" }

        val message = runCatching { source.resolve(config, Channel("cctv1", "CCTV-1")) }
            .exceptionOrNull()?.message.orEmpty()

        assertTrue(message.contains("未提供原生高清"))
        assertEquals(1, requests.size)
    }

    @Test fun liveWithoutHdVariantFailsWithoutDowngrading() = runTest {
        val source = source { request ->
            if (request.url.host == "vdnx.live.cntv.cn") """{"ack":"yes","play":"1",
                "manifest":{"hls_cdrm":"https://media.test/live/master.m3u8"}}"""
            else """#EXTM3U
                #EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360
                sd.m3u8
            """.trimIndent()
        }

        val message = runCatching { source.resolve(config, Channel("cctv1", "CCTV-1")) }
            .exceptionOrNull()?.message.orEmpty()

        assertTrue(message.contains("未提供原生高清"))
        assertEquals(2, requests.size)
        assertTrue(requests.none { it.url.encodedPath.endsWith("sd.m3u8") })
    }

    @Test fun liveChannelAliasesUseOfficialIdsAndKeepChannelIdentity() = runTest {
        val source = source { request ->
            if (request.url.host == "vdnx.live.cntv.cn") """{"ack":"yes","play":"1",
                "manifest":{"hls_cdrm":"https://media.test/live/master.m3u8"}}"""
            else """#EXTM3U
                #EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720
                hd.m3u8
            """.trimIndent()
        }
        for ((id, officialId) in listOf("cctv9" to "cctvjilu", "cctv14" to "cctvchild", "cctv5plus" to "cctv5plus")) {
            requests.clear()
            val play = source.resolve(config, Channel(id, id))

            assertEquals(id, play.id)
            assertEquals(PlaybackRoute.NATIVE, play.route)
            assertEquals(officialId, requests.first().url.queryParameter("channel"))
            assertEquals("https://tv.cctv.com/live/$officialId/index.shtml", play.headers["Referer"])
        }
    }

    @Test fun longAlbumLoadsEveryPageAndKeepsGuidSeparateFromAlbumId() = runTest {
        val source = source { request ->
            if (request.url.host == "vdn.apps.cntv.cn") """{"hls_url":"https://media.test/standard.m3u8"}"""
            else episodePage(if (request.url.queryParameter("p") == "1") 1..100 else 101..152, 152)
        }
        val detail = source.detail(config, "VIDA-album")
        assertEquals(152, detail.playGroups.first().episodes.size)
        assertEquals(2, requests.size)
        assertEquals(listOf("央视高清（原生播放）", "官方标清（原生播放）"), detail.playGroups.map { it.name })
        val hdEpisode = detail.playGroups.first().episodes.first()
        val hdRef = CctvJson.format.decodeFromString<CctvEpisodeRef>(hdEpisode.ref)
        assertEquals(listOf(CctvJson.format.encodeToString(hdRef.copy(playback = CctvPlayback.OFFICIAL))), hdEpisode.legacyRefs)
        val standard = source.resolve(config, detail.playGroups.last().episodes.last().ref)
        assertEquals(PlaybackRoute.NATIVE, standard.route)
        assertEquals("guid152", requests.last().url.queryParameter("pid"))
        assertEquals("https://media.test/standard.m3u8", standard.url)
    }

    @Test fun nativeHdUsesNestedManifestAndHighestHdWithoutOpeningWebPage() = runTest {
        val source = source { request ->
            when (request.url.host) {
                "vdn.apps.cntv.cn" -> """{"hls_url":"https://media.test/standard.m3u8",
                    "manifest":{"hls_h5e_url":"https://media.test/hd/master.m3u8"}}"""
                "media.test" -> """#EXTM3U
                    #EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=480x270,CODECS="avc1.64001e,mp4a.40.2"
                    sd.m3u8
                    #EXT-X-STREAM-INF:BANDWIDTH=2048000,RESOLUTION=1280x720,CODECS="avc1.64001e,mp4a.40.2"
                    best.m3u8
                    #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720,CODECS="avc1.64001e,mp4a.40.2"
                    low.m3u8
                """.trimIndent()
                else -> episodePage(1..1, 1)
            }
        }
        val ref = source.detail(config, "VIDA-album").playGroups.first().episodes.single().ref
        val play = source.resolve(config, ref)
        assertEquals(PlaybackRoute.NATIVE, play.route)
        assertEquals("cctvh5e+https://media.test/hd/best.m3u8", play.url)
        assertTrue(requests.none { it.url.host == "tv.cctv.com" })
        assertTrue(requests.none { it.url.encodedPath.endsWith("standard.m3u8") })
    }

    @Test fun missingNativeHdFailsWithoutSilentlySelectingStandard() = runTest {
        val source = source { request ->
            if (request.url.host == "vdn.apps.cntv.cn") """{"hls_url":"https://media.test/standard.m3u8"}"""
            else episodePage(1..1, 1)
        }
        val ref = source.detail(config, "VIDA-album").playGroups.first().episodes.single().ref
        val message = runCatching { source.resolve(config, ref) }.exceptionOrNull()?.message.orEmpty()
        assertTrue(message.contains("未提供原生高清"))
        assertFalse(message.contains("网页"))
        assertTrue(requests.none { it.url.host == "media.test" })
    }

    @Test fun legacyOfficialReferenceUsesNativeHdWithoutOpeningWebPage() = runTest {
        val source = source { request ->
            when (request.url.host) {
                "vdn.apps.cntv.cn" -> """{"manifest":{"hls_h5e_url":"https://media.test/hd/master.m3u8"}}"""
                "media.test" -> """#EXTM3U
                    #EXT-X-STREAM-INF:BANDWIDTH=2048000,RESOLUTION=1280x720
                    best.m3u8
                """.trimIndent()
                else -> error("Legacy episode must resolve directly to native HD")
            }
        }
        val ref = CctvJson.format.encodeToString(CctvEpisodeRef(
            "guid1", "https://tv.cctv.com/episode1.shtml", "第1集", CctvPlayback.OFFICIAL))

        val play = source.resolve(config, ref)

        assertEquals(PlaybackRoute.NATIVE, play.route)
        assertEquals("cctvh5e+https://media.test/hd/best.m3u8", play.url)
        assertEquals("guid1", requests.first().url.queryParameter("pid"))
        assertTrue(requests.none { it.url.host == "tv.cctv.com" })
    }

    @Test fun repeatedPageWithMissingEpisodesFailsInsteadOfPublishingIncompleteAlbum() = runTest {
        val source = source { episodePage(1..100, 152) }
        assertTrue(runCatching { source.detail(config, "VIDA-album") }.isFailure)
        assertEquals(2, requests.size)
    }

    @Test fun numberedEpisodesWinOverLongExtrasAndDuplicateParts() {
        val episodes = listOf(
            CctvEpisode("extra", "花絮", "https://tv.cctv.com/extra.shtml", null, null, 900),
            CctvEpisode("second", "第2集", "https://tv.cctv.com/2.shtml", null, 2, 900),
            CctvEpisode("first", "第1集", "https://tv.cctv.com/1.shtml", null, 1, 900),
            CctvEpisode("duplicate", "第1集", "https://tv.cctv.com/1a.shtml", null, 1, 900),
        )
        assertEquals(listOf("first", "second"), CctvJson.mainEpisodes(episodes).map { it.guid })
    }

    @Test fun albumListKeepsAlbumIdentityAndSearchUsesActors() = runTest {
        val source = source { """{"data":{"total":1,"list":[{"id":"album","vsetid":"set",
            "title":"《测试剧》","image2":"//p1.img.cctvpic.com/cover.jpg","actors":"演员甲","year":"2026"}]}}""" }
        val item = source.list(config, CctvCategory.DRAMA.name, 2).single()
        assertEquals("album", item.id)
        assertEquals("测试剧", item.title)
        assertEquals("https://p1.img.cctvpic.com/cover.jpg", item.cover)
        assertEquals("2", requests.first().url.queryParameter("p"))
        assertEquals("电视剧", requests.first().url.queryParameter("fc"))
        assertEquals(1, source.search(config, "演员甲", 1).size)
        assertTrue(source.search(config, "不存在", 1).isEmpty())
    }

    @Test fun albumTitleKeepsBracketsWhenTheyDoNotSurroundTheWholeTitle() = runTest {
        val source = source { """{"data":{"list":[{"id":"film","title":"电影《崂山道士》"}]}}""" }
        assertEquals("电影《崂山道士》", source.list(config, CctvCategory.MOVIE.name, 1).single().title)
    }

    private fun episodePage(range: IntRange, total: Int): String = buildJsonObject {
        put("data", buildJsonObject {
            put("total", total)
            put("list", buildJsonArray { range.forEach { part -> add(buildJsonObject {
                put("guid", "guid$part"); put("part", part); put("title", "《测试剧》 第${part}集")
                put("url", "https://tv.cctv.com/episode$part.shtml"); put("length", "00:10:32")
            }) } })
        })
    }.toString()
}
