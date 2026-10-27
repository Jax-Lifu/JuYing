package com.flytech.juying.source.tvbox

import com.flytech.juying.source.tvbox.config.TvboxSite
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class TvboxProtocolTest {
    @Test fun retainsPaginationFromJsonAndXmlInsteadOfGuessingFromItems() {
        assertEquals(true, TvboxJson.hasMore("""{"pagecount":"5","list":[]}""", 2))
        assertEquals(false, TvboxJson.hasMore("""{"pagecount":5}""", 5))
        assertEquals(true, TvboxJson.hasMore("""{"total":21,"limit":20}""", 1))
        assertEquals(false, TvboxJson.hasMore("""{"total":20,"limit":20}""", 1))
        assertEquals(null, TvboxJson.hasMore("""{"pagecount":0,"limit":0}""", 1))
        val xml = TvboxXml.response("""<rss><list page="2" pagecount="5" pagesize="20" recordcount="100"/></rss>""")
        assertEquals(true, TvboxJson.hasMore(xml, 2))
    }
    @Test
    fun referencesRoundTripAndKeepSitesDistinct() {
        val item = TvboxItemRef("site:中文", "movie/1\"?#")
        assertEquals(item, TvboxItemRef.decode(item.encode()))
        assertNotEquals(item.encode(), item.copy(siteKey = "other").encode())
        val episode = TvboxEpisodeRef(item, "线路一", "第1集", 0)
        assertEquals(episode, TvboxEpisodeRef.decode(episode.encode()))
    }

    @Test
    fun parsesAllLinesAndKeepsDollarInUrl() {
        val text = """{"list":[{"vod_id":7,"vod_name":"剧集","vod_play_from":"HLS${'$'}${'$'}${'$'}MP4","vod_play_url":"一${'$'}https://example.com/1.m3u8?t=a${'$'}b#二${'$'}https://example.com/2.m3u8${'$'}${'$'}${'$'}一${'$'}https://example.com/1.mp4"}]}"""
        val video = TvboxJson.videos(text).single()
        assertEquals("7", video.id)
        assertEquals(2, video.groups.size)
        assertEquals(2, video.groups.first().episodes.size)
        assertEquals("https://example.com/1.m3u8?t=a${'$'}b", video.groups.first().episodes.first().playId)
        assertEquals("MP4", video.detail("source", "site").playGroups.last().name)
    }

    @Test
    fun malformedRowsDoNotBecomeFakeItems() {
        assertEquals(emptyList<TvboxVideo>(), TvboxJson.videos("""{"list":[null,{}, {"vod_id":1}]}"""))
        assertThrows(IllegalArgumentException::class.java) { TvboxJson.videos("""{"list":{}}""") }
        assertThrows(IllegalArgumentException::class.java) { TvboxJson.response("<html>blocked</html>") }
    }

    @Test
    fun validatesHeadersAndRelativeAddresses() {
        val headers = TvboxJson.headers(TvboxJson.response("""{"Referer":"https://example.com/"}"""))
        assertEquals("https://example.com/", headers["Referer"])
        assertThrows(IllegalArgumentException::class.java) {
            TvboxJson.headers(TvboxJson.response("""{"X-Test":"ok\r\nCookie: secret"}"""))
        }
        assertEquals("https://example.com/api", TvboxJson.httpUrl("../api", "https://example.com/repo/config.json"))
        assertThrows(IllegalArgumentException::class.java) { TvboxJson.httpUrl("file:///etc/passwd") }
    }

    @Test
    fun detectsEachScriptLanguageWithoutMatchingQueryStrings() {
        assertEquals(SpiderLanguage.JAR, TvboxSite(api = "csp_Demo").spiderLanguage())
        assertEquals(SpiderLanguage.JAVASCRIPT, TvboxSite(api = "./demo.js?v=1").spiderLanguage())
        assertEquals(SpiderLanguage.PYTHON, TvboxSite(api = "https://example.com/demo.py").spiderLanguage())
        assertThrows(UnsupportedOperationException::class.java) {
            TvboxSite(api = "https://example.com/api?ext=.js").spiderLanguage()
        }
    }
}
