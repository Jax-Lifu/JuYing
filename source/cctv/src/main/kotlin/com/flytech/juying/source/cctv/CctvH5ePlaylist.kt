package com.flytech.juying.source.cctv

import okhttp3.HttpUrl.Companion.toHttpUrl

/** 官方 H5E 点播/CDRM 直播只接收 H.264 TS；未知格式不能悄悄切到标清。 */
internal object CctvH5ePlaylist {
    const val SCHEME_HTTP = "cctvh5e+http"
    const val SCHEME_HTTPS = "cctvh5e+https"
    const val LIVE_SCHEME_HTTP = "cctvcdrm+http"
    const val LIVE_SCHEME_HTTPS = "cctvcdrm+https"
    const val MAX_PLAYLIST_BYTES = 1024 * 1024L
    private const val MIN_HD_HEIGHT = 720
    private val attributes = Regex("([A-Z0-9-]+)=(\"[^\"]*\"|[^,]*)")

    fun highestHd(text: String, baseUrl: String): String {
        val highest = highestHdVariant(variants(text))
        return requireNotNull(baseUrl.toHttpUrl().resolve(highest.uri)) { "央视高清地址异常" }.toString()
    }

    /** 保留可播放的低档供手动选择，但缺少高清或最高档不兼容时仍拒绝静默降级。 */
    fun rewriteLiveMaster(text: String, baseUrl: String): String {
        val variants = variants(text)
        highestHdVariant(variants)
        require(text.lineSequence().none { it.trim().startsWith('#') && "URI=" in it }) { "央视高清清单格式暂不支持" }
        val base = baseUrl.toHttpUrl()
        return variants.filter { supportsCodecs(it.codecs) }.joinToString("\n", prefix = "#EXTM3U\n", postfix = "\n") {
            val url = requireNotNull(base.resolve(it.uri)) { "央视高清地址异常" }.toString()
            "${it.streamInfo}\n${wrap(url, live = true)}"
        }
    }

    private fun variants(text: String): List<Variant> {
        val lines = text.trim().lines().map(String::trim)
        require(lines.firstOrNull() == "#EXTM3U") { "央视高清清单格式异常" }
        return lines.mapIndexedNotNull { index, line ->
            if (!line.startsWith("#EXT-X-STREAM-INF:")) return@mapIndexedNotNull null
            val fields = attributes.findAll(line).associate { it.groupValues[1] to it.groupValues[2].trim('"') }
            val resolution = fields["RESOLUTION"]?.split('x') ?: return@mapIndexedNotNull null
            val width = resolution.getOrNull(0)?.toIntOrNull() ?: 0
            val height = resolution.getOrNull(1)?.toIntOrNull() ?: 0
            val bandwidth = fields["BANDWIDTH"]?.toLongOrNull() ?: 0
            val uri = lines.getOrNull(index + 1)?.takeIf { it.isNotEmpty() && !it.startsWith('#') }
                ?: return@mapIndexedNotNull null
            if (width <= 0 || height <= 0 || bandwidth <= 0) return@mapIndexedNotNull null
            Variant(uri, height, bandwidth, fields["CODECS"].orEmpty(), line)
        }
    }

    private fun highestHdVariant(variants: List<Variant>): Variant {
        val highest = variants.filter { it.height >= MIN_HD_HEIGHT }
            .maxWithOrNull(compareBy<Variant> { it.height }.thenBy { it.bandwidth })
            ?: error("该节目未提供原生高清线路")
        require(supportsCodecs(highest.codecs)) {
            "该节目最高画质编码暂不支持原生播放，请尝试其他节目"
        }
        return highest
    }

    private fun supportsCodecs(value: String): Boolean {
        val codecs = value.lowercase().split(',').map(String::trim).filter(String::isNotEmpty)
        return codecs.isEmpty() || (codecs.any { it.startsWith("avc1") || it.startsWith("avc3") } &&
            codecs.all { codec -> listOf("avc1", "avc3", "mp4a", "ac-3", "ec-3", "opus", "flac").any(codec::startsWith) })
    }

    fun rewriteMedia(text: String, baseUrl: String, live: Boolean = false): String {
        val lines = text.trim().lines().map(String::trim)
        require(lines.firstOrNull() == "#EXTM3U" && (live || "#EXT-X-ENDLIST" in lines)) { "央视高清未返回有效媒体清单" }
        require(lines.none { it.startsWith("#EXT-X-KEY:") || it.startsWith("#EXT-X-MAP:") ||
            it.startsWith("#EXT-X-BYTERANGE:") || it.startsWith("#EXT-X-STREAM-INF:") ||
            (it.startsWith('#') && "URI=" in it) }) { "央视高清清单格式暂不支持" }
        require(lines.any { it.isNotBlank() && !it.startsWith('#') }) { "央视高清清单没有分片" }
        val base = baseUrl.toHttpUrl()
        return lines.joinToString("\n", postfix = "\n") { line ->
            if (line.isBlank() || line.startsWith('#')) line
            else wrap(requireNotNull(base.resolve(line)) { "央视高清分片地址异常" }.toString(), live)
        }
    }

    fun wrap(url: String, live: Boolean = false): String = "${if (live) "cctvcdrm" else "cctvh5e"}+${url.toHttpUrl()}"
    fun unwrap(url: String): String {
        require(listOf(SCHEME_HTTP, SCHEME_HTTPS, LIVE_SCHEME_HTTP, LIVE_SCHEME_HTTPS).any { url.startsWith("$it:") }) { "无效的央视高清协议" }
        return url.substringAfter('+').toHttpUrl().toString()
    }

    private data class Variant(val uri: String, val height: Int, val bandwidth: Long, val codecs: String, val streamInfo: String)
}
