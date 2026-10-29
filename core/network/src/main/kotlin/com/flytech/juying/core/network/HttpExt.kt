package com.flytech.juying.core.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import timber.log.Timber
import java.io.IOException
import java.nio.charset.Charset
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

private const val DEFAULT_MAX_TEXT_BYTES = 15L * 1024 * 1024 // 15MB 上限，防止误拉取视频流撑爆低配机内存

/**
 * 将 OkHttp 的异步 [Call] 转换为支持协程取消的挂起扩展。
 *
 * **Why**: 协程作用域取消或超时（如超时取消网络嗅探）时，自动触发 [Call.cancel]，
 * 立即关闭底层 TCP 连接并释放缓冲区，避免后台任务继续空转。
 */
suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            if (!cont.isCancelled) cont.resumeWithException(e)
        }

        override fun onResponse(call: Call, response: Response) {
            cont.resume(response)
        }
    })
    cont.invokeOnCancellation { runCatching { cancel() } }
}

/**
 * 非阻塞地拉取文本；非 2xx 或超过 [maxBytes] 上限抛 [IOException]。
 *
 * Why: 低端 TV 盒子（1-2GB 内存）若将错误指向 TS/MP4 流或超大文件的 URL 当作 M3U/JSON 配置调用 `body.string()`，
 * 会瞬间触发 OOM。通过 `source().request(maxBytes + 1)` 严格限制单次文本拉取上限。
 */
suspend fun OkHttpClient.fetchText(
    url: String,
    headers: Map<String, String> = emptyMap(),
    maxBytes: Long = DEFAULT_MAX_TEXT_BYTES,
): String = withContext(Dispatchers.IO) {
    // OkHttp 回调只保证响应头异步到达，正文读取仍需避开主线程。
    val request = Request.Builder().url(url).apply { headers.forEach { (k, v) -> header(k, v) } }.build()
    newCall(request).await().use { resp ->
        if (!resp.isSuccessful) {
            Timber.w("fetchText HTTP %d", resp.code)
            throw IOException("HTTP ${resp.code}")
        }
        val body = resp.body ?: return@withContext ""
        val contentLength = body.contentLength()
        if (contentLength > maxBytes) {
            throw IOException("Response too large ($contentLength bytes > $maxBytes limit)")
        }
        val source = body.source()
        if (source.request(maxBytes + 1)) {
            throw IOException("Response body exceeds $maxBytes bytes limit")
        }
        val charset: Charset = body.contentType()?.charset(Charsets.UTF_8) ?: Charsets.UTF_8
        source.buffer.readString(charset)
    }
}
