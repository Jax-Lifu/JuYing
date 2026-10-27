package com.flytech.juying.source.smb

import android.net.Uri
import com.flytech.juying.core.model.SourceConfig
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder

/**
 * SourceConfig.url 约定为 smb://host[:port]/share[/subdir]，省略端口时使用 445。
 *
 * 安全设计（Why）：
 * 播放 URI 仅编码为 `smb://user@host[:port]/share/path/to/file`，严禁在 URI 中明文拼接 password，
 * 避免密码随播放历史落盘或出现在 ExoPlayer 异常日志中；密码与 domain 由 [SmbConnections] 在内存中按 `(host, port, share, user)` 维护。
 */
internal data class SmbTarget(
    val host: String,
    val share: String,
    val basePath: String,
    val user: String,
    val password: String = "",
    val domain: String = "",
    val port: Int = DEFAULT_PORT,
) {
    init { require(port in 1..65535) { "SMB 端口必须在 1–65535 范围内" } }

    fun fullPath(relative: String): String =
        listOf(basePath, relative).filter { it.isNotBlank() }.joinToString("/").trim('/')

    fun toPlayUri(relative: String): String {
        val encodedUser = URLEncoder.encode(user, Charsets.UTF_8.name()).replace("+", "%20")
        val userPart = if (user.isNotEmpty()) "$encodedUser@" else ""
        val portPart = if (port == DEFAULT_PORT) "" else ":$port"
        // 按路径构造并编码，保留目录分隔符，避免文件名的 #、?、% 被解释为 URI 结构。
        val encodedPath = URI(null, null, "/$share/${fullPath(relative)}", null).toASCIIString()
        return "smb://$userPart$host$portPart$encodedPath"
    }

    companion object {
        private const val DEFAULT_PORT = 445

        fun fromConfig(config: SourceConfig): SmbTarget {
            val u = URI(config.url)
            val segs = u.path.trim('/').split('/').filter { it.isNotEmpty() }
            require(u.host != null && segs.isNotEmpty()) { "SMB 地址格式应为 smb://host/share[/dir]" }
            return SmbTarget(
                host = u.host,
                share = segs.first(),
                basePath = segs.drop(1).joinToString("/"),
                user = config.username.orEmpty().ifEmpty { "guest" },
                password = config.password.orEmpty(),
                domain = config.extra["domain"].orEmpty(),
                port = u.port.takeIf { it != -1 } ?: DEFAULT_PORT,
            )
        }

        /** 播放时由 DataSource 解析；path 已含 basePath。 */
        fun fromPlayUri(uri: Uri): SmbTarget {
            val address = URI(uri.toString())
            require(address.host != null) { "SMB 播放地址格式无效" }
            val rawUserInfo = uri.userInfo ?: "guest"
            val user = URLDecoder.decode(rawUserInfo.substringBefore(':'), Charsets.UTF_8.name())
            val inlinePass = if (':' in rawUserInfo) {
                URLDecoder.decode(rawUserInfo.substringAfter(':'), Charsets.UTF_8.name())
            } else {
                ""
            }
            val segs = uri.path.orEmpty().trim('/').split('/')
            return SmbTarget(
                host = address.host,
                share = segs.first(),
                basePath = segs.drop(1).joinToString("/"),
                user = user.ifEmpty { "guest" },
                password = inlinePass,
                port = address.port.takeIf { it != -1 } ?: DEFAULT_PORT,
            )
        }
    }
}
