package com.flytech.juying.source.tvbox

import com.flytech.juying.source.tvbox.config.TvboxParse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class TvboxJsonPlaybackTest {
    @Test fun matchingFlagsWinAndFailedParserFallsThroughToNextJsonParser() = runTest {
        val hosts = CopyOnWriteArrayList<String>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            hosts += request.url.host
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body((if (request.url.host == "match.test") "<html>failure</html>"
                    else """{"url":"https://media.test/play.m3u8"}""").toResponseBody("application/json".toMediaType())).build()
        }.build()
        val parsers = listOf(TvboxParse("web", 0, "https://web.test/?url="),
            TvboxParse("default", 1, "https://default.test/?url="),
            TvboxParse("matching", 1, "https://match.test/?url=", Json.parseToJsonElement("""{"flag":["main"]}""")))
        val play = TvboxJsonPlayback.resolve(client, parsers, "https://config.test/", "main", "https://video.test/watch", emptyMap())
        assertEquals(listOf("match.test", "default.test"), hosts)
        assertEquals("https://media.test/play.m3u8", play?.url)
    }

    @Test fun cancellationDoesNotTryAnotherParserOrReturnAWebFallback() = runTest {
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val hosts = CopyOnWriteArrayList<String>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            hosts += chain.request().url.host
            started.countDown()
            check(release.await(5, TimeUnit.SECONDS))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("{}".toResponseBody("application/json".toMediaType())).build()
        }.build()
        val job = launch(Dispatchers.Default) {
            TvboxJsonPlayback.resolve(client, listOf(TvboxParse("first", 1, "https://first.test/?url="),
                TvboxParse("second", 1, "https://second.test/?url=")), "https://config.test/", "main", "https://video.test/", emptyMap())
            fail("取消不能返回普通解析失败")
        }
        try {
            assertTrue(started.await(5, TimeUnit.SECONDS))
            job.cancelAndJoin()
            assertEquals(listOf("first.test"), hosts)
        } finally { release.countDown() }
    }
}
