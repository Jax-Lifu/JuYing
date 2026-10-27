package com.flytech.juying.player.media3

import android.net.Uri
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class JuyingDataSourceFactoryTest {
    private val requests = mutableListOf<Request>()
    private val client = OkHttpClient.Builder().addInterceptor { chain ->
        requests += chain.request()
        Response.Builder()
            .request(chain.request())
            .protocol(Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .body("media".toResponseBody("application/octet-stream".toMediaType()))
            .build()
    }.build()
    private val factory = JuyingDataSourceFactory(RuntimeEnvironment.getApplication(), client, emptyMap())

    @Test
    fun `delayed sources retain their playback headers after switching lines`() {
        val first = factory.forHeaders(mapOf("Authorization" to "Bearer first", "Referer" to "https://first.test"))
        val existing = first.createDataSource()
        val second = factory.forHeaders(mapOf("Authorization" to "Bearer second", "Referer" to "https://second.test"))

        second.createDataSource().openAndClose("https://media.test/second.ts")
        first.createDataSource().openAndClose("https://media.test/first.m3u8")
        first.createDataSource().openAndClose("https://media.test/first.vtt")
        existing.openAndClose("https://media.test/first.ts")
        factory.forHeaders(emptyMap()).createDataSource().openAndClose("https://media.test/public.ts")

        assertEquals(listOf("Bearer second", "Bearer first", "Bearer first", "Bearer first", null),
            requests.map { it.header("Authorization") })
        assertEquals(listOf("https://second.test", "https://first.test", "https://first.test", "https://first.test", null),
            requests.map { it.header("Referer") })
    }

    @Test
    fun `binding copies headers before caller reuses its mutable map`() {
        val headers = mutableMapOf("Cookie" to "session=first")
        val first = factory.forHeaders(headers)
        headers["Cookie"] = "session=second"

        first.createDataSource().openAndClose("https://media.test/first.ts")

        assertEquals("session=first", requests.single().header("Cookie"))
    }

    @Test
    fun `explicit HTTP request headers still override playback defaults`() {
        val source = factory.forHeaders(mapOf("Authorization" to "Bearer playback", "Referer" to "https://first.test"))
            .createDataSource()
        source.openAndClose("https://media.test/first.ts", mapOf("Authorization" to "Bearer explicit"))

        assertEquals("Bearer explicit", requests.single().header("Authorization"))
        assertEquals("https://first.test", requests.single().header("Referer"))
    }

    private fun DataSource.openAndClose(url: String, headers: Map<String, String> = emptyMap()) {
        try {
            open(DataSpec.Builder().setUri(Uri.parse(url)).setHttpRequestHeaders(headers).build())
        } finally {
            close()
        }
    }
}
