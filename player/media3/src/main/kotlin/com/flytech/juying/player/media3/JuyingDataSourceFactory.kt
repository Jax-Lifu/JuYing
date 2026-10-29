package com.flytech.juying.player.media3

import android.content.Context
import android.net.Uri
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.datasource.okhttp.OkHttpDataSource
import dagger.hilt.android.qualifiers.ApplicationContext
import okhttp3.OkHttpClient
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 按 URI scheme 路由：smb:// 等自定义协议走各 source 模块通过 Hilt @IntoMap 注册的工厂，
 * 其余（http/https/udp/file/content...）走 DefaultDataSource + OkHttp。
 */
@UnstableApi
@Singleton
class JuyingDataSourceFactory @Inject constructor(
    @ApplicationContext private val context: Context,
    private val client: OkHttpClient,
    private val custom: @JvmSuppressWildcards Map<String, DataSource.Factory>,
) {

    /** 每个播放项独立快照，避免旧清单/分片/字幕延迟创建 DataSource 时读到新线路的凭据。 */
    fun forHeaders(headers: Map<String, String>): DataSource.Factory {
        val headersSnapshot = headers.toMap()
        val http = OkHttpDataSource.Factory(client).setDefaultRequestProperties(headersSnapshot)
        val default = DefaultDataSource.Factory(context, http)
        return DataSource.Factory {
            SchemeRoutingDataSource(
                default = default.createDataSource(),
                custom = custom,
                defaultHeaders = headersSnapshot,
            )
        }
    }
}

/** 按 URI Scheme 协议分流的多源 Media3 DataSource 包装实现。 */
@UnstableApi
internal class SchemeRoutingDataSource(
    private val default: DataSource,
    private val custom: Map<String, DataSource.Factory>,
    private val defaultHeaders: Map<String, String>,
) : DataSource {

    private val listeners = mutableListOf<TransferListener>()
    private var active: DataSource? = null

    override fun addTransferListener(transferListener: TransferListener) {
        listeners += transferListener
        default.addTransferListener(transferListener)
    }

    override fun open(dataSpec: DataSpec): Long {
        val effectiveSpec = if (defaultHeaders.isNotEmpty() && dataSpec.httpRequestHeaders.isEmpty()) {
            dataSpec.withRequestHeaders(defaultHeaders)
        } else {
            dataSpec
        }
        val factory = effectiveSpec.uri.scheme?.lowercase()?.let(custom::get)
        val ds = if (factory != null) {
            factory.createDataSource().also { d -> listeners.forEach(d::addTransferListener) }
        } else default
        active = ds
        return ds.open(effectiveSpec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int = checkNotNull(active).read(buffer, offset, length)

    override fun getUri(): Uri? = active?.uri

    override fun getResponseHeaders(): Map<String, List<String>> = active?.responseHeaders ?: emptyMap()

    override fun close() {
        try {
            active?.close()
        } finally {
            active = null
        }
    }
}
