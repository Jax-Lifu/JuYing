package com.flytech.juying.source.tvbox.spider

import com.flytech.juying.source.tvbox.TvboxJson
import com.flytech.juying.source.tvbox.TvboxJson.text
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

/** JS/Python 共用的 HTTP 桥接；限定协议、时限和响应体，避免低内存盒子被单个站点耗尽。 */
class ScriptHttp(client: OkHttpClient) {
    private val client = client.newBuilder()
        .callTimeout(SpiderLimits.HTTP_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .build()

    internal fun bytes(url: String, limit: Long = SpiderLimits.SCRIPT_MAX_BYTES): ByteArray =
        client.newCall(Request.Builder().url(TvboxJson.httpUrl(url)).build()).execute().use { response ->
            if (!response.isSuccessful) throw IOException("站点 HTTP 请求失败 (${response.code})")
            val body = response.body ?: throw IOException("站点响应为空")
            require(body.contentLength() <= limit) { "站点响应过大" }
            val source = body.source()
            source.request(limit + 1)
            require(source.buffer.size <= limit) { "站点响应过大" }
            source.readByteArray()
        }

    internal fun text(url: String): String = bytes(url).toString(Charsets.UTF_8)

    // 由 QuickJS 与 Chaquopy 反射调用，签名由 consumer-rules 保留。
    fun request(url: String, optionsJson: String): String {
        val options = TvboxJson.response(optionsJson)
        val method = options.text("method")?.uppercase() ?: "GET"
        require(method in HTTP_METHODS) { "不支持的 HTTP 方法" }
        val headers = TvboxJson.headers(options["headers"])
        val body = if (method == "GET" || method == "HEAD") null else {
            val contentType = headers.entries.firstOrNull { it.key.equals("Content-Type", true) }?.value
            (options.text("data") ?: options.text("body").orEmpty()).toRequestBody(contentType?.toMediaTypeOrNull())
        }
        val builder = Request.Builder().url(TvboxJson.httpUrl(url)).method(method, body)
        headers.forEach { (name, value) -> builder.header(name, value) }
        val follow = options.text("redirect") != "0"
        val transport = if (follow) client else client.newBuilder().followRedirects(false).build()
        return transport.newCall(builder.build()).execute().use { response ->
            val responseBody = response.body ?: throw IOException("站点响应为空")
            require(responseBody.contentLength() <= SpiderLimits.SCRIPT_MAX_BYTES) { "站点响应过大" }
            val source = responseBody.source()
            source.request(SpiderLimits.SCRIPT_MAX_BYTES + 1)
            require(source.buffer.size <= SpiderLimits.SCRIPT_MAX_BYTES) { "站点响应过大" }
            buildJsonObject {
                put("code", response.code)
                put("content", source.readString(responseBody.contentType()?.charset(Charsets.UTF_8) ?: Charsets.UTF_8))
                put("headers", Json.encodeToJsonElement(
                    kotlinx.serialization.serializer<Map<String, String>>(),
                    response.headers.names().associateWith { response.header(it).orEmpty() },
                ))
            }.toString()
        }
    }

    private companion object {
        val HTTP_METHODS = setOf("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
    }
}
