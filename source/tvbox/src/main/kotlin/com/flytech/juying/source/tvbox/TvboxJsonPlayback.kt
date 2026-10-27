package com.flytech.juying.source.tvbox

import com.flytech.juying.core.model.PlayLine
import com.flytech.juying.core.network.fetchText
import com.flytech.juying.source.tvbox.TvboxJson.text
import com.flytech.juying.source.tvbox.config.TvboxParse
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okhttp3.OkHttpClient
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/** 只执行订阅声明的 JSON 解析接口；请求头隔离，避免把站点凭据发给解析服务。 */
internal object TvboxJsonPlayback {
    private const val JSON_PARSE_TYPE = 1
    private const val MAX_ATTEMPTS = 4
    private const val ATTEMPT_TIMEOUT_MS = 4_000L
    private const val MAX_RESPONSE_BYTES = 1024 * 1024L

    suspend fun resolve(client: OkHttpClient, parsers: List<TvboxParse>, baseUrl: String,
        flag: String, url: String, headers: Map<String, String>): PlayLine? {
        val candidates = parsers.filter { it.type == JSON_PARSE_TYPE && it.url.isNotBlank() }
            .sortedBy { parser ->
                val flags = ((parser.ext as? JsonObject)?.get("flag") as? JsonArray)
                    ?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }.orEmpty()
                when { flag in flags -> 0; flags.isEmpty() -> 1; else -> 2 }
            }.take(MAX_ATTEMPTS)
        if (candidates.isEmpty()) return null
        val parserClient = client.newBuilder().callTimeout(ATTEMPT_TIMEOUT_MS, TimeUnit.MILLISECONDS).build()
        for (parser in candidates) {
            val resolved = try {
                withContext(Dispatchers.IO) {
                    withTimeoutOrNull(ATTEMPT_TIMEOUT_MS) {
                        val parserHeaders = TvboxJson.headers((parser.ext as? JsonObject)?.get("header"))
                        val endpoint = TvboxJson.httpUrl(parser.url, baseUrl) + URLEncoder.encode(url, "UTF-8")
                        val root = TvboxJson.response(parserClient.fetchText(endpoint, parserHeaders, MAX_RESPONSE_BYTES))
                        val data = root["data"] as? JsonObject
                        val target = data?.text("url") ?: root.text("url") ?: root.text("playurl")
                            ?: root.text("vurl") ?: root.text("result") ?: root.text("data")
                            ?: return@withTimeoutOrNull null
                        val responseHeaders = TvboxJson.headers(root["header"] ?: root["headers"]) +
                            TvboxJson.headers(data?.get("header") ?: data?.get("headers"))
                        PlayLine(TvboxJson.httpUrl(target), parser.name, headers + parserHeaders + responseHeaders)
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                null
            }
            if (resolved != null) return resolved
        }
        return null
    }
}
