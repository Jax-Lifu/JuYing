package com.flytech.juying.source.tvbox

import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.core.model.PlaybackRoute
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import javax.inject.Provider

class TvboxSourceTest {
    private val requests = CopyOnWriteArrayList<Request>()
    private val config = SourceConfig("subscription", "我的订阅", SourceType.TVBOX, "https://config.test/repos.json")

    private fun source(response: (Request) -> String): TvboxSource {
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            requests += request
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(response(request).toResponseBody("application/json".toMediaType())).build()
        }.build()
        return TvboxSource(Provider { client }, Dispatchers.Default, Provider { error("CMS 不应启动 Spider") })
    }

    @Test fun cmsClosesCategoryDetailEpisodePlaybackAndKeepsSiteIdentity() = runTest {
        val source = source { request ->
            when (request.url.encodedPath) {
                "/repos.json" -> """{"urls":[{"url":"./repo/config.json","name":"仓库"}]}"""
                "/repo/config.json" -> """{"sites":[
                    {"key":"a","name":"甲","type":1,"api":"./a","header":{"Referer":"https://a.test/"}},
                    {"key":"b","name":"乙","type":1,"api":"./b"}]}"""
                else -> if (request.url.queryParameter("ac") == null) categories else video
            }
        }
        assertEquals(listOf("a", "b"), source.subSources(config).map { it.id })
        val category = source.categories(config, "a").single()
        val items = source.list(config, category.id, 2)
        val fromA = items.single()
        val fromB = source.search(config, "中文 & 空格", 3, "b").single()
        assertNotEquals(fromA.id, fromB.id)
        val detail = source.detail(config, fromA.id)
        assertEquals(2, detail.playGroups.size)
        val play = source.resolve(config, detail.playGroups[1].episodes[0].ref)
        assertEquals("https://media.test/backup.m3u8", play.url)
        assertEquals("https://a.test/", play.headers["Referer"])
        assertTrue(requests.any { it.url.queryParameter("t") == "电影" && it.url.queryParameter("pg") == "2" })
        assertTrue(requests.any { it.url.queryParameter("wd") == "中文 & 空格" && it.url.queryParameter("pg") == "3" })
        assertEquals(1, requests.count { it.url.encodedPath == "/repo/config.json" })
        val pinned = config.copy(extra = mapOf("siteKey" to "b"))
        assertEquals(listOf("b"), source.subSources(pinned).map { it.id })
        assertTrue(com.flytech.juying.core.model.SourceCapability.LIVE !in source.capabilities(pinned))
        assertTrue(com.flytech.juying.core.model.SourceCapability.VOD in source.capabilities(pinned))
    }

    @Test fun directCmsEndpointAndEmptySecondPageAreSupported() = runTest {
        val source = source { request ->
            when {
                request.url.queryParameter("pg") == "2" -> """{"list":[]}"""
                request.url.queryParameter("ac") != null -> video
                else -> categories
            }
        }
        val category = source.categories(config).single()
        assertEquals(1, source.list(config, category.id, 1).size)
        assertTrue(source.list(config, category.id, 2).isEmpty())
    }

    @Test fun reorderedEpisodeIsResolvedByNameAndDoesNotPlayAdjacentEpisode() = runTest {
        var reordered = false
        val source = source { request ->
            if (request.url.queryParameter("ac") == null) categories
            else if (reordered) video.replace("正片\$https://media.test/main.m3u8", "新增\$https://media.test/new.m3u8#正片\$https://media.test/main.m3u8")
            else video
        }
        val category = source.categories(config).single()
        val item = source.list(config, category.id, 1).single()
        val ref = source.detail(config, item.id).playGroups[0].episodes[0].ref
        reordered = true
        assertEquals("https://media.test/main.m3u8", source.resolve(config, ref).url)
    }

    @Test fun malformedResponseIsAnErrorInsteadOfAnEmptySuccess() = runTest {
        val source = source { "<html>upstream unavailable</html>" }
        assertTrue(runCatching { source.categories(config) }.isFailure)
    }

    @Test fun jsonParserResolvesWebEpisodeToNativeStreamAndPreservesHeaders() = runTest {
        val source = source { request ->
            when {
                request.url.encodedPath == "/repos.json" -> """{"sites":[{"key":"remote","type":4,"api":"https://cms.test/api",
                    "header":{"Authorization":"site-only"}}],"parses":[{"name":"JSON","type":1,
                    "url":"https://parse.test/?url=","ext":{"header":{"User-Agent":"ParserClient"}}}]}"""
                request.url.host == "parse.test" -> """{"data":{"url":"https://media.test/hd.m3u8",
                    "header":{"Referer":"https://video.test/"}}}"""
                request.url.queryParameter("play") != null -> """{"parse":1,"url":"https://video.test/watch?id=1&part=2"}"""
                else -> video
            }
        }
        val ref = TvboxEpisodeRef(TvboxItemRef("remote", "same-id"), "主线", "正片", 0).encode()
        val play = source.resolve(config, ref)
        assertEquals(PlaybackRoute.NATIVE, play.route)
        assertEquals("https://media.test/hd.m3u8", play.url)
        assertEquals("https://video.test/", play.headers["Referer"])
        assertEquals("ParserClient", play.headers["User-Agent"])
        val parserRequest = requests.single { it.url.host == "parse.test" }
        assertEquals("https://video.test/watch?id=1&part=2", parserRequest.url.queryParameter("url"))
        assertEquals(null, parserRequest.header("Authorization"))
    }

    private companion object {
        const val categories = """{"class":[{"type_id":"电影","type_name":"电影"}]}"""
        val video = """{"list":[{"vod_id":"same-id","vod_name":"测试影片","vod_play_from":"主线${'$'}${'$'}${'$'}备用",
            "vod_play_url":"正片${'$'}https://media.test/main.m3u8${'$'}${'$'}${'$'}正片${'$'}https://media.test/backup.m3u8"}]}"""
    }

    @Test fun xmlCmsUsesVideolistAndDirectPlaybackWithoutPlayerRequest() = runTest {
        val source = source { request ->
            if (request.url.encodedPath == "/repos.json")
                """{"sites":[{"key":"xml","type":0,"api":"https://cms.test/api"}]}"""
            else """<rss><class><ty id="1">电影</ty></class><list><video><id>movie</id><name>测试影片</name>
                <dl><dd flag="线路"><![CDATA[正片${'$'}https://media.test/first.m3u8]]></dd></dl></video></list></rss>"""
        }
        val category = source.categories(config).single()
        val item = source.list(config, category.id, 1).single()
        val detail = source.detail(config, item.id)
        assertEquals("https://media.test/first.m3u8", source.resolve(config, detail.playGroups.single().episodes.single().ref).url)
        assertTrue(requests.filter { it.url.queryParameter("ac") != null }.all { it.url.queryParameter("ac") == "videolist" })
        assertTrue(requests.none { it.url.queryParameter("play") != null })
        assertTrue(runCatching { TvboxXml.response("""<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///private">]><rss>&x;</rss>""") }.isFailure)
    }
}
