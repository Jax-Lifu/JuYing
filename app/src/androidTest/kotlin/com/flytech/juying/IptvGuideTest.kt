package com.flytech.juying

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.source.iptv.IptvSource
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.zip.GZIPOutputStream
import javax.inject.Provider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class IptvGuideTest {
    @Test fun playlistHeadersGzipGuideAndChannelFilteringWorkOnAndroid() = runBlocking {
        MockWebServer().use { server ->
            val source = IptvSource(Provider { OkHttpClient() }, Dispatchers.Default,
                Provider { InstrumentationRegistry.getInstrumentation().targetContext })
            val config = SourceConfig("guide", "IPTV", SourceType.IPTV, server.url("/playlist").toString(),
                extra = mapOf("userAgent" to "JuYing-test", "referer" to "https://example.test/"))
            server.enqueue(MockResponse().setBody("""#EXTM3U x-tvg-url="/guide.gz"
                |#EXTINF:-1 tvg-id="channel-1",Test channel
                |https://example.test/video.m3u8
            """.trimMargin()))
            val now = Instant.now()
            val format = DateTimeFormatter.ofPattern("yyyyMMddHHmmss Z").withZone(ZoneOffset.UTC)
            fun programme(channel: String, title: String) = """<programme channel="$channel" start="${format.format(now.minusSeconds(120))}" stop="${format.format(now.plusSeconds(1200))}"><title>$title</title></programme>"""
            val xml = "<tv>${programme("channel-1", "当前节目 &amp; 特辑")}${programme("other", "Wrong channel")}</tv>"
            val compressed = ByteArrayOutputStream().apply { GZIPOutputStream(this).use { it.write(xml.toByteArray()) } }.toByteArray()
            server.enqueue(MockResponse().setBody(Buffer().write(compressed)))
            val channel = source.channels(config).single().channels.single()
            assertEquals("JuYing-test", channel.lines.single().headers["User-Agent"])
            assertEquals("当前节目 & 特辑", source.epg(config, channel.id).single().title)
            assertEquals(1, source.epg(config, channel.id).size)
            assertEquals(2, server.requestCount)
            repeat(2) {
                val request = server.takeRequest()
                assertEquals("JuYing-test", request.getHeader("User-Agent"))
                assertEquals("https://example.test/", request.getHeader("Referer"))
            }
            val changed = config.copy(extra = config.extra + ("epgUrl" to server.url("/hostile.xml").toString()))
            server.enqueue(MockResponse().setBody("#EXTM3U\n#EXTINF:-1 tvg-id=\"channel-1\",Test channel\nhttps://example.test/video.m3u8"))
            server.enqueue(MockResponse().setBody("""<!DOCTYPE tv [<!ENTITY leak SYSTEM "${server.url("/secret")}">]><tv>${programme("channel-1", "&leak;")}</tv>"""))
            assertTrue(runCatching { source.epg(changed, channel.id) }.isFailure)
            assertEquals(4, server.requestCount)
        }
    }
}
