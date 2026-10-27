package com.flytech.juying.source.cctv

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.DataSpec
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [32], manifest = Config.NONE)
class CctvH5eDataSourceTest {
    private fun client(body: (Request) -> ByteArray) = OkHttpClient.Builder().addInterceptor { chain ->
        val request = chain.request()
        Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
            .body(body(request).toResponseBody("application/octet-stream".toMediaType())).build()
    }.build()

    @Test fun rangeRetryDecodesWholeSegmentThenReadsRequestedPositionAndHeaders() {
        var calls = 0
        val source = CctvH5eDataSource(client { request ->
            assertEquals("https", request.url.scheme)
            assertEquals("https://tv.cctv.com/", request.header("Referer"))
            assertNull(request.header("Range"))
            byteArrayOf(0, 1, 2, 3, 4, 5)
        }) { bytes, live ->
            calls++
            assertFalse(live)
            assertEquals(6, bytes.size)
            bytes[3] = 33
            0
        }
        val spec = DataSpec.Builder().setUri("cctvh5e+https://media.test/segment.ts")
            .setPosition(2).setLength(3).setHttpRequestHeaders(mapOf("Range" to "bytes=2-4", "Referer" to "https://tv.cctv.com/"))
            .build()
        assertEquals(3L, source.open(spec))
        val result = ByteArray(8)
        assertEquals(3, source.read(result, 1, 7))
        assertArrayEquals(byteArrayOf(2, 33, 4), result.sliceArray(1..3))
        assertEquals(C.RESULT_END_OF_INPUT, source.read(result, 0, 8))
        source.close()
        assertNull(source.uri)
        assertEquals(3L, source.open(spec))
        assertEquals(2, calls)
        source.close()
    }

    @Test fun playlistPreservesTimelineWithoutCallingNativeDecoder() {
        val playlist = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment.ts\n#EXT-X-ENDLIST\n"
        val source = CctvH5eDataSource(client { playlist.toByteArray() }) { _, _ -> error("清单不能进入 TS 解码器") }
        val length = source.open(DataSpec(Uri.parse("cctvh5e+https://media.test/show/index.m3u8"))).toInt()
        val bytes = ByteArray(length)
        assertEquals(length, source.read(bytes, 0, length))
        assertTrue(bytes.toString(Charsets.UTF_8).contains("cctvh5e+https://media.test/show/segment.ts"))
        assertTrue(bytes.toString(Charsets.UTF_8).contains("#EXT-X-ENDLIST"))
        source.close()
    }

    @Test fun liveMasterKeepsEveryQualityInTheCdrmDataSource() {
        val master = """#EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720
            hd/index.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=600000,RESOLUTION=640x360
            https://other.test/sd/index.m3u8
        """.trimIndent()
        val source = CctvH5eDataSource(client { master.toByteArray() }) { _, _ -> error("清单不能进入 TS 解码器") }
        try {
            val bytes = ByteArray(source.open(DataSpec(Uri.parse("cctvcdrm+https://media.test/live/master.m3u8"))).toInt())
            assertEquals(bytes.size, source.read(bytes, 0, bytes.size))
            val rewritten = bytes.toString(Charsets.UTF_8)
            assertEquals(2, rewritten.lineSequence().count { it.startsWith("#EXT-X-STREAM-INF:") })
            assertTrue(rewritten.contains("cctvcdrm+https://media.test/live/hd/index.m3u8"))
            assertTrue(rewritten.contains("cctvcdrm+https://other.test/sd/index.m3u8"))
        } finally { source.close() }
    }

    @Test fun liveRefreshKeepsLiveModeAndDispatchesOnlySegmentsToLiveDecoder() {
        var sequence = 123
        var decoded = false
        val source = CctvH5eDataSource(client { request ->
            if (request.url.encodedPath.endsWith(".m3u8")) {
                "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:$sequence\n#EXTINF:10,\n$sequence.ts\n".toByteArray()
            } else byteArrayOf(1, 2, 3)
        }) { _, live -> assertTrue(live); decoded = true; 0 }
        val playlist = DataSpec(Uri.parse("cctvcdrm+https://media.test/live/index.m3u8"))
        repeat(2) {
            val bytes = ByteArray(source.open(playlist).toInt())
            assertEquals(bytes.size, source.read(bytes, 0, bytes.size))
            assertTrue(bytes.toString(Charsets.UTF_8).contains("#EXT-X-MEDIA-SEQUENCE:$sequence"))
            assertTrue(bytes.toString(Charsets.UTF_8).contains("cctvcdrm+https://media.test/live/$sequence.ts"))
            assertEquals(playlist.uri, source.uri)
            assertFalse(decoded)
            source.close()
            sequence++
        }
        assertEquals(3L, source.open(DataSpec(Uri.parse("cctvcdrm+https://media.test/live/124.ts"))))
        assertTrue(decoded)
        source.close()
    }

    @Test fun closeDuringDownloadCancelsAndDoesNotPublishStaleDecodedBytes() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        var decoded = false
        val source = CctvH5eDataSource(client {
            entered.countDown()
            check(release.await(5, TimeUnit.SECONDS))
            byteArrayOf(1, 2, 3)
        }) { _, _ -> decoded = true; 0 }
        val worker = Executors.newSingleThreadExecutor()
        try {
            val result = worker.submit<Throwable?> {
                runCatching { source.open(DataSpec(Uri.parse("cctvh5e+https://media.test/segment.ts"))) }.exceptionOrNull()
            }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            source.close()
            release.countDown()
            assertTrue(result.get(5, TimeUnit.SECONDS) is IOException)
            assertFalse(decoded)
        } finally {
            release.countDown()
            worker.shutdownNow()
            source.close()
        }
    }

    @Test fun oversizedSegmentIsRejectedBeforeReadingOrNativeAllocation() {
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(object : okhttp3.ResponseBody() {
                    override fun contentType() = "video/mp2t".toMediaType()
                    override fun contentLength() = 8 * 1024 * 1024L + 1
                    override fun source(): okio.BufferedSource = okio.Buffer()
                }).build()
        }.build()
        var decoded = false
        val source = CctvH5eDataSource(client) { _, _ -> decoded = true; 0 }
        try {
            val failure = runCatching { source.open(DataSpec(Uri.parse("cctvh5e+https://media.test/large.ts"))) }.exceptionOrNull()
            assertTrue(failure is IOException)
            assertTrue(failure?.message.orEmpty().contains("超过设备内存上限"))
            assertFalse(decoded)
            assertNull(source.uri)
        } finally { source.close() }
    }
}
