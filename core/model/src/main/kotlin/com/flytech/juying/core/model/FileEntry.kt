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

    val isImage: Boolean
        get() = !isDirectory && (mimeType?.startsWith("image/") == true || extension in IMAGE_EXTENSIONS)

    companion object {
        val VIDEO_EXTENSIONS = setOf("mp4", "mkv", "avi", "mov", "flv", "ts", "m2ts", "webm", "rmvb", "wmv", "m4v", "mpg", "mpeg")
        val SUBTITLE_EXTENSIONS = setOf("srt", "ass", "ssa", "vtt", "sub")
        val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp")
    }
}

/**
 * 跨数据源通用的同目录视频封面 / 缩略图自动匹配器。
 *
 * 匹配优先级：
 * 1. 同名或同前缀专属图片（如 `movie.jpg`、`movie-thumb.jpg`）。
 * 2. 回传视频本身的 [uri]，由视频截帧器异步抽取首帧作为缩略图。
 *
 * 注意：不要把目录级 folder/poster/fanart 赋给每一个子集视频，否则同一个目录下几十集视频全部显示同一张巨幅背景图，极其难看重复。
 */
object SidecarCovers {
    private val markers = listOf("-thumb", ".thumb", "-poster")

    /** 每个目录只索引一次图片；仍以目录中第一个匹配项为准。 */
    fun forDirectory(siblings: List<FileEntry>): Map<String, String?> {
        val images = mutableMapOf<String, FileEntry>()
        siblings.forEach { file ->
            if (file.isImage) {
                val base = file.name.substringBeforeLast('.', "").lowercase()
                images.putIfAbsent(base, file)
                markers.forEach { marker ->
                    var offset = base.indexOf(marker)
                    while (offset >= 0) {
                        images.putIfAbsent(base.substring(0, offset), file)
                        offset = base.indexOf(marker, offset + marker.length)
                    }
                }
            }
        }
        return siblings.asSequence().filter { it.isVideo }.associate { video ->
            val base = video.name.substringBeforeLast('.', video.name).lowercase()
            video.path to (images[base]?.uri ?: video.uri)
        }
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
