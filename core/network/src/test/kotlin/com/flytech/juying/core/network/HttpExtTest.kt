package com.flytech.juying.core.network

import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import okio.ForwardingSource
import okio.buffer
import org.junit.Assert.*
import org.junit.Test

class HttpExtTest {
    @Test fun normalReadAndReaderFailureCloseTheResponse() = runBlocking {
        val closed = CountDownLatch(2)
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(tracked("hello".toResponseBody("text/plain".toMediaType()), closed)).build()
        }.build()
        try {
            assertEquals("hello", client.fetchText("http://example.test/"))
            val error = runCatching {
                client.newCall(Request.Builder().url("http://example.test/").build()).await { error("Invalid document") }
            }.exceptionOrNull()
            assertTrue(error is IllegalStateException)
            assertEquals("Invalid document", error?.message)
            assertEquals(0L, closed.count)
        } finally { client.dispatcher.executorService.shutdownNow() }
    }

    @Test fun cancellationAfterHeadersClosesTheSocketAndResponse() = runBlocking {
        val server = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
        val accepted = AtomicReference<Socket>()
        val peerClosed = CountDownLatch(1)
        val reading = CountDownLatch(1)
        val closed = CountDownLatch(1)
        val serving = thread(isDaemon = true) {
            runCatching {
                server.accept().also(accepted::set).use { socket ->
                    socket.soTimeout = 5_000
                    val input = socket.getInputStream().bufferedReader()
                    while (!input.readLine().isNullOrEmpty()) Unit
                    socket.getOutputStream().apply {
                        write("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nh".toByteArray())
                        flush()
                    }
                    try {
                        if (input.read() == -1) peerClosed.countDown()
                    } catch (_: java.net.SocketException) { peerClosed.countDown() }
                }
            }
        }
        val client = OkHttpClient.Builder().readTimeout(5, TimeUnit.SECONDS).addNetworkInterceptor { chain ->
            val response = chain.proceed(chain.request())
            response.newBuilder().body(tracked(checkNotNull(response.body), closed, reading)).build()
        }.build()
        try {
            val pending = async(Dispatchers.IO) { client.fetchText("http://127.0.0.1:${server.localPort}/") }
            assertTrue("Body reading never started", reading.await(2, TimeUnit.SECONDS))
            withTimeout(1_000) { pending.cancelAndJoin() }
            assertTrue("Response was not closed", closed.await(2, TimeUnit.SECONDS))
            assertTrue("Server socket remained open", peerClosed.await(2, TimeUnit.SECONDS))
        } finally {
            accepted.get()?.close()
            server.close()
            serving.join(2_000)
            client.connectionPool.evictAll()
            client.dispatcher.executorService.shutdownNow()
        }
    }

    @Test fun responseArrivingAfterCancellationIsClosedWithoutReading() = runBlocking {
        val client = OkHttpClient()
        val request = Request.Builder().url("http://example.test/").build()
        var callback: Callback? = null
        val call = object : Call by client.newCall(request) {
            override fun enqueue(responseCallback: Callback) { callback = responseCallback }
        }
        val pending = async(start = CoroutineStart.UNDISPATCHED) { call.await { error("Cancelled response was read") } }
        pending.cancelAndJoin()
        val closed = CountDownLatch(1)
        val response = Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
            .body(tracked("late".toResponseBody(), closed)).build()
        checkNotNull(callback).onResponse(call, response)
        assertTrue(call.isCanceled())
        assertEquals(0L, closed.count)
    }

    private fun tracked(body: ResponseBody, closed: CountDownLatch, reading: CountDownLatch? = null): ResponseBody =
        object : ResponseBody() {
            private val input = object : ForwardingSource(body.source()) {
                override fun read(sink: Buffer, byteCount: Long): Long {
                    reading?.countDown()
                    return super.read(sink, byteCount)
                }
                override fun close() { try { super.close() } finally { closed.countDown() } }
            }.buffer()
            override fun contentType() = body.contentType()
            override fun contentLength() = body.contentLength()
            override fun source() = input
        }
}
