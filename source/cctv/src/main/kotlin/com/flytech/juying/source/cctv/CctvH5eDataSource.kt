package com.flytech.juying.source.cctv

import android.net.Uri
import androidx.annotation.Keep
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoMap
import dagger.multibindings.StringKey
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Provider

/**
 * 将官方 H5E/CDRM TS 还原后交给同一个 Media3 播放器，保留 SurfaceView 硬解与原始时间轴。
 * 每个 DataSource 只持有一个分片；8 MiB 上限约束 JNI 临时副本，关闭时取消网络并释放缓存。
 * H5E 必须按完整 TS 分片解码，Range/重试在解码后的字节上定位，不能把部分密文送入解码器。
 */
@UnstableApi
internal class CctvH5eDataSource(
    private val client: OkHttpClient,
    private val decode: (ByteArray, Boolean) -> Int = { segment, live ->
        if (live) CctvH5eDecoder.decodeLive(segment) else CctvH5eDecoder.decode(segment)
    },
) : BaseDataSource(true) {
    @Volatile private var call: Call? = null
    @Volatile private var cancelled = false
    private var data = ByteArray(0)
    private var position = 0
    private var end = 0
    private var uri: Uri? = null
    private var responseHeaders: Map<String, List<String>> = emptyMap()
    private var opened = false

    override fun open(dataSpec: DataSpec): Long {
        cancelled = false
        transferInitializing(dataSpec)
        try {
            val live = dataSpec.uri.scheme == CctvH5ePlaylist.LIVE_SCHEME_HTTP ||
                dataSpec.uri.scheme == CctvH5ePlaylist.LIVE_SCHEME_HTTPS
            val url = CctvH5ePlaylist.unwrap(dataSpec.uri.toString())
            val request = Request.Builder().url(url).apply {
                dataSpec.httpRequestHeaders.forEach { (name, value) -> header(name, value) }
                // The upstream must return a complete segment even for a resumed extractor read.
                removeHeader("Range")
            }.build()
            val pending = client.newCall(request).also {
                it.timeout().timeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                synchronized(this) {
                    if (cancelled) throw IOException("央视高清请求已取消")
                    call = it
                }
            }
            val bytes = pending.execute().use { response ->
                if (!response.isSuccessful) throw IOException("央视高清请求失败：HTTP ${response.code}")
                val finalUrl = response.request.url
                uri = Uri.parse(CctvH5ePlaylist.wrap(finalUrl.toString(), live))
                responseHeaders = response.headers.toMultimap()
                val body = response.body ?: throw IOException("央视高清响应为空")
                val playlist = finalUrl.encodedPath.endsWith(".m3u8", ignoreCase = true)
                val limit = if (playlist) CctvH5ePlaylist.MAX_PLAYLIST_BYTES else MAX_SEGMENT_BYTES
                if (body.contentLength() > limit || body.source().request(limit + 1))
                    throw IOException("央视高清分片超过设备内存上限")
                if (cancelled) throw IOException("央视高清请求已取消")
                if (playlist) {
                    val text = body.string()
                    if (live && text.lineSequence().any { it.trim().startsWith("#EXT-X-STREAM-INF:") })
                        CctvH5ePlaylist.rewriteLiveMaster(text, finalUrl.toString()).toByteArray()
                    else CctvH5ePlaylist.rewriteMedia(text, finalUrl.toString(), live).toByteArray()
                }
                else body.bytes().also { segment ->
                    if (decode(segment, live) != 0) throw IOException("央视高清分片解码失败，请重试或选择其他节目")
                }
            }
            synchronized(this) {
                if (cancelled) throw IOException("央视高清请求已取消")
                if (dataSpec.position > bytes.size) throw IOException("央视高清分片位置越界")
                data = bytes
                position = dataSpec.position.toInt()
                end = if (dataSpec.length == C.LENGTH_UNSET.toLong()) bytes.size
                    else position + minOf(dataSpec.length, (bytes.size - position).toLong()).toInt()
                opened = true
                transferStarted(dataSpec)
                return (end - position).toLong()
            }
        } catch (error: Exception) {
            synchronized(this) {
                data = ByteArray(0)
                position = 0
                end = 0
                uri = null
                responseHeaders = emptyMap()
            }
            throw if (error is IOException) error else IOException(error.message, error)
        } finally {
            call = null
        }
    }

    @Synchronized override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (cancelled) throw IOException("央视高清请求已取消")
        if (position == end) return C.RESULT_END_OF_INPUT
        val count = minOf(length, end - position)
        data.copyInto(buffer, offset, position, position + count)
        position += count
        bytesTransferred(count)
        return count
    }

    override fun getUri(): Uri? = uri
    override fun getResponseHeaders(): Map<String, List<String>> = responseHeaders

    @Synchronized override fun close() {
        cancelled = true
        call?.cancel()
        call = null
        data = ByteArray(0)
        position = 0
        end = 0
        uri = null
        responseHeaders = emptyMap()
        if (opened) {
            opened = false
            transferEnded()
        }
    }

    private companion object {
        const val MAX_SEGMENT_BYTES = 8 * 1024 * 1024L
        const val REQUEST_TIMEOUT_SECONDS = 20L
    }
}

/** 按需加载 JNI；浏览列表和打开详情不会占用 native 解码资源。 */
@Keep
internal object CctvH5eDecoder {
    init { System.loadLibrary("juying_cctv_h5e") }
    external fun decode(segment: ByteArray): Int
    external fun decodeLive(segment: ByteArray): Int
}

@UnstableApi
class CctvH5eDataSourceFactory @Inject constructor(private val client: Provider<OkHttpClient>) : DataSource.Factory {
    override fun createDataSource(): DataSource = CctvH5eDataSource(client.get())
}

@Module
@InstallIn(SingletonComponent::class)
abstract class CctvH5eDataSourceModule {
    @UnstableApi
    @Binds @IntoMap @StringKey(CctvH5ePlaylist.SCHEME_HTTP)
    abstract fun http(factory: CctvH5eDataSourceFactory): DataSource.Factory

    @UnstableApi
    @Binds @IntoMap @StringKey(CctvH5ePlaylist.SCHEME_HTTPS)
    abstract fun https(factory: CctvH5eDataSourceFactory): DataSource.Factory

    @UnstableApi
    @Binds @IntoMap @StringKey(CctvH5ePlaylist.LIVE_SCHEME_HTTP)
    abstract fun liveHttp(factory: CctvH5eDataSourceFactory): DataSource.Factory

    @UnstableApi
    @Binds @IntoMap @StringKey(CctvH5ePlaylist.LIVE_SCHEME_HTTPS)
    abstract fun liveHttps(factory: CctvH5eDataSourceFactory): DataSource.Factory
}
