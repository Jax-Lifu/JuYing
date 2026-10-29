package com.flytech.juying.core.data

import dagger.Lazy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import timber.log.Timber
import java.net.URLEncoder
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 拼音首字母/简拼与视频搜索联想词服务。
 * 通过主流公开视频搜索 Suggest 接口，将 "wwd"、"xcm" 等简拼转为标准影视剧名（如 "汪汪队立大功"、"熊出没"）。
 */
@Singleton
class SearchSuggestService @Inject constructor(
    private val client: Lazy<OkHttpClient>,
) {
    suspend fun suggest(query: String): List<String> = withContext(Dispatchers.IO) {
        val q = query.trim()
        if (q.isEmpty()) return@withContext emptyList()
        val url = "https://suggest.video.iqiyi.com/?key=${URLEncoder.encode(q, "UTF-8")}"
        try {
            val req = Request.Builder()
                .url(url)
                .header("User-Agent", "Mozilla/5.0")
                .build()
            val text = client.get().newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext emptyList()
                resp.body?.string().orEmpty()
            }
            val json = JSONObject(text)
            val data = json.optJSONArray("data") ?: return@withContext emptyList()
            val list = mutableListOf<String>()
            for (i in 0 until minOf(data.length(), 10)) {
                val obj = data.optJSONObject(i) ?: continue
                val name = obj.optString("name", "").trim()
                if (name.isNotEmpty() && name !in list) {
                    list.add(name)
                }
            }
            list
        } catch (e: Exception) {
            Timber.w(e, "Suggest failed for %s", q)
            emptyList()
        }
    }
}
