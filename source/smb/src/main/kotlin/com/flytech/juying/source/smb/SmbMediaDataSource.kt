package com.flytech.juying.source.smb

import android.media.MediaDataSource
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.smbj.share.File
import java.io.IOException
import java.util.EnumSet

/**
 * 包装 SMB 文件为 Android 原生 [MediaDataSource]，用于 [android.media.MediaMetadataRetriever]
 * 在低配设备上以最小 I/O 随机读取远端视频头部/关键帧并抽取封面缩略图。
 */
internal class SmbMediaDataSource(
    private val connections: SmbConnections,
    private val target: SmbTarget,
) : MediaDataSource() {

    private var file: File? = null
    private var size: Long = -1L

    @Synchronized
    private fun ensureOpen(): File {
        file?.let { return it }
        val share = connections.share(target)
        val f = share.openFile(
            target.basePath,
            EnumSet.of(AccessMask.GENERIC_READ),
            null,
            EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ),
            SMB2CreateDisposition.FILE_OPEN,
            null,
        )
        file = f
        size = f.fileInformation.standardInformation.endOfFile
        return f
    }

    @Synchronized
    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        if (size <= 0) return 0
        val currentSize = getSize()
        if (position >= currentSize) return -1
        val currentFile = try {
            ensureOpen()
        } catch (e: Exception) {
            connections.invalidate(target)
            throw IOException("SMB open failed: ${e.message}", e)
        }
        val toRead = minOf(size.toLong(), currentSize - position).toInt()
        val n = try {
            currentFile.read(buffer, position, offset, toRead)
        } catch (e: Exception) {
            connections.invalidate(target)
            throw IOException("SMB read failed: ${e.message}", e)
        }
        return if (n <= 0) -1 else n
    }

    @Synchronized
    override fun getSize(): Long {
        if (size >= 0) return size
        return try {
            ensureOpen().fileInformation.standardInformation.endOfFile.also { size = it }
        } catch (e: Exception) {
            connections.invalidate(target)
            throw IOException("SMB getSize failed: ${e.message}", e)
        }
    }

    @Synchronized
    override fun close() {
        try {
            file?.close()
        } catch (_: Exception) {
        } finally {
            file = null
        }
    }
}
