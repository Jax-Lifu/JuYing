package com.flytech.juying.source.smb

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import coil.ImageLoader
import coil.decode.DataSource
import coil.decode.ImageSource
import coil.fetch.FetchResult
import coil.fetch.Fetcher
import coil.fetch.SourceResult
import coil.request.Options
import com.flytech.juying.core.model.FileEntry
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2ShareAccess
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okio.Path.Companion.toOkioPath
import timber.log.Timber
import java.io.File
import java.security.MessageDigest
import java.util.EnumSet
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 让 Coil 支持通过 smb:// 协议加载 NAS 上的伴随图片（jpg/png/webp）以及自动抽取视频关键帧缩略图。
 * 抽取的缩略图会压缩缓存到本地磁盘，避免反复向 NAS 发起 I/O。
 */
class SmbThumbnailFetcher(
    private val context: Context,
    private val connections: SmbConnections,
    private val uri: Uri,
    private val options: Options,
) : Fetcher {

    override suspend fun fetch(): FetchResult? = withContext(Dispatchers.IO) {
        val path = uri.path.orEmpty().lowercase()
        val ext = path.substringAfterLast('.', "")
        val isVideo = ext in FileEntry.VIDEO_EXTENSIONS
        val isImage = ext in FileEntry.IMAGE_EXTENSIONS

        if (!isVideo && !isImage) return@withContext null

        val cacheKey = "smb_" + md5(uri.toString() + if (isVideo) "@1s" else "")
        val cacheFile = File(File(context.cacheDir, "video_thumbs"), "$cacheKey.jpg")

        // 1. 命中本地缓存，直接以本地文件返回
        if (cacheFile.exists() && cacheFile.length() > 0) {
            return@withContext SourceResult(
                source = ImageSource(file = cacheFile.toOkioPath()),
                mimeType = "image/jpeg",
                dataSource = DataSource.DISK,
            )
        }

        val target = try {
            SmbTarget.fromPlayUri(uri)
        } catch (e: Exception) {
            Timber.w(e, "Invalid SMB URI for thumbnail: %s", uri)
            return@withContext null
        }

        cacheFile.parentFile?.mkdirs()

        if (isImage) {
            // 加载伴随图片
            try {
                val share = connections.share(target)
                val file = share.openFile(
                    target.basePath,
                    EnumSet.of(AccessMask.GENERIC_READ),
                    null,
                    EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ),
                    SMB2CreateDisposition.FILE_OPEN,
                    null,
                )
                file.inputStream.use { input ->
                    cacheFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                runCatching { file.close() }
                return@withContext SourceResult(
                    source = ImageSource(file = cacheFile.toOkioPath()),
                    mimeType = mimeTypeFor(ext),
                    dataSource = DataSource.NETWORK,
                )
            } catch (e: Exception) {
                Timber.w(e, "Failed to load SMB image for %s", uri)
                return@withContext null
            }
        } else {
            // 视频文件：通过 SmbMediaDataSource 随机读取关键帧抽取缩略图
            val dataSource = SmbMediaDataSource(connections, target)
            val retriever = MediaMetadataRetriever()
            var bitmap: Bitmap? = null
            try {
                retriever.setDataSource(dataSource)
                // 默认取 1.5 秒处的关键帧，避开纯黑片头
                bitmap = retriever.getFrameAtTime(1_500_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: retriever.frameAtTime
            } catch (e: Exception) {
                Timber.w(e, "Failed to extract SMB video thumbnail for %s", uri)
            } finally {
                runCatching { retriever.release() }
                runCatching { dataSource.close() }
            }

            if (bitmap == null) return@withContext null

            // 限制最大边长不超过 384px，低配设备内存优先
            val maxDim = 384
            val scaled = if (bitmap.width > maxDim || bitmap.height > maxDim) {
                val ratio = minOf(maxDim.toFloat() / bitmap.width, maxDim.toFloat() / bitmap.height)
                val w = (bitmap.width * ratio).toInt().coerceAtLeast(1)
                val h = (bitmap.height * ratio).toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(bitmap, w, h, true)
            } else bitmap

            try {
                cacheFile.outputStream().use { out ->
                    scaled.compress(Bitmap.CompressFormat.JPEG, 80, out)
                }
            } finally {
                if (scaled !== bitmap) bitmap.recycle()
                scaled.recycle()
            }

            return@withContext SourceResult(
                source = ImageSource(file = cacheFile.toOkioPath()),
                mimeType = "image/jpeg",
                dataSource = DataSource.NETWORK,
            )
        }
    }

    private fun mimeTypeFor(ext: String) = when (ext) {
        "png" -> "image/png"
        "webp" -> "image/webp"
        else -> "image/jpeg"
    }

    private fun md5(str: String): String =
        MessageDigest.getInstance("MD5").digest(str.toByteArray()).joinToString("") { "%02x".format(it) }

    @Singleton
    class Factory @Inject constructor(
        @ApplicationContext private val context: Context,
        private val connections: SmbConnections,
    ) : Fetcher.Factory<Uri> {
        override fun create(data: Uri, options: Options, imageLoader: ImageLoader): Fetcher? {
            if (data.scheme.equals("smb", ignoreCase = true)) {
                return SmbThumbnailFetcher(context, connections, data, options)
            }
            return null
        }
    }
}
