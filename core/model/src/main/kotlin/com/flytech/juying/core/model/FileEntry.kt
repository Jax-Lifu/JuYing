package com.flytech.juying.core.model

/**
 * 目录树浏览条目（适用于 SMB、WebDAV、NFS、网盘、Alist、本地存储、移动存储、UPnP）。
 *
 * @property path 相对于数据源根的路径或对象标识符（如 UPnP containerId/itemId）。
 * @property uri 可选的直链或系统 URI（如 UPnP 媒体 HTTP 地址、SAF `content://` 地址）。
 */
data class FileEntry(
    val name: String,
    val path: String,
    val isDirectory: Boolean,
    val size: Long = 0,
    val modifiedMs: Long = 0,
    val mimeType: String? = null,
    val uri: String? = null,
) {
    val extension: String
        get() = name.substringAfterLast('.', "").lowercase()

    val isVideo: Boolean
        get() = !isDirectory && (mimeType?.startsWith("video/") == true || extension in VIDEO_EXTENSIONS)

    val isSubtitle: Boolean
        get() = !isDirectory && extension in SUBTITLE_EXTENSIONS

    companion object {
        val VIDEO_EXTENSIONS = setOf("mp4", "mkv", "avi", "mov", "flv", "ts", "m2ts", "webm", "rmvb", "wmv", "m4v", "mpg", "mpeg")
        val SUBTITLE_EXTENSIONS = setOf("srt", "ass", "ssa", "vtt", "sub")
    }
}

/**
 * 跨数据源通用的同目录外挂字幕自动匹配器。
 *
 * **What**: 给定视频文件 [video] 与同目录文件列表 [siblings]，匹配同名或带语言后缀的字幕文件（如 `movie.srt`、`movie.zh.ass`）。
 *
 * **Why**: 让 SMB、WebDAV、NFS、网盘、本地存储、USB 移动存储等所有 `BrowseSource` 共享同一套外挂字幕发现规则，
 * 避免在每个存储协议模块中重复编写文件名匹配逻辑。
 */
object SidecarSubtitles {

    fun matchFor(
        video: FileEntry,
        siblings: List<FileEntry>,
        urlResolver: (FileEntry) -> String,
    ): List<Subtitle> {
        val baseName = video.name.substringBeforeLast('.', video.name).lowercase()
        if (baseName.isEmpty()) return emptyList()
        return siblings.asSequence()
            .filter { it.isSubtitle }
            .filter { sub ->
                val subBase = sub.name.substringBeforeLast('.', "").lowercase()
                subBase == baseName || subBase.startsWith("$baseName.")
            }
            .map { sub ->
                val lang = sub.name.substringBeforeLast('.', "")
                    .substringAfter(video.name.substringBeforeLast('.', video.name), "")
                    .trimStart('.', '-', '_')
                    .takeIf { it.isNotEmpty() }
                Subtitle(url = urlResolver(sub), lang = lang, mimeType = mimeTypeFor(sub.extension))
            }
            .toList()
    }

    private fun mimeTypeFor(ext: String): String? = when (ext) {
        "srt" -> "application/x-subrip"
        "ass", "ssa" -> "text/x-ssa"
        "vtt" -> "text/vtt"
        else -> null
    }
}
